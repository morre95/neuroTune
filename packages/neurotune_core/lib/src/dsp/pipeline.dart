import 'dart:math';
import 'dart:typed_data';

import '../models.dart';
import 'filters.dart';
import 'welch.dart';

class DspPipeline {
  DspPipeline({
    required this.config,
    required this.sampleRateHz,
    required this.channelNames,
  }) {
    _notch = [
      for (var i = 0; i < channelNames.length; i++)
        SosFilter([
          notchSos(notchHz: config.notchHz, q: config.notchQ, sampleRateHz: sampleRateHz),
        ]),
    ];
    final bandpass = butterBandpassSos(
      order: config.filterOrder,
      lowHz: config.bandpassLowHz,
      highHz: config.bandpassHighHz,
      sampleRateHz: sampleRateHz,
    );
    _bandpass = [for (var i = 0; i < channelNames.length; i++) SosFilter(bandpass)];
    _raw = [for (var i = 0; i < channelNames.length; i++) <double>[]];
    _filtered = [for (var i = 0; i < channelNames.length; i++) <double>[]];
    _contact = [for (var i = 0; i < channelNames.length; i++) <int>[]];
    _accel = <List<double>>[];
    _gyro = <List<double>>[];
  }

  final ExperimentConfig config;
  final double sampleRateHz;
  final List<String> channelNames;

  late final List<SosFilter> _notch;
  late final List<SosFilter> _bandpass;
  late final List<List<double>> _raw;
  late final List<List<double>> _filtered;
  late final List<List<int>> _contact;
  late final List<List<double>> _accel;
  late final List<List<double>> _gyro;

  double? _expectedTime;
  int _nextEnd = 0;
  int _total = 0;
  double _sampleTime0 = 0;
  bool _haveOrigin = false;
  double _gapUntil = -1;

  int get _windowSamples => config.samplesFor(config.welchWindowSeconds, sampleRateHz);
  int get _hopSamples => config.samplesFor(config.welchHopSeconds, sampleRateHz);
  int get _segmentSamples => config.samplesFor(config.welchSegmentSeconds, sampleRateHz);

  List<FeatureFrame> addBatch(EegBatch batch) {
    if (batch.sampleRateHz != sampleRateHz) {
      throw StateError('Batch sample rate ${batch.sampleRateHz} does not match $sampleRateHz');
    }
    if (batch.channelNames.length != channelNames.length) {
      throw StateError('Batch channels do not match the pipeline');
    }
    final dt = 1 / sampleRateHz;
    final frames = <FeatureFrame>[];
    if (_expectedTime != null) {
      final gap = batch.timeSeconds - _expectedTime!;
      if (gap > dt * config.gapSamples) {
        _resetAfterGap(batch.timeSeconds);
        _gapUntil = batch.timeSeconds + config.welchWindowSeconds;
      }
    }
    if (!_haveOrigin) {
      _sampleTime0 = batch.timeSeconds;
      _haveOrigin = true;
      _nextEnd = _windowSamples;
    }
    final count = batch.sampleCount;
    for (var channel = 0; channel < channelNames.length; channel++) {
      for (var sample = 0; sample < count; sample++) {
        final raw = batch.eeg[channel][sample];
        _raw[channel].add(raw);
        final filtered = _bandpass[channel].process(_notch[channel].process(raw));
        _filtered[channel].add(filtered);
        _contact[channel].add(batch.contact[sample][channel]);
      }
    }
    for (var sample = 0; sample < count; sample++) {
      _accel.add(batch.accel[sample]);
      _gyro.add(batch.gyro[sample]);
    }
    _total += count;
    _expectedTime = batch.timeSeconds + count * dt;
    while (_total >= _nextEnd) {
      frames.add(_frameEndingAt(_nextEnd));
      _nextEnd += _hopSamples;
    }
    _discard();
    return frames;
  }

  void _resetAfterGap(double timeSeconds) {
    for (final filter in _notch) {
      filter.reset();
    }
    for (final filter in _bandpass) {
      filter.reset();
    }
    for (final buffer in _raw) {
      buffer.clear();
    }
    for (final buffer in _filtered) {
      buffer.clear();
    }
    for (final buffer in _contact) {
      buffer.clear();
    }
    _accel.clear();
    _gyro.clear();
    _total = 0;
    _sampleTime0 = timeSeconds;
    _nextEnd = _windowSamples;
    _haveOrigin = true;
  }

  FeatureFrame _frameEndingAt(int endSample) {
    final start = endSample - _windowSamples;
    final time = _sampleTime0 + endSample / sampleRateHz;
    final reasons = <String>[];
    if (time <= _gapUntil) reasons.add('gap');
    if (_motion(start, endSample)) reasons.add('motion');
    final rejected = reasons.isNotEmpty;
    final channels = <ChannelFeature>[];
    for (var channel = 0; channel < channelNames.length; channel++) {
      channels.add(_channelFeature(channel, start, endSample, rejected));
    }
    return FeatureFrame(
      timeSeconds: time,
      sampleRateHz: sampleRateHz,
      channels: channels,
      rejected: rejected,
      reasons: reasons,
    );
  }

  ChannelFeature _channelFeature(int channel, int start, int end, bool rejected) {
    final reasons = <String>[];
    final raw = _raw[channel].sublist(_index(start), _index(end));
    final filtered = _filtered[channel].sublist(_index(start), _index(end));
    var worstContact = 1;
    for (var i = _index(start); i < _index(end); i++) {
      worstContact = max(worstContact, _contact[channel][i]);
    }
    if (worstContact >= 3) reasons.add('contact');
    var saturated = false;
    var peakJump = 0.0;
    var sum = 0.0;
    for (var i = 0; i < raw.length; i++) {
      final sample = raw[i];
      sum += sample;
      if (sample.abs() >= config.saturationUv) saturated = true;
      if (i > 0) peakJump = max(peakJump, (sample - raw[i - 1]).abs());
    }
    final mean = sum / raw.length;
    var variance = 0.0;
    for (final sample in raw) {
      final delta = sample - mean;
      variance += delta * delta;
    }
    final std = sqrt(variance / raw.length);
    if (saturated) reasons.add('saturation');
    if (std < config.flatlineStdUv) reasons.add('flatline');
    if (peakJump >= config.jumpUv) reasons.add('jump');
    final valid = reasons.isEmpty && !rejected;
    final powers = valid || filtered.isNotEmpty
        ? bandPowers(
            samples: filtered,
            sampleRateHz: sampleRateHz,
            segmentSamples: _segmentSamples,
            overlap: config.welchOverlap,
            thetaHz: config.thetaHz,
            alphaHz: config.alphaHz,
            betaHz: config.betaHz,
            totalHz: config.totalHz,
          )
        : BandPowers(absoluteTheta: 0, absoluteAlpha: 0, absoluteBeta: 0, total: 0);
    return ChannelFeature(
      name: channelNames[channel],
      valid: valid,
      contact: worstContact,
      absoluteTheta: powers.absoluteTheta,
      absoluteAlpha: powers.absoluteAlpha,
      absoluteBeta: powers.absoluteBeta,
      relativeTheta: powers.relativeTheta,
      relativeAlpha: powers.relativeAlpha,
      relativeBeta: powers.relativeBeta,
      totalPower: powers.total,
      reasons: reasons,
    );
  }

  bool _motion(int start, int end) {
    for (var i = _index(start); i < _index(end); i++) {
      final accel = _accel[i];
      final magnitude = sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
      if ((magnitude - 1).abs() >= config.motionAccelG) return true;
      final gyro = _gyro[i];
      final gyroMag = sqrt(gyro[0] * gyro[0] + gyro[1] * gyro[1] + gyro[2] * gyro[2]);
      if (gyroMag >= config.motionGyroDps) return true;
    }
    return false;
  }

  int _index(int absolute) => absolute - (_total - _raw.first.length);

  void _discard() {
    final keep = _windowSamples + _hopSamples;
    if (_raw.first.length <= keep) return;
    final drop = _raw.first.length - keep;
    for (final buffer in [..._raw, ..._filtered]) {
      buffer.removeRange(0, drop);
    }
    for (final buffer in _contact) {
      buffer.removeRange(0, drop);
    }
    _accel.removeRange(0, drop);
    _gyro.removeRange(0, drop);
  }
}

/// Population standard deviation. Returns 0 for an empty list.
double populationStd(List<double> values) {
  if (values.isEmpty) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  var sum = 0.0;
  for (final value in values) {
    final delta = value - mean;
    sum += delta * delta;
  }
  return sqrt(sum / values.length);
}

double meanOf(List<double> values) => values.reduce((a, b) => a + b) / values.length;

Float64List sine({
  required double hz,
  required double sampleRateHz,
  required int count,
  double amplitude = 1,
}) {
  final output = Float64List(count);
  for (var i = 0; i < count; i++) {
    output[i] = amplitude * sin(2 * pi * hz * i / sampleRateHz);
  }
  return output;
}
