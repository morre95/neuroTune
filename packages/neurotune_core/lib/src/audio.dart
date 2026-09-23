import 'dart:math';
import 'dart:typed_data';

import 'dsp/fft.dart';
import 'models.dart';

/// Stereo binaural tones with linear amplitude ramps.
///
/// A frequency change fades to silence, switches oscillator frequency, then fades
/// back to the shared amplitude so the transition does not click.
class BinauralSynth {
  BinauralSynth({
    required this.sampleRateHz,
    required this.carrierHz,
    required this.amplitude,
    required this.fadeSeconds,
  }) : fadeSamples = max(1, (fadeSeconds * sampleRateHz).round());

  final double sampleRateHz;
  final double carrierHz;
  final double amplitude;
  final double fadeSeconds;
  final int fadeSamples;

  double _phaseLeft = 0;
  double _phaseRight = 0;
  double _freqLeft = 0;
  double _freqRight = 0;
  double _gain = 0;
  double _fadeFrom = 0;
  double _fadeTo = 0;
  int _fadeLeft = 0;
  bool _switchAfterFade = false;
  double _pendingLeft = 0;
  double _pendingRight = 0;

  double get gain => _gain;

  void setAction(StimulusAction? action) {
    if (action == null) {
      _switchAfterFade = false;
      _beginFade(0);
      return;
    }
    final tones = action.tones(carrierHz);
    if (_gain == 0 && _fadeLeft == 0) {
      _freqLeft = tones.$1;
      _freqRight = tones.$2;
      _beginFade(amplitude);
      return;
    }
    if (tones.$1 == _freqLeft &&
        tones.$2 == _freqRight &&
        _fadeTo == amplitude &&
        !_switchAfterFade) {
      return;
    }
    _pendingLeft = tones.$1;
    _pendingRight = tones.$2;
    _switchAfterFade = true;
    _beginFade(0);
  }

  Float64List render(int frames) {
    final output = Float64List(frames * 2);
    for (var i = 0; i < frames; i++) {
      if (_fadeLeft > 0) {
        final t = 1 - (_fadeLeft / fadeSamples);
        _gain = _fadeFrom + (_fadeTo - _fadeFrom) * t;
        _fadeLeft -= 1;
        if (_fadeLeft == 0) {
          _gain = _fadeTo;
          if (_switchAfterFade && _gain == 0) {
            _freqLeft = _pendingLeft;
            _freqRight = _pendingRight;
            _switchAfterFade = false;
            _beginFade(amplitude);
          }
        }
      }
      output[i * 2] = _gain * sin(_phaseLeft);
      output[i * 2 + 1] = _gain * sin(_phaseRight);
      _phaseLeft = _wrap(_phaseLeft + 2 * pi * _freqLeft / sampleRateHz);
      _phaseRight = _wrap(_phaseRight + 2 * pi * _freqRight / sampleRateHz);
    }
    return output;
  }

  void _beginFade(double target) {
    _fadeFrom = _gain;
    _fadeTo = target;
    _fadeLeft = fadeSamples;
  }

  double _wrap(double phase) {
    final turns = phase / (2 * pi);
    return (turns - turns.floor()) * 2 * pi;
  }
}

/// Peak frequency of one channel in an interleaved stereo buffer.
double peakHz(
  Float64List interleaved, {
  required bool left,
  required double sampleRateHz,
}) {
  final frames = interleaved.length ~/ 2;
  final n = 1 << (log(frames) / ln2).floor();
  final channel = Float64List(n);
  final offset = left ? 0 : 1;
  for (var i = 0; i < n; i++) {
    channel[i] = interleaved[(frames - n + i) * 2 + offset];
  }
  final transformed = rfft(channel);
  var best = 0.0;
  var bestHz = 0.0;
  final step = sampleRateHz / n;
  for (var k = 1; k < transformed.real.length; k++) {
    final frequency = k * step;
    if (frequency < 150 || frequency > 300) continue;
    final power =
        transformed.real[k] * transformed.real[k] +
        transformed.imag[k] * transformed.imag[k];
    if (power > best) {
      best = power;
      bestHz = frequency;
    }
  }
  return bestHz;
}
