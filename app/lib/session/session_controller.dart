import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/api_client.dart';
import '../data/repository.dart';
import '../dsp/dsp_isolate.dart';
import '../platform/channels.dart';
import '../ui/session_page.dart';

/// How far ahead of playback the output is kept filled. The writes come from
/// a timer on the UI isolate, which runs late whenever the isolate is busy
/// with headband data; anything less than that delay empties the buffer and
/// every gap is heard as a click.
const _audioLeadSeconds = 0.15;
const _audioTick = Duration(milliseconds: 50);
// A full buffer should drain within a few audio ticks. Also bound the wait
// if the platform channel never replies, so recording cannot run silently.
const _audioWriteTimeout = Duration(seconds: 2);

class SessionController extends ChangeNotifier {
  SessionController({
    required this.repository,
    required this.ownerEmail,
    required this.audio,
    required this.keepAlive,
    required this.config,
    required this.snapshot,
    required this.mode,
    required this.eyeState,
    required this.origin,
    this.sampleRateHz = 256,
  });

  final SessionRepository repository;
  final String ownerEmail;
  final PcmOutput audio;
  final SessionKeepAlive keepAlive;
  final ExperimentConfig config;
  final BanditSnapshot snapshot;
  final SessionMode mode;
  final EyeState eyeState;
  final DataOrigin origin;
  final double sampleRateHz;

  SessionEngine? engine;
  FeatureFrame? latest;
  String? error;
  bool waitingForUser = false;
  bool saved = false;
  double? latencyMs;

  final List<EegBatch> _raw = [];
  final List<OpticsBatch> _opticsRaw = [];
  final List<SessionDiagnostic> _diagnostics = [];
  final DataLossTracker _dataLoss = DataLossTracker();
  final Stopwatch _diagnosticClock = Stopwatch();
  StreamSubscription<SessionDiagnostic>? _diagnosticSub;
  bool _museConnected = false;
  final OpticsAccumulator _optics = OpticsAccumulator();
  SimulatorSource? _source;
  MuseChannel? _muse;
  DspHost? _dsp;
  StreamSubscription<EegBatch>? _batches;
  StreamSubscription<OpticsBatch>? _opticsSub;
  StreamSubscription<void>? _lost;
  StreamSubscription<FeatureFrame>? _frames;
  Timer? _audioTimer;
  final Stopwatch _audioClock = Stopwatch();
  var _audioFramesWritten = 0;
  var _audioWritePending = false;
  var _audioGeneration = 0;
  BinauralSynth? _synth;
  Future<void>? _finish;
  Future<void>? _resuming;
  var _closed = false;
  StopReason? _lastInterruption;

  /// The bridge's clock starts when the headband first streams, which is
  /// before this session because of the contact preview. Session time starts
  /// at the first sample this session receives.
  double? _museOrigin;

  bool get _finishing => _finish != null;

  /// Acquires the foreground service, DSP isolate, data source and audio
  /// output. Returns false with [error] set if any of them fails, leaving the
  /// caller to dispose the controller and keep the user on the contact page.
  Future<bool> start({MuseChannel? muse}) async {
    try {
      await _open(muse);
    } catch (failure) {
      error = 'Sessionen kunde inte starta: $failure';
      // Keep the headband connected so the contact page can retry without
      // scanning again; dispose() only stops a Muse the session owns.
      _muse = null;
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<void> _open(MuseChannel? muse) async {
    await keepAlive.start();
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    final channelNames = muse == null
        ? simulatorChannels
        : const ['EEG1', 'EEG2', 'EEG3', 'EEG4'];
    if (muse == null) {
      _source = SimulatorSource(
        config: config,
        sampleRateHz: sampleRateHz,
        seed: seed,
      );
    } else {
      _muse = muse;
      _museConnected = true;
      _diagnosticClock.start();
      _recordDiagnostic('connection', {'state': 'connected'});
      final battery = muse.batteryPercent.value;
      if (battery != null) {
        _recordDiagnostic('battery', {
          'percent': battery,
          'initial_reading': true,
        });
      }
      _diagnosticSub = muse.diagnostics.listen((event) {
        if (_closed || _finishing) return;
        _recordDiagnostic(event.type, {
          ...event.values,
          'muse_time_seconds': event.timeSeconds,
        });
      });
    }
    engine = SessionEngine(
      config: config,
      snapshot: snapshot,
      sessionId: newSessionId(Random(seed)),
      origin: origin,
      mode: mode,
      eyeState: eyeState,
      sampleRateHz: sampleRateHz,
      channelNames: channelNames,
      seed: seed,
      startedAt: DateTime.now().toUtc(),
    );
    _dsp = await DspHost.start(
      config: config,
      sampleRateHz: sampleRateHz,
      channelNames: channelNames,
    );
    _frames = _dsp!.frames.listen(_onFrame, onError: _onDspFailure);
    if (_source != null) {
      _batches = _source!.batches.listen((batch) {
        _raw.add(batch);
        final optics = _source!.lastOptics;
        if (optics != null) {
          _opticsRaw.add(optics);
          _optics.addBatch(optics);
        }
        _dsp?.addBatch(batch);
      });
    } else {
      _batches = _muse!.eeg.listen((bridged) {
        if (_closed || _finishing) return;
        final batch = bridged.shifted(-_sessionOrigin(bridged.timeSeconds));
        _raw.add(batch);
        _diagnostics.addAll(
          _dataLoss.add(
            stream: 'eeg',
            timeSeconds: batch.timeSeconds,
            sampleRateHz: batch.sampleRateHz,
            channelNames: batch.channelNames,
            samples: batch.eeg,
          ),
        );
        for (final entry in {
          'accelerometer': batch.accel,
          'gyro': batch.gyro,
        }.entries) {
          final invalid = entry.value
              .where((row) => row.any((value) => !value.isFinite))
              .length;
          if (invalid > 0) {
            _diagnostics.add(
              SessionDiagnostic(
                timeSeconds: batch.timeSeconds,
                type: 'invalid_motion',
                values: {'stream': entry.key, 'resampled_rows': invalid},
              ),
            );
          }
        }
        _dsp?.addBatch(batch);
      });
      _opticsSub = _muse!.optics.listen((bridged) {
        if (_closed || _finishing) return;
        final batch = bridged.shifted(-_sessionOrigin(bridged.timeSeconds));
        _opticsRaw.add(batch);
        _diagnostics.addAll(
          _dataLoss.add(
            stream: 'optics',
            timeSeconds: batch.timeSeconds,
            sampleRateHz: batch.sampleRateHz,
            channelNames: batch.channelNames,
            samples: batch.values,
          ),
        );
        _optics.addBatch(batch);
        _releaseFrames();
      });
      _lost = _muse!.disconnected.listen((_) {
        if (_closed || _finishing) return;
        if (!_museConnected) return;
        _museConnected = false;
        _recordDiagnostic('connection', {'state': 'disconnected'});
        interrupt(StopReason.sourceDisconnected);
      });
    }
    _synth = BinauralSynth(
      sampleRateHz: config.audioSampleRateHz.toDouble(),
      carrierHz: config.carrierHz,
      amplitude: config.amplitude,
      fadeSeconds: config.fadeMs / 1000,
    );
    if (await _startAudio()) _source?.start();
  }

  SessionView get view {
    final current = engine;
    final frame = latest;
    final selected = current?.selectedChannels ?? const <String>[];
    final channels = frame?.channels ?? const <ChannelFeature>[];
    final valid = channels
        .where((channel) => channel.valid && frame?.rejected != true)
        .length;
    final names = selected.isEmpty ? config.outerNirChannels : selected;
    final nir = _outerNir(frame, names);
    final nirZ = nir == null || current == null || current.baselineStd == 0
        ? null
        : (nir - current.baselineMean) / current.baselineStd;
    return SessionView(
      message: error ?? current?.message ?? 'Startar session.',
      phase: current?.phase.name ?? 'start',
      blockLabel: '${current?.completedBlocks ?? 0}/${config.blockCount}',
      actionLabel: actionLabel(current?.currentAction?.id),
      theta: _mean(channels, (channel) => channel.relativeTheta),
      alpha: _mean(channels, (channel) => channel.relativeAlpha),
      beta: _mean(channels, (channel) => channel.relativeBeta),
      outerNir: nir == null ? '-' : nir.toStringAsFixed(3),
      nirZ: nirZ == null ? '-' : nirZ.toStringAsFixed(3),
      quality: frame == null ? '-' : '$valid/${channels.length} kanaler',
      canContinue: waitingForUser,
      canStop: current != null && !current.terminal && !waitingForUser,
    );
  }

  void interrupt(StopReason reason) {
    final current = engine;
    if (current == null || current.terminal || _finishing) return;
    current.interrupt(reason);
    _lastInterruption = reason;
    _pauseOutputs();
    waitingForUser = current.phase == SessionPhase.waitingStable;
    if (current.terminal) {
      _finishInBackground();
      return;
    }
    notifyListeners();
  }

  /// A finish that starts while this reconnects the headband waits for it.
  /// Otherwise the audio and the simulator would start again after the
  /// session was saved. A second tap joins the running attempt.
  Future<void> continueSession() {
    if (!waitingForUser || _finishing || _closed) return Future.value();
    return _resuming ??= _resume().whenComplete(() => _resuming = null);
  }

  Future<void> _resume() async {
    try {
      if (_lastInterruption == StopReason.sourceDisconnected && _muse != null) {
        await _muse!.stop();
        await _muse!.start();
        _museConnected = true;
        _recordDiagnostic('connection', {'state': 'connected'});
      }
      if (!await _startAudio()) return;
      engine?.resume();
      waitingForUser = false;
      _lastInterruption = null;
      _source?.start();
      error = null;
    } catch (failure) {
      error = 'Sessionen kunde inte fortsätta: $failure';
      _pauseOutputs();
    }
    if (!_closed) notifyListeners();
  }

  double? _outerNir(FeatureFrame? frame, List<String> selected) {
    if (frame == null || selected.isEmpty) return null;
    final values = <double>[];
    for (final name in selected) {
      final reading = frame.optics.where((channel) => channel.name == name);
      if (reading.isEmpty || !reading.first.valid) return null;
      values.add(reading.first.intensity);
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Saves the session once. The automatic finish when the engine ends and a
  /// tap on the finish button share this future, so a failed save reaches the
  /// caller instead of hiding behind a second call that returned early.
  Future<void> finish() => _finish ??= _finishOnce();

  /// Persisting can fail on a full disk or a closed database. The foreground
  /// service and the headband are released either way, or the app is left with
  /// an ongoing notification and a connected Muse that only a restart clears.
  Future<void> _finishOnce() async {
    try {
      await _resuming;
      final current = engine;
      if (current != null && current.phase == SessionPhase.sound) {
        current.interrupt(StopReason.manual);
      }
      _pauseOutputs();
      if (origin == DataOrigin.muse) {
        _recordDiagnostic('recording_end', {'connected': _museConnected});
        _diagnosticClock.stop();
      }
      if (current != null) await _persist(current);
      saved = true;
    } finally {
      await keepAlive.stop();
      await _muse?.stop();
      _muse = null;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _pauseOutputs();
    _frames?.cancel();
    _batches?.cancel();
    _opticsSub?.cancel();
    _lost?.cancel();
    _diagnosticSub?.cancel();
    _diagnosticClock.stop();
    keepAlive.stop();
    _muse?.stop();
    _dsp?.close();
    super.dispose();
  }

  /// Finishes without a caller to await it, so a failed save is shown in the
  /// session view instead of becoming an unhandled error.
  void _finishInBackground() {
    unawaited(
      finish().catchError((Object failure) {
        error = 'Sessionen kunde inte sparas: $failure';
        if (!_closed) notifyListeners();
      }),
    );
  }

  double _sessionOrigin(double bridgeSeconds) => _museOrigin ??= bridgeSeconds;

  void _recordDiagnostic(String type, Map<String, dynamic> values) {
    _diagnostics.add(
      SessionDiagnostic(
        timeSeconds: _diagnosticClock.elapsedMicroseconds / 1000000,
        type: type,
        values: {...values, 'time_source': 'observed_monotonic'},
      ),
    );
  }

  /// The isolate is dead after an error and no frames will follow, so the
  /// session cannot wait for a stable signal. Save what was recorded.
  void _onDspFailure(Object failure) {
    if (_closed || _finishing) return;
    engine?.abort(
      StopReason.processingFailed,
      'Signalbehandlingen slutade fungera. Sessionen sparas.',
    );
    error = 'Signalbehandlingen slutade fungera: $failure';
    _finishInBackground();
  }

  void _onFrame(FeatureFrame frame) {
    _optics.addFrame(frame);
    _releaseFrames();
  }

  void _releaseFrames() {
    final current = engine;
    // Do not advance or score the protocol while audio acceptance is unknown.
    // Frames stay queued until the packet succeeds or the watchdog aborts.
    if (current == null || _closed || _finishing || _audioWritePending) return;
    final ready = _optics.takeReady(config);
    if (ready.isEmpty) return;
    for (final scored in ready) {
      current.onFrame(scored);
      _synth?.setAction(current.currentAction);
      latest = scored;
      if (current.terminal) {
        _finishInBackground();
        return;
      }
    }
    if (!_closed) notifyListeners();
  }

  /// Returns false when an interruption paused the outputs while the output
  /// started. Writing then would hit the stopped output and end the session as
  /// lost audio instead of waiting for the user to continue.
  Future<bool> _startAudio() async {
    final generation = _audioGeneration;
    latencyMs = await audio.start(config.audioSampleRateHz);
    if (generation != _audioGeneration) return false;
    _audioFramesWritten = 0;
    _audioClock
      ..reset()
      ..start();
    _writeAudio();
    _audioTimer ??= Timer.periodic(_audioTick, (_) => _writeAudio());
    return true;
  }

  /// Keep one packet in flight and drop stale backlog after a long delay.
  /// The native output completes write only once its buffer accepts the data.
  void _writeAudio() {
    final synth = _synth;
    if (synth == null || _finishing || _closed || _audioWritePending) return;
    final rate = config.audioSampleRateHz;
    final due =
        ((_audioLeadSeconds + _audioClock.elapsedMicroseconds / 1e6) * rate)
            .round();
    final frames = min(due - _audioFramesWritten, (rate * 0.2).round());
    if (frames <= 0) return;
    _audioFramesWritten = due;
    final generation = _audioGeneration;
    _audioWritePending = true;
    unawaited(_sendAudio(synth, frames, generation));
  }

  Future<void> _sendAudio(
    BinauralSynth synth,
    int frames,
    int generation,
  ) async {
    try {
      await audio
          .write(encodePcm16(synth.render(frames)))
          .timeout(_audioWriteTimeout);
    } catch (failure) {
      if (generation != _audioGeneration || _closed || _finishing) return;
      engine?.abort(StopReason.audioLost, 'Ljudutgången slutade fungera.');
      error = 'Ljudutgången slutade fungera: $failure';
      _finishInBackground();
    } finally {
      _audioWritePending = false;
      if (generation == _audioGeneration) _releaseFrames();
    }
  }

  void _pauseOutputs() {
    _audioGeneration += 1;
    _audioTimer?.cancel();
    _audioTimer = null;
    _audioClock.stop();
    _synth?.setAction(null);
    _source?.stop();
    audio.stop();
  }

  Future<void> _persist(SessionEngine current) async {
    final diagnostics = List<SessionDiagnostic>.of(_diagnostics)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    final raw = encodeSessionRaw(
      _raw,
      _opticsRaw,
      diagnostics: diagnostics,
      diagnosticsVersion: origin == DataOrigin.muse ? 1 : 0,
    );
    final checksum = sha256Hex(raw);
    final manifest = current.manifest(
      audioLatencyMs: latencyMs,
      checksum: checksum,
      diagnostics: diagnostics,
      diagnosticsVersion: origin == DataOrigin.muse ? 1 : 0,
    );
    final status = current.phase == SessionPhase.completed
        ? 'completed'
        : 'stopped';
    final rawPath = await repository.saveSession(
      manifest: manifest,
      decisions: current.decisions,
      frames: current.frames,
      raw: raw,
      checksum: checksum,
      status: status,
    );
    await repository.enqueueUpload(
      manifest.sessionId,
      checksum,
      rawPath,
      ownerEmail,
    );
  }

  String _mean(
    List<ChannelFeature> channels,
    double Function(ChannelFeature channel) read,
  ) {
    if (channels.isEmpty) return '-';
    final value = channels.map(read).reduce((a, b) => a + b) / channels.length;
    return value.toStringAsFixed(3);
  }
}
