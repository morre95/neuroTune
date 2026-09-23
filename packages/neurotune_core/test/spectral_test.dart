import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  final goldenFile = File('test/goldens/spectral.json');

  test('default config matches contracts/default_experiment.json', () {
    final saved = jsonDecode(
      File('../../contracts/default_experiment.json').readAsStringSync(),
    );
    expect(jsonDecode(defaultExperimentJson), saved);
    expect(ExperimentConfig.defaults().toJson(), saved);
  });

  test('known sines match the SciPy reference', () {
    final golden =
        jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>;
    final fs = (golden['fs'] as num).toDouble();
    final input = (golden['fft_input'] as List<dynamic>)
        .map((value) => (value as num).toDouble())
        .toList();
    final transformed = rfft(input);
    final expectedReal = golden['fft_real'] as List<dynamic>;
    final expectedImag = golden['fft_imag'] as List<dynamic>;
    for (var bin = 0; bin < expectedReal.length; bin++) {
      expect(
        transformed.real[bin],
        closeTo((expectedReal[bin] as num).toDouble(), 1e-9),
      );
      expect(
        transformed.imag[bin],
        closeTo((expectedImag[bin] as num).toDouble(), 1e-9),
      );
    }

    final notch = notchSos(notchHz: 50, q: 30, sampleRateHz: fs);
    final bandpass = butterBandpassSos(
      order: 4,
      lowHz: 1,
      highHz: 40,
      sampleRateHz: fs,
    );
    for (final rawCase in golden['cases'] as List<dynamic>) {
      final item = rawCase as Map<String, dynamic>;
      final hz = (item['hz'] as num).toDouble();
      final count = (item['filtered'] as List<dynamic>).length;
      final samples = sine(
        hz: hz,
        sampleRateHz: fs,
        count: count,
        amplitude: 20,
      );
      final filter = SosFilter([notch, ...bandpass]);
      final filtered = filter.processAll(samples);
      final expected = item['filtered'] as List<dynamic>;
      for (var i = 0; i < filtered.length; i++) {
        expect(
          filtered[i],
          closeTo((expected[i] as num).toDouble(), 1e-6),
          reason: '$hz Hz sample $i',
        );
      }
      final powers = bandPowers(
        samples: filtered.sublist(filtered.length - 1024),
        sampleRateHz: fs,
        segmentSamples: 512,
        overlap: 0.5,
        thetaHz: (4, 8),
        alphaHz: (8, 13),
        betaHz: (13, 30),
        totalHz: (1, 40),
      );
      expect(
        powers.absoluteTheta,
        closeTo((item['theta'] as num).toDouble(), 1e-4),
      );
      expect(
        powers.absoluteAlpha,
        closeTo((item['alpha'] as num).toDouble(), 1e-4),
      );
      expect(
        powers.absoluteBeta,
        closeTo((item['beta'] as num).toDouble(), 1e-4),
      );
      expect(powers.total, closeTo((item['total'] as num).toDouble(), 1e-4));
    }
  });

  test('8 Hz belongs to alpha and not to theta', () {
    final frequencies = Float64List.fromList([7.5, 8.0, 8.5]);
    final psd = Float64List.fromList([0, 4, 0]);
    final spectrum = Spectrum(frequencies, psd);
    expect(integrateBand(spectrum, 4, 8), 0);
    expect(integrateBand(spectrum, 8, 13), greaterThan(0));
  });

  test('normalization matches the reference z-score', () {
    final golden =
        jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>;
    final stats = golden['normalization'] as Map<String, dynamic>;
    final baseline = [
      for (final value in stats['baseline'] as List<dynamic>)
        (value as num).toDouble(),
    ];
    final observed = [
      for (final value in stats['observed'] as List<dynamic>)
        (value as num).toDouble(),
    ];
    final mean = meanOf(baseline);
    final std = populationStd(baseline);
    final reward = meanOf([
      for (final value in observed) (value - mean) / std,
    ]).clamp(-3, 3);
    expect(mean, closeTo((stats['mean'] as num).toDouble(), 1e-12));
    expect(std, closeTo((stats['std'] as num).toDouble(), 1e-12));
    expect(reward, closeTo((stats['reward'] as num).toDouble(), 1e-12));
  });

  test('pipeline reports the right band for each tone', () {
    final config = ExperimentConfig.defaults();
    const fs = 256.0;
    final pipeline = DspPipeline(
      config: config,
      sampleRateHz: fs,
      channelNames: const ['TP9', 'AF7', 'AF8', 'TP10'],
    );
    const tones = [6.0, 10.0, 20.0, 16.0];
    final frames = <FeatureFrame>[];
    for (var start = 0; start < fs * 8; start += 128) {
      final count = min(128, (fs * 8 - start).round());
      frames.addAll(
        pipeline.addBatch(_toneBatch(tones, fs, start / fs, count)),
      );
    }
    final last = frames.last;
    expect(last.channels[0].relativeTheta, greaterThan(0.8));
    expect(last.channels[1].relativeAlpha, greaterThan(0.8));
    expect(last.channels[2].relativeBeta, greaterThan(0.8));
    expect(last.channels.every((channel) => channel.valid), isTrue);
  });
}

EegBatch _toneBatch(List<double> tones, double fs, double time, int count) {
  return EegBatch(
    channelNames: const ['TP9', 'AF7', 'AF8', 'TP10'],
    unit: 'uV',
    sampleRateHz: fs,
    timeSeconds: time,
    eeg: [
      for (final hz in tones)
        [
          for (var i = 0; i < count; i++)
            20 * sin(2 * pi * hz * (time + i / fs)),
        ],
    ],
    accel: List.generate(count, (_) => [0.0, 0.0, 1.0]),
    gyro: List.generate(count, (_) => [0.0, 0.0, 0.0]),
    contact: List.generate(count, (_) => [1, 1, 1, 1]),
  );
}
