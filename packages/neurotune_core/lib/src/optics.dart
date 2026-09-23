import 'dart:math';

import 'models.dart';

/// Collects raw optics and scores each one-second hop.
///
/// LibMuse 8.0.9 names the 850 nm outer channels `OPTICS3` (left) and
/// `OPTICS4` (right) and reports them in microamps. That SDK does not publish
/// a numeric full scale, so a non-finite sample is saturation.
class OpticsAccumulator {
  final List<_OpticsSample> _pending = [];

  void addBatch(OpticsBatch batch) {
    final step = 1 / batch.sampleRateHz;
    for (var sample = 0; sample < batch.sampleCount; sample++) {
      _pending.add(
        _OpticsSample(
          batch.timeSeconds + sample * step,
          {
            for (var channel = 0; channel < batch.channelNames.length; channel++)
              batch.channelNames[channel]: batch.values[channel][sample],
          },
          batch.sampleRateHz,
        ),
      );
    }
  }

  List<OpticsFeature> consumeUntil(
    double endSeconds,
    ExperimentConfig config, {
    required bool motion,
  }) {
    final start = endSeconds - config.welchHopSeconds;
    final window = [
      for (final sample in _pending)
        if (sample.timeSeconds > start && sample.timeSeconds <= endSeconds)
          sample,
    ];
    _pending.removeWhere((sample) => sample.timeSeconds <= endSeconds);
    return _scoreOpticsHop(
      config: config,
      samples: window,
      motion: motion,
    );
  }
}

List<OpticsFeature> _scoreOpticsHop({
  required ExperimentConfig config,
  required List<_OpticsSample> samples,
  required bool motion,
}) {
  final rate = samples.isEmpty ? 64.0 : samples.first.sampleRateHz;
  final expected = max(1, (config.welchHopSeconds * rate).round());
  final short = samples.length < expected - config.gapSamples;
  return [
    for (final name in config.outerNirChannels)
      _scoreChannel(
        name: name,
        values: [for (final sample in samples) sample.values[name]],
        short: short,
        motion: motion,
        flatlineStd: config.opticsFlatlineStdUa,
      ),
  ];
}

OpticsFeature _scoreChannel({
  required String name,
  required List<double?> values,
  required bool short,
  required bool motion,
  required double flatlineStd,
}) {
  final reasons = <String>[];
  final present = [for (final value in values) ?value];
  if (short || present.isEmpty) reasons.add('gap');
  if (present.any((value) => !value.isFinite)) reasons.add('saturation');
  if (present.length >= 2) {
    final mean = present.reduce((a, b) => a + b) / present.length;
    var sum = 0.0;
    for (final value in present) {
      final delta = value - mean;
      sum += delta * delta;
    }
    if (sqrt(sum / present.length) < flatlineStd) reasons.add('flatline');
  } else if (present.length == 1) {
    reasons.add('flatline');
  }
  if (motion) reasons.add('motion');
  final finite = present.where((value) => value.isFinite).toList();
  final intensity = finite.isEmpty
      ? 0.0
      : finite.reduce((a, b) => a + b) / finite.length;
  return OpticsFeature(
    name: name,
    valid: reasons.isEmpty,
    intensity: intensity,
    reasons: reasons,
  );
}

class _OpticsSample {
  _OpticsSample(this.timeSeconds, this.values, this.sampleRateHz);

  final double timeSeconds;
  final Map<String, double> values;
  final double sampleRateHz;
}
