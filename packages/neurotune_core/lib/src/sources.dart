import 'dart:async';
import 'dart:math';

import 'models.dart';

enum SimulatorScenario { clean, tones, gaps, saturation, motion, flatline, response }

/// Names used by the simulator. A Muse source must report the names from the SDK instead.
const simulatorChannels = ['TP9', 'AF7', 'AF8', 'TP10'];

class SimulatorSource {
  SimulatorSource({
    required this.config,
    required this.sampleRateHz,
    required this.seed,
    this.scenario = SimulatorScenario.clean,
    this.channels = simulatorChannels,
    this.chunkSamples = 128,
    this.corruptAfterSeconds,
  }) : random = Random(seed);

  final ExperimentConfig config;
  final double sampleRateHz;
  final int seed;
  final SimulatorScenario scenario;
  final List<String> channels;
  final int chunkSamples;
  final double? corruptAfterSeconds;
  final Random random;

  StimulusAction? action;
  double clock = 0;
  bool _gapInserted = false;
  final _batches = StreamController<EegBatch>.broadcast();
  Timer? _timer;

  Stream<EegBatch> get batches => _batches.stream;

  void start({Duration? interval}) {
    _timer?.cancel();
    final period = interval ?? Duration(milliseconds: (chunkSamples / sampleRateHz * 1000).round());
    _timer = Timer.periodic(period, (_) {
      if (_batches.isClosed) return;
      _batches.add(pull());
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  EegBatch pull([int? samples]) {
    final count = samples ?? chunkSamples;
    if (scenario == SimulatorScenario.gaps && !_gapInserted && clock >= 5) {
      clock += 0.5;
      _gapInserted = true;
    }
    final batch = _synthesize(count);
    clock += count / sampleRateHz;
    return batch;
  }

  EegBatch _synthesize(int count) {
    final eeg = [for (final _ in channels) List<double>.filled(count, 0)];
    final accel = List.generate(count, (_) => [0.0, 0.0, 1.0]);
    final gyro = List.generate(count, (_) => [0.0, 0.0, 0.0]);
    final contact = List.generate(count, (_) => List<int>.filled(channels.length, 1));
    for (var sample = 0; sample < count; sample++) {
      final time = clock + sample / sampleRateHz;
      for (var channel = 0; channel < channels.length; channel++) {
        eeg[channel][sample] = _sample(channel, time);
      }
      if (scenario == SimulatorScenario.motion && time >= 5 && time < 6) {
        accel[sample] = [3, 0, 0];
      }
      if (scenario == SimulatorScenario.saturation && time >= 6 && time < 6.2) {
        for (var channel = 0; channel < channels.length; channel++) {
          eeg[channel][sample] = 2000;
        }
      }
    }
    return EegBatch(
      channelNames: channels,
      unit: 'uV',
      sampleRateHz: sampleRateHz,
      timeSeconds: clock,
      eeg: eeg,
      accel: accel,
      gyro: gyro,
      contact: contact,
    );
  }

  double _sample(int channel, double time) {
    if (corruptAfterSeconds != null && time >= corruptAfterSeconds!) return 2000;
    switch (scenario) {
      case SimulatorScenario.tones:
        const tones = [6.0, 10.0, 20.0, 16.0];
        return 20 * sin(2 * pi * tones[channel] * time);
      case SimulatorScenario.flatline:
        return 0;
      case SimulatorScenario.response:
        final noise = 8 * _gauss();
        final alpha = 6 * sin(2 * pi * 10 * time);
        var thetaAmp = 3.0;
        if (action == StimulusAction.binaural10) thetaAmp = 30;
        final theta = thetaAmp * sin(2 * pi * 6 * time);
        return noise + alpha + theta;
      case SimulatorScenario.clean:
      case SimulatorScenario.gaps:
      case SimulatorScenario.saturation:
      case SimulatorScenario.motion:
        final wobble = 0.15 * sin(2 * pi * 0.1 * time);
        return (12 + wobble) * _gauss() + 5 * sin(2 * pi * 10 * time);
    }
  }

  double _gauss() {
    final u1 = max(random.nextDouble(), 1e-12);
    final u2 = random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}

class PlaybackSource {
  PlaybackSource(this.recording);

  final List<EegBatch> recording;
  final _batches = StreamController<EegBatch>.broadcast();
  var _index = 0;

  Stream<EegBatch> get batches => _batches.stream;

  Future<void> start() async {
    while (_index < recording.length && !_batches.isClosed) {
      _batches.add(recording[_index]);
      _index += 1;
    }
  }

  Future<void> stop() async {}
}

class MuseUnavailable implements Exception {
  MuseUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class MuseSource {
  MuseSource(this.config);
  final ExperimentConfig config;
  final _batches = StreamController<EegBatch>.broadcast();

  Stream<EegBatch> get batches => _batches.stream;

  Future<void> start() async {
    throw MuseUnavailable(
      config.hardwareApproved
          ? 'Muse-SDK:t är inte installerat i den här bygget.'
          : 'Hårdvaruläget är inte verifierat. Fysisk Muse S Athena och SDK krävs.',
    );
  }

  Future<void> stop() async {}
}
