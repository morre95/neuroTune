import 'dart:math';

import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

List<FeatureFrame> qualityFrames({
  double offset = 0,
  double Function(int)? signal,
  int contact = 1,
}) {
  final pipeline = DspPipeline(
    config: ExperimentConfig.defaults(),
    sampleRateHz: 256,
    channelNames: const ['left', 'right'],
  );
  final frames = <FeatureFrame>[];
  for (var chunk = 0; chunk < 24; chunk++) {
    final samples = [
      for (var i = 0; i < 128; i++)
        offset +
            (signal?.call(chunk * 128 + i) ??
                20 * sin(2 * pi * 10 * (chunk * 128 + i) / 256)),
    ];
    frames.addAll(
      pipeline.addBatch(
        EegBatch(
          channelNames: const ['left', 'right'],
          unit: 'uV',
          sampleRateHz: 256,
          timeSeconds: chunk * .5,
          eeg: [samples, samples],
          contact: [
            for (var i = 0; i < 128; i++) [contact, contact],
          ],
          accel: [
            for (var i = 0; i < 128; i++) [0, 0, 1],
          ],
          gyro: [
            for (var i = 0; i < 128; i++) [0, 0, 0],
          ],
        ),
      ),
    );
  }
  return frames;
}

void main() {
  test('a stable EEG baseline does not invalidate a clean oscillation', () {
    // Synthetic microvolt signals; none come from a user recording. A DC
    // reference changes neither oscillation amplitude nor electrode contact.
    for (final offset in [0.0, 1000.0, -1000.0]) {
      final frames = qualityFrames(offset: offset);
      expect(frames, hasLength(9));
      expect(frames.every((frame) => !frame.rejected), isTrue);
      expect(
        frames.every(
          (frame) => frame.channels.every((channel) => channel.valid),
        ),
        isTrue,
        reason: 'clean oscillation with a stable reference',
      );
    }
  });

  test('quantized theta and alpha remain valid with a stable reference', () {
    for (final signal in <double Function(int)>[
      (i) => (20 * sin(2 * pi * 10 * i / 256) * 8).round() / 8,
      (i) => (5 * sin(2 * pi * 4 * i / 256) * 8).round() / 8,
      (i) => (80 * sin(2 * pi * 4 * i / 256) * 8).round() / 8,
      (i) =>
          ((20 * sin(2 * pi * 4 * i / 256) + 5 * sin(2 * pi * 10 * i / 256)) *
                  8)
              .round() /
          8,
    ]) {
      final frames = qualityFrames(offset: 1000, signal: signal);
      expect(
        frames.every(
          (frame) => frame.channels.every((channel) => channel.valid),
        ),
        isTrue,
      );
    }
  });

  test(
    'centering preserves excursion, jump, flatline and missing-sample gates',
    () {
      final signals = <String, double Function(int)>{
        'saturation': (i) => 800 * sin(2 * pi * i / 256),
        'jump': (i) => i % 256 == 128 ? 200 : 20 * sin(2 * pi * 10 * i / 256),
        'flatline': (_) => 0,
        'missing_samples': (i) =>
            i % 256 == 128 ? double.nan : 20 * sin(2 * pi * 10 * i / 256),
      };
      for (final entry in signals.entries) {
        final frames = qualityFrames(offset: 1000, signal: entry.value);
        expect(frames.last.channels.every((channel) => !channel.valid), isTrue);
        expect(frames.last.channels.first.reasons, contains(entry.key));
      }
      final badContact = qualityFrames(offset: 1000, contact: 3);
      expect(
        badContact.last.channels.every((channel) => !channel.valid),
        isTrue,
      );
      expect(badContact.last.channels.first.reasons, contains('contact'));
    },
  );
}
