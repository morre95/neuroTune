import 'dart:math';
import 'dart:typed_data';

import 'fft.dart';

class Spectrum {
  Spectrum(this.frequenciesHz, this.psd);
  final Float64List frequenciesHz;
  final Float64List psd;
}

/// Welch PSD with a periodic Hann window, 50 percent overlap and constant detrend.
///
/// Band edges are half-open: power is summed for `lowHz <= f < highHz`.
Spectrum welchPsd({
  required List<double> samples,
  required double sampleRateHz,
  required int segmentSamples,
  required double overlap,
}) {
  final hop = (segmentSamples * (1 - overlap)).round();
  final window = Float64List(segmentSamples);
  var windowEnergy = 0.0;
  for (var i = 0; i < segmentSamples; i++) {
    window[i] = 0.5 - 0.5 * cos(2 * pi * i / segmentSamples);
    windowEnergy += window[i] * window[i];
  }
  final scale = 1 / (sampleRateHz * windowEnergy);
  final bins = segmentSamples ~/ 2 + 1;
  final accumulator = Float64List(bins);
  var count = 0;
  for (var start = 0; start + segmentSamples <= samples.length; start += hop) {
    var mean = 0.0;
    for (var i = 0; i < segmentSamples; i++) {
      mean += samples[start + i];
    }
    mean /= segmentSamples;
    final real = Float64List(segmentSamples);
    for (var i = 0; i < segmentSamples; i++) {
      real[i] = (samples[start + i] - mean) * window[i];
    }
    final transformed = rfft(real);
    for (var bin = 0; bin < bins; bin++) {
      var power =
          transformed.real[bin] * transformed.real[bin] +
          transformed.imag[bin] * transformed.imag[bin];
      power *= scale;
      final edge = bin == 0 || bin == bins - 1;
      if (!edge) power *= 2;
      accumulator[bin] += power;
    }
    count += 1;
  }
  if (count == 0) {
    throw ArgumentError('Signal is shorter than one Welch segment');
  }
  for (var bin = 0; bin < bins; bin++) {
    accumulator[bin] /= count;
  }
  final frequencies = Float64List(bins);
  for (var bin = 0; bin < bins; bin++) {
    frequencies[bin] = bin * sampleRateHz / segmentSamples;
  }
  return Spectrum(frequencies, accumulator);
}

double integrateBand(Spectrum spectrum, double lowHz, double highHz) {
  if (spectrum.frequenciesHz.length < 2) return 0;
  final df = spectrum.frequenciesHz[1] - spectrum.frequenciesHz[0];
  var power = 0.0;
  for (var bin = 0; bin < spectrum.frequenciesHz.length; bin++) {
    final frequency = spectrum.frequenciesHz[bin];
    if (frequency >= lowHz && frequency < highHz) {
      power += spectrum.psd[bin] * df;
    }
  }
  return power;
}

class BandPowers {
  BandPowers({
    required this.absoluteTheta,
    required this.absoluteAlpha,
    required this.absoluteBeta,
    required this.total,
  });

  final double absoluteTheta;
  final double absoluteAlpha;
  final double absoluteBeta;
  final double total;

  double _relative(double absolute) => total == 0 ? 0 : absolute / total;

  double get relativeTheta => _relative(absoluteTheta);
  double get relativeAlpha => _relative(absoluteAlpha);
  double get relativeBeta => _relative(absoluteBeta);
}

BandPowers bandPowers({
  required List<double> samples,
  required double sampleRateHz,
  required int segmentSamples,
  required double overlap,
  required (double, double) thetaHz,
  required (double, double) alphaHz,
  required (double, double) betaHz,
  required (double, double) totalHz,
}) {
  final spectrum = welchPsd(
    samples: samples,
    sampleRateHz: sampleRateHz,
    segmentSamples: segmentSamples,
    overlap: overlap,
  );
  return BandPowers(
    absoluteTheta: integrateBand(spectrum, thetaHz.$1, thetaHz.$2),
    absoluteAlpha: integrateBand(spectrum, alphaHz.$1, alphaHz.$2),
    absoluteBeta: integrateBand(spectrum, betaHz.$1, betaHz.$2),
    total: integrateBand(spectrum, totalHz.$1, totalHz.$2),
  );
}
