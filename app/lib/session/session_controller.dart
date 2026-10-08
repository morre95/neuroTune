import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/api_client.dart';
import '../data/canonical_wave.dart';
import '../audio/meditation_renderer.dart';
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

/// Verified immutable setup. Additional metadata and a reserved ID let durable
/// calibration attempts attach to the same lifecycle before audio acquisition.
class MeditationSetup {
  const MeditationSetup({
    required this.profile,
    required this.file,
    required this.action,
    this.metadata = const {},
  });
  final AudioProfileVersion profile;
  final File file;
  final StimulusAction action;
  final Map<String, dynamic> metadata;
}

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
    this.protocolFactory,
    this.meditation,
    this.reservedSessionId,
    this.beforeAcquire,
    this.observedTimeSeconds,
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
  final SessionProtocolFactory? protocolFactory;
  final MeditationSetup? meditation;
  final String? reservedSessionId;
  final Future<void> Function(String sessionId)? beforeAcquire;

  /// Monotonic time boundary; source clocks and PCM frames remain independent.
  final double Function()? observedTimeSeconds;
  double get _observedSeconds =>
      observedTimeSeconds?.call() ??
      _playbackObserved.elapsedMicroseconds / 1e6;
  MeditationRenderer? _renderer;
  Future<void>? _playbackPump;
  int _playbackBase = 0;
  int _playedFrames = 0;
  final Stopwatch _playbackObserved = Stopwatch();
  double _lastPlayedObserved = 0;
  bool get isMeditation => meditation != null;

  /// Absolute rendered cursor to resume after flushing unplayed packets.
  int get activePlaybackFrames => _playedFrames;
  int get acceptedPlaybackFrames => _audioFramesWritten;

  SessionProtocol? engine;
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
  Future<bool> start({MuseChannel? muse}) {
    if (_closed || _finishing) return Future.value(false);
    return _starting ??= _start(muse);
  }

  Future<bool>? _starting;

  Future<bool> _start(MuseChannel? muse) async {
    if (_closed || _finishing) return false;
    try {
      await _open(muse);
    } catch (failure) {
      error = 'Sessionen kunde inte starta: $failure';
      // Keep the headband connected so the contact page can retry without
      // scanning again; dispose() only stops a Muse the session owns.
      _muse = null;
      return false;
    }
    if (_closed || _finishing) return false;
    notifyListeners();
    return true;
  }

  Future<void> _open(MuseChannel? muse) async {
    _playbackObserved.start();
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    final sessionId = reservedSessionId ?? newSessionId(Random(seed));
    final setup = meditation;
    if (setup != null) {
      if (audio is! PcmPlaybackProgress) {
        throw StateError('Played audio progress is required');
      }
      await CanonicalWave.verify(
        setup.file,
        setup.profile.checksumSha256,
        setup.profile.durationSeconds,
      );
    }
    await beforeAcquire?.call(sessionId);
    if (_closed || _finishing) return;
    await keepAlive.start();
    if (_closed || _finishing) {
      await keepAlive.stop();
      return;
    }
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
    final context = SessionContext(
      sessionId: sessionId,
      origin: origin,
      eyeState: eyeState,
      sampleRateHz: sampleRateHz,
      channelNames: channelNames,
      seed: seed,
      startedAt: DateTime.now().toUtc(),
    );
    engine = setup != null
        ? MeditationProtocol(
            context: context,
            profile: setup.profile,
            action: setup.action,
            metadata: {
              ...setup.metadata,
              'quality_version': config.qualityVersion,
              'eeg_config': config.toJson(),
            },
          )
        : protocolFactory?.call(context) ??
              SessionEngine(
                config: config,
                snapshot: snapshot,
                sessionId: context.sessionId,
                origin: origin,
                mode: mode,
                eyeState: eyeState,
                sampleRateHz: sampleRateHz,
                channelNames: channelNames,
                seed: seed,
                startedAt: context.startedAt,
              );
    _dsp = await DspHost.start(
      config: config,
      sampleRateHz: sampleRateHz,
      channelNames: channelNames,
    );
    if (_closed || _finishing) {
      _dsp!.close();
      _dsp = null;
      return;
    }
    _frames = _dsp!.frames.listen(_onFrame, onError: _onDspFailure);
    if (_source != null) {
      _batches = _source!.batches.listen((batch) {
        _raw.add(batch);
        _anchorSource(batch);
        final optics = _source!.lastOptics;
        if (optics != null) {
          _opticsRaw.add(optics);
          engine?.queueOptics(optics);
        }
        _dsp?.addBatch(batch);
      });
    } else {
      _batches = _muse!.eeg.listen((bridged) {
        if (_closed || _finishing) return;
        final batch = bridged.shifted(-_sessionOrigin(bridged.timeSeconds));
        _raw.add(batch);
        _anchorSource(batch);
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
        engine?.queueOptics(batch);
        _releaseFrames();
      });
      _lost = _muse!.disconnected.listen((_) {
        if (_closed || _finishing) return;
        if (!_museConnected) return;
        _museConnected = false;
        _recordDiagnostic('connection', {'state': 'disconnected'});
        if (!isMeditation) interrupt(StopReason.sourceDisconnected);
      });
    }
    _synth = BinauralSynth(
      sampleRateHz: config.audioSampleRateHz.toDouble(),
      carrierHz: config.carrierHz,
      amplitude: config.amplitude,
      fadeSeconds: config.fadeMs / 1000,
    );
    if (setup != null) {
      _renderer = await MeditationRenderer.open(
        setup.file,
        setup.profile,
        setup.action,
      );
      if (_closed || _finishing) {
        await _renderer!.close();
        _renderer = null;
        return;
      }
    }
    await _startOutputs();
  }

  SessionView get view {
    final current = engine;
    final frame = latest;
    // Experiment-only metrics stay in the NIR presentation path. Alternative
    // protocols share lifecycle state without needing a baseline or optics.
    final nirEngine = current is SessionEngine ? current : null;
    final selected = nirEngine?.selectedChannels ?? const <String>[];
    final channels = frame?.channels ?? const <ChannelFeature>[];
    final valid = channels
        .where((channel) => channel.valid && frame?.rejected != true)
        .length;
    final names = selected.isEmpty ? config.outerNirChannels : selected;
    final nir = _outerNir(frame, names);
    final nirZ = nir == null || nirEngine == null || nirEngine.baselineStd == 0
        ? null
        : (nir - nirEngine.baselineMean) / nirEngine.baselineStd;
    return SessionView(
      meditation: isMeditation,
      activeSeconds: isMeditation ? _playedFrames / 48000 : null,
      message: error ?? current?.message ?? 'Startar session.',
      phase: current?.phase.name ?? 'start',
      blockLabel: '${nirEngine?.completedBlocks ?? 0}/${config.blockCount}',
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
    if (isMeditation && reason == StopReason.sourceDisconnected) return;
    if (isMeditation && reason == StopReason.manual) {
      _finishInBackground();
      return;
    }
    current.interrupt(reason);
    _lastInterruption = reason;
    _pauseOutputs();
    waitingForUser = current.waitingForResume;
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
      if (!await _startOutputs()) return;
      engine?.resume();
      waitingForUser = false;
      _lastInterruption = null;
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
      await _starting;
      await _resuming;
      final current = engine;
      if (isMeditation) {
        _audioTimer?.cancel();
        _audioTimer = null;
        await _playbackPump;
        if (current != null && !current.terminal && !current.waitingForResume) {
          await _stopRamp();
        }
        final meditationProtocol = current as MeditationProtocol?;
        if (meditationProtocol != null) {
          for (var i = 0; i < meditationProtocol.frames.length; i++) {
            meditationProtocol.frames[i] = meditationProtocol.mapFrame(
              meditationProtocol.frames[i],
              config.welchWindowSeconds,
            );
          }
        }
      }
      current?.finish();
      _pauseOutputs();
      await _renderer?.close();
      _renderer = null;
      if (origin == DataOrigin.muse) {
        _recordDiagnostic('recording_end', {'connected': _museConnected});
        _diagnosticClock.stop();
      }
      if (current != null) await _persist(current);
      saved = true;
    } finally {
      await audio.stop();
      _dsp?.close();
      _dsp = null;
      await _frames?.cancel();
      await _batches?.cancel();
      await _opticsSub?.cancel();
      await _lost?.cancel();
      await _diagnosticSub?.cancel();
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
    unawaited(_renderer?.close());
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
    if (isMeditation) {
      _recordDiagnostic('processing_failed', {'error': '$failure'});
      _dsp?.close();
      _dsp = null;
      return;
    }
    engine?.abort(
      StopReason.processingFailed,
      'Signalbehandlingen slutade fungera. Sessionen sparas.',
    );
    error = 'Signalbehandlingen slutade fungera: $failure';
    _finishInBackground();
  }

  void _onFrame(FeatureFrame frame) {
    engine?.queueFrame(frame);
    _releaseFrames();
  }

  void _releaseFrames() {
    final current = engine;
    // Do not advance or score the protocol while audio acceptance is unknown.
    // Frames stay queued until the packet succeeds or the watchdog aborts.
    if (current == null || _closed || _finishing || _audioWritePending) return;
    final ready = current.takeReadyFrames();
    if (ready.isEmpty) return;
    for (final scored in ready) {
      current.onFrame(scored);
      _synth?.setAction(current.currentAction);
      latest = current is MeditationProtocol
          ? current.mapFrame(scored, config.welchWindowSeconds)
          : scored;
      if (current.terminal) {
        _finishInBackground();
        return;
      }
    }
    if (!_closed) notifyListeners();
  }

  /// Starts the audio and the simulator; the counterpart of [_pauseOutputs].
  /// Returns false when an interruption paused the outputs while the audio
  /// started. That start is stopped again, since [PcmOutput] does not promise
  /// that the earlier stop ran after it, and its latency is not kept. Writing
  /// would hit the stopped output and end the session as lost audio instead
  /// of waiting for the user to continue.
  Future<bool> _startOutputs() async {
    if (_closed || _finishing) return false;
    final generation = _audioGeneration;
    final latency = await audio.start(config.audioSampleRateHz);
    if (generation != _audioGeneration || _closed || _finishing) {
      unawaited(audio.stop());
      return false;
    }
    latencyMs = latency;
    _audioFramesWritten = 0;
    if (isMeditation) {
      _playbackBase = _playedFrames;
      _audioFramesWritten = _playedFrames;
      _playbackObserved.start();
      _lastPlayedObserved = _observedSeconds;
      (engine as MeditationProtocol).playback(
        _playedFrames,
        _lastPlayedObserved,
      );
    }
    _audioClock
      ..reset()
      ..start();
    _writeAudio();
    _audioTimer ??= Timer.periodic(_audioTick, (_) => _writeAudio());
    _source?.start();
    return true;
  }

  /// Keep one packet in flight and drop stale backlog after a long delay.
  /// The native output completes write only once its buffer accepts the data.
  void _writeAudio() {
    if (isMeditation) {
      unawaited(pumpPlayback());
      return;
    }
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
    if (engine is MeditationProtocol) {
      (engine as MeditationProtocol).playback(
        _playedFrames,
        _observedSeconds,
        active: false,
      );
    }
    audio.stop();
  }

  void _anchorSource(EegBatch batch) {
    if (engine is MeditationProtocol) {
      (engine as MeditationProtocol).sourceAnchor(
        batch.timeSeconds,
        _observedSeconds - batch.sampleCount / batch.sampleRateHz,
      );
    }
  }

  /// Pumps bounded PCM using actual device consumption. Useful for virtual
  /// devices and interruption integration; concurrent callers join one request.
  Future<void> pumpPlayback() {
    if (!isMeditation || _closed || _finishing || waitingForUser) {
      return Future.value();
    }
    return _playbackPump ??= _pumpPlayback().whenComplete(
      () => _playbackPump = null,
    );
  }

  Future<void> _readPlayed(int generation) async {
    final local = await (audio as PcmPlaybackProgress).playedFrames().timeout(
      _audioWriteTimeout,
    );
    if (generation != _audioGeneration || _closed) return;
    final played = (_playbackBase + local).clamp(
      _playedFrames,
      _audioFramesWritten,
    );
    final observed = _observedSeconds;
    if (played > _playedFrames) {
      _playedFrames = played;
      _lastPlayedObserved = observed;
    }
    if (_audioFramesWritten > _playedFrames &&
        observed - _lastPlayedObserved > 2) {
      throw StateError('Audio playback stopped progressing');
    }
    (engine as MeditationProtocol).playback(_playedFrames, observed);
  }

  Future<void> _pumpPlayback() async {
    final renderer = _renderer;
    if (renderer == null || engine?.terminal == true) return;
    final generation = _audioGeneration;
    try {
      await _readPlayed(generation);
      if (generation != _audioGeneration || _closed || _finishing) return;
      if (engine!.terminal) {
        _finishInBackground();
        return;
      }
      final due = min(MeditationRenderer.durationFrames, _playedFrames + 7200);
      final frames = min(
        due - _audioFramesWritten,
        MeditationRenderer.maxPacketFrames,
      );
      if (frames > 0) {
        _audioWritePending = true;
        final pcm = await renderer
            .render(_audioFramesWritten, frames)
            .timeout(_audioWriteTimeout);
        if (generation != _audioGeneration || _closed || _finishing) return;
        await audio.write(pcm).timeout(_audioWriteTimeout);
        if (generation != _audioGeneration || _closed) return;
        _audioFramesWritten += frames;
      }
      _releaseFrames();
      if (!_closed) notifyListeners();
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

  Future<void> _stopRamp() async {
    try {
      await _readPlayed(_audioGeneration);
      await audio.stop();
      if (_closed) return;
      await audio.start(48000).timeout(_audioWriteTimeout);
      _playbackBase = _playedFrames;
      final frames = min(
        7200,
        MeditationRenderer.durationFrames - _playedFrames,
      );
      if (frames <= 0) return;
      final pcm = await _renderer!.render(
        _playedFrames,
        frames,
        stopping: true,
      );
      await audio.write(pcm).timeout(_audioWriteTimeout);
      _audioFramesWritten = _playedFrames + frames;
      _lastPlayedObserved = _observedSeconds;
      while (_playedFrames < _audioFramesWritten && !_closed) {
        await _readPlayed(_audioGeneration);
        if (_playedFrames < _audioFramesWritten) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    } catch (failure) {
      engine?.abort(StopReason.audioLost, 'Ljudutgången slutade fungera.');
      error = 'Ljudutgången slutade fungera: $failure';
    }
  }

  Future<void> _persist(SessionProtocol current) async {
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
