import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart' show PlatformException;
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
    this.model,
    this.statistics,
    this.saveStatistics,
  });
  final PersonalEegModel? model;
  final MeditationActionStatistics? statistics;
  final Future<void> Function(MeditationActionStatistics)? saveStatistics;
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
    required ExperimentConfig config,
    required BanditSnapshot snapshot,
    required this.mode,
    required this.eyeState,
    required this.origin,
    this.sampleRateHz = 256,
    this.protocolFactory,
    this.meditation,
    this.reservedSessionId,
    this.beforeAcquire,
    this.observedTimeSeconds,
    this.randomUnit,
  }) : config = config.forCurrentProcessing(),
       snapshot = _currentSnapshot(config, origin, snapshot);

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
  final double Function()? randomUnit;
  final double Function()? observedTimeSeconds;
  double get _observedSeconds =>
      observedTimeSeconds?.call() ??
      _playbackObserved.elapsedMicroseconds / 1e6;
  MeditationRenderer? _renderer;
  Future<void>? _playbackPump;
  Future<void>? _pausing;
  StreamSubscription<PcmInterruption>? _audioEvents;
  Future<double?>? _outputStart;
  bool _outputAcquired = false;
  int _inFlightFrames = 0;
  int _playbackBase = 0;
  int _playedFrames = 0;
  int _startupThresholdFrames = 0;
  int _paddingFrames = 0;
  final Stopwatch _playbackObserved = Stopwatch();
  double _lastPlayedObserved = 0;
  final Stopwatch _progressStall = Stopwatch();
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
      _pauseOutputs();
      await _pausing;
      _source?.stop();
      Future<void> release(
        FutureOr<void> Function() operation,
        String resource,
      ) async {
        try {
          await operation();
        } catch (cleanup) {
          _recordDiagnostic('cleanup_failed', {
            'resource': resource,
            'error': '$cleanup',
          });
        }
      }

      await release(keepAlive.stop, 'keep_alive');
      await release(() async {
        await _audioEvents?.cancel();
      }, 'audio_events');
      await release(() async {
        await _frames?.cancel();
      }, 'frames');
      await release(() async {
        await _batches?.cancel();
      }, 'eeg');
      await release(() async {
        await _opticsSub?.cancel();
      }, 'optics');
      await release(() async {
        await _lost?.cancel();
      }, 'connection');
      await release(() async {
        await _diagnosticSub?.cancel();
      }, 'diagnostics');
      await release(() => _dsp?.close(), 'dsp');
      await release(() async {
        await _renderer?.close();
      }, 'renderer');
      _renderer = null;
      if (isMeditation && engine != null && !_closed && !_finishing) {
        _audioFailed(failure);
      }
      return false;
    }
    if (_closed || _finishing) return false;
    notifyListeners();
    return true;
  }

  Future<void> _open(MuseChannel? muse) async {
    _playbackObserved.start();
    _diagnosticClock.start();
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
    MeditationAdaptation? adaptation;
    final model = setup?.model;
    if (setup != null &&
        model != null &&
        setup.metadata['mode'] != 'calibration' &&
        model.ownerAccountId == setup.metadata['owner_account_id'] &&
        model.ownerAccountId == setup.profile.ownerAccountId &&
        model.origin == origin.name &&
        model.unsupportedReason(
              backgroundAssetId: setup.profile.backgroundAssetId,
              eyeState: eyeState.name,
              carrierHz: setup.profile.carrierHz,
              toneGain: setup.profile.toneGain,
              backgroundGain: setup.profile.backgroundGain,
              eegConfig: config,
            ) ==
            null) {
      final scope = MeditationSetupContext(
        profile: setup.profile,
        eyeState: eyeState,
        origin: origin,
      );
      final stats =
          setup.statistics ??
          MeditationActionStatistics.seeded(model.ownerAccountId, scope, model);
      if (stats.setup.key == scope.key &&
          stats.owner == model.ownerAccountId &&
          stats.model.modelVersion == model.modelVersion) {
        adaptation = MeditationAdaptation(
          statistics: MeditationActionStatistics.fromJson(
            stats.toJson(),
            model.ownerAccountId,
            scope,
            model,
          ),
          initialAction: setup.action,
          randomUnit: randomUnit ?? Random(seed).nextDouble,
        );
      }
    }
    engine = setup != null
        ? MeditationProtocol(
            context: context,
            profile: setup.profile,
            adaptation: adaptation,
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
    if (audio is PcmInterruptionSource) {
      _audioEvents = (audio as PcmInterruptionSource).interruptions.listen((
        event,
      ) {
        if (_closed) return;
        _recordDiagnostic('audio_interruption', {
          'reason': event.reason,
          'available': event.available,
        });
        if (!event.available) {
          if (_finishing && isMeditation) {
            _pauseOutputs();
          } else {
            interrupt(StopReason.background);
          }
        }
      }, onError: (Object failure) => _audioFailed(failure));
    }
    if (isMeditation) _source?.start();
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
      if (isMeditation) {
        await _starting;
        await _pausing;
        if (_closed || _finishing) return;
      }
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
      if (isMeditation) _audioFailed(failure);
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
    Object? failure;
    StackTrace? failureStack;
    try {
      await _starting;
      await _resuming;
      await _pausing;
      final current = engine;
      if (isMeditation) {
        _audioTimer?.cancel();
        _audioTimer = null;
        await _playbackPump;
        if (current != null && !current.terminal && !current.waitingForResume) {
          await _stopRamp();
        }
        _pauseOutputs();
        await _pausing;
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
      if (!isMeditation) _pauseOutputs();
      await _pausing;
      _source?.stop();
      await _renderer?.close();
      _renderer = null;
      if (origin == DataOrigin.muse) {
        _recordDiagnostic('recording_end', {'connected': _museConnected});
        _diagnosticClock.stop();
      }
      if (current != null) await _persist(current);
      saved = true;
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    // Cleanup steps are independent: one failing platform call must not keep
    // the foreground service, subscriptions or headband alive. Preserve the
    // original persistence failure when cleanup also reports an error.
    Future<void> release(FutureOr<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await release(audio.stop);
    await release(() async {
      await _audioEvents?.cancel();
    });
    final dsp = _dsp;
    _dsp = null;
    await release(() => dsp?.close());
    await release(() async {
      await _frames?.cancel();
    });
    await release(() async {
      await _batches?.cancel();
    });
    await release(() async {
      await _opticsSub?.cancel();
    });
    await release(() async {
      await _lost?.cancel();
    });
    await release(() async {
      await _diagnosticSub?.cancel();
    });
    await release(keepAlive.stop);
    final muse = _muse;
    _muse = null;
    await release(() async {
      await muse?.stop();
    });
    if (!_closed) notifyListeners();
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  @override
  void dispose() {
    _closed = true;
    _pauseOutputs();
    if (isMeditation) {
      // Resumable pauses retain focus. Terminal disposal must abandon it after
      // a held start/checkpoint settles, including a start that acquired late.
      _cleanupInBackground(() async {
        try {
          await _pausing;
        } finally {
          await audio.stop();
        }
      }, 'audio');
    }
    _source?.stop();
    _audioEvents?.cancel();
    _frames?.cancel();
    _batches?.cancel();
    _opticsSub?.cancel();
    _lost?.cancel();
    _diagnosticSub?.cancel();
    _diagnosticClock.stop();
    _cleanupInBackground(keepAlive.stop, 'keep_alive');
    _cleanupInBackground(() async {
      await _muse?.stop();
    }, 'muse');
    _cleanupInBackground(() => _dsp?.close(), 'dsp');
    _cleanupInBackground(() async {
      await _renderer?.close();
    }, 'renderer');
    super.dispose();
  }

  /// Finishes without a caller to await it, so a failed save is shown in the
  /// session view instead of becoming an unhandled error.
  void _finishInBackground() {
    unawaited(
      finish().catchError((Object failure) {
        error = saved
            ? 'Sessionen är sparad, men resurserna kunde inte stängas: $failure'
            : 'Sessionen kunde inte sparas: $failure';
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

  void _releaseFrames({bool finalCheckpoint = false}) {
    final current = engine;
    // Do not advance or score the protocol while audio acceptance is unknown.
    // Frames stay queued until the packet succeeds or the watchdog aborts.
    if (current == null ||
        _closed ||
        (_finishing && !finalCheckpoint) ||
        _audioWritePending) {
      return;
    }
    final ready = current.takeReadyFrames();
    if (ready.isEmpty) return;
    for (final scored in ready) {
      current.onFrame(scored);
      _synth?.setAction(current.currentAction);
      latest = current is MeditationProtocol
          ? current.mapFrame(scored, config.welchWindowSeconds)
          : scored;
      if (current.terminal && current is! MeditationProtocol) {
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
    final starting = audio.start(
      isMeditation ? MeditationRenderer.sampleRate : config.audioSampleRateHz,
    );
    _outputStart = starting;
    double? latency;
    try {
      latency = await starting;
    } on PlatformException catch (failure) {
      if (failure.code != 'AUDIO_FOCUS_DENIED' || !isMeditation) rethrow;
      _recordDiagnostic('audio_interruption', {
        'reason': 'focus_denied',
        'available': false,
      });
      interrupt(StopReason.background);
      return false;
    }
    _outputAcquired = true;
    if (generation != _audioGeneration || _closed || _finishing) {
      if (!isMeditation) _cleanupInBackground(audio.stop, 'audio');
      return false;
    }
    latencyMs = latency;
    _audioFramesWritten = 0;
    if (isMeditation) {
      _playbackBase = _playedFrames;
      _startupThresholdFrames = 0;
      _paddingFrames = 0;
      _audioFramesWritten = _playedFrames;
      _playbackObserved.start();
      _lastPlayedObserved = _observedSeconds;
      _progressStall
        ..reset()
        ..start();
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
    if (!isMeditation) _source?.start();
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
      _audioFailed(failure);
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
    if (isMeditation) {
      _pausing ??= _pauseMeditation().whenComplete(() => _pausing = null);
    } else {
      _source?.stop();
      _cleanupInBackground(audio.stop, 'audio');
    }
  }

  /// Invalidate writes synchronously, then join a held start and take the
  /// device checkpoint before flushing. Recording/DSP continue during pauses.
  Future<void> _pauseMeditation() async {
    bool paused = false;
    try {
      // A rejected focus request acquired nothing; other start failures are
      // handled by start/resume. Still stop defensively below.
      try {
        await _outputStart;
      } catch (_) {}
      if (_outputAcquired) {
        final local = audio is PcmInterruptionSource
            ? await (audio as PcmInterruptionSource)
                  .pauseAndCheckpoint()
                  .timeout(_audioWriteTimeout)
            : await (audio as PcmPlaybackProgress).playedFrames().timeout(
                _audioWriteTimeout,
              );
        paused = audio is PcmInterruptionSource;
        _playedFrames = (_playbackBase + local).clamp(
          _playedFrames,
          _audioFramesWritten + _inFlightFrames,
        );
        (engine as MeditationProtocol?)?.playback(
          _playedFrames,
          _observedSeconds,
        );
      }
    } catch (failure) {
      _recordDiagnostic('audio_checkpoint_failed', {'error': '$failure'});
      _audioFailed(failure);
    }
    (engine as MeditationProtocol?)?.playback(
      _playedFrames,
      _observedSeconds,
      active: false,
    );
    if (!paused) {
      try {
        await audio.stop().timeout(_audioWriteTimeout);
      } catch (failure) {
        _recordDiagnostic('cleanup_failed', {
          'resource': 'audio',
          'error': '$failure',
        });
        _audioFailed(failure);
      }
    }
    _outputAcquired = false;
    await _playbackPump;
    _audioWritePending = false;
    _inFlightFrames = 0;
    if (!_closed) {
      _releaseFrames(finalCheckpoint: true);
      await _evaluateMeditation(selectNext: false);
    }
  }

  void _audioFailed(Object failure) {
    if (_closed || _finishing) return;
    _recordDiagnostic('audio_failed', {
      'error': '$failure',
      ..._playbackCounters(),
    });
    if (kDebugMode) {
      debugPrint('NeuroTunePlayback failure=$failure ${_playbackCounters()}');
    }
    engine?.abort(StopReason.audioLost, 'Ljudutgången slutade fungera.');
    error = 'Ljudutgången slutade fungera: $failure';
    _finishInBackground();
  }

  void _cleanupInBackground(
    FutureOr<void> Function() operation,
    String resource,
  ) {
    unawaited(
      Future<void>.sync(operation).catchError((Object failure) {
        _recordDiagnostic('cleanup_failed', {
          'resource': resource,
          'error': '$failure',
        });
        if (!_closed) {
          error = 'Resursen kunde inte stängas ($resource): $failure';
          notifyListeners();
        }
      }),
    );
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

  Map<String, Object> _playbackCounters() => {
    'played_frames': _playedFrames,
    'written_frames': _audioFramesWritten,
    'in_flight_frames': _inFlightFrames,
    'padding_frames': _paddingFrames,
    'startup_threshold_frames': _startupThresholdFrames,
    'playback_base_frames': _playbackBase,
    'observed_seconds': _observedSeconds,
    'last_played_observed_seconds': _lastPlayedObserved,
    'wall_stall_ms': _progressStall.elapsedMilliseconds,
  };

  bool get _needsPriming =>
      _startupThresholdFrames > 0 &&
      _audioFramesWritten + _paddingFrames - _playedFrames <
          _startupThresholdFrames;

  void _acknowledgePriming(bool neededPriming) {
    if (!neededPriming) return;
    // Consumption cannot progress until the native threshold is filled.
    // Render/write deadlines still bound every packet while filling it.
    _lastPlayedObserved = _observedSeconds;
    _progressStall
      ..reset()
      ..start();
  }

  Future<void> _readPlayed(int generation) async {
    final local = await (audio as PcmPlaybackProgress).playedFrames().timeout(
      _audioWriteTimeout,
    );
    if (generation != _audioGeneration || _closed) return;
    final played = (_playbackBase + local).clamp(
      _playedFrames,
      _audioFramesWritten + _inFlightFrames,
    );
    final observed = _observedSeconds;
    if (played > _playedFrames) {
      _playedFrames = played;
      _lastPlayedObserved = observed;
      _progressStall
        ..reset()
        ..start();
    }
    if (!_needsPriming &&
        _audioFramesWritten > _playedFrames &&
        (observed - _lastPlayedObserved > 2 ||
            _progressStall.elapsed > _audioWriteTimeout)) {
      if (kDebugMode) {
        debugPrint(
          'NeuroTunePlayback stalled nativeHead=$local ${_playbackCounters()}',
        );
      }
      throw StateError('Audio playback stopped progressing');
    }
    (engine as MeditationProtocol).playback(_playedFrames, observed);
  }

  Future<void> _readStartupThreshold(int generation) async {
    final threshold = audio is PcmStartupThreshold
        ? await (audio as PcmStartupThreshold).startupThresholdFrames().timeout(
            _audioWriteTimeout,
          )
        : 0;
    if (generation != _audioGeneration || _closed) return;
    if (threshold < 0 || threshold > MeditationRenderer.sampleRate) {
      throw StateError('Audio startup buffer exceeds the one-second bound');
    }
    if (threshold != _startupThresholdFrames) {
      _startupThresholdFrames = threshold;
      _recordDiagnostic('audio_buffer', {
        'startup_threshold_frames': threshold,
      });
    }
  }

  /// Only the final content may be followed by silence. A short final tail or
  /// stop ramp still has to prime the sink; padding never advances its cursor.
  Future<void> _primeFinalBuffer(int generation) async {
    while (generation == _audioGeneration && !_closed) {
      final missing =
          _startupThresholdFrames -
          (_audioFramesWritten + _paddingFrames - _playedFrames);
      if (missing <= 0) return;
      final frames = min(missing, MeditationRenderer.maxPacketFrames);
      final neededPriming = _needsPriming;
      await audio.write(Uint8List(frames * 4)).timeout(_audioWriteTimeout);
      if (generation != _audioGeneration || _closed) return;
      _paddingFrames += frames;
      _acknowledgePriming(neededPriming);
    }
  }

  Future<void> _pumpPlayback() async {
    final renderer = _renderer;
    if (renderer == null || engine?.terminal == true) return;
    final generation = _audioGeneration;
    try {
      await _readStartupThreshold(generation);
      final previousPlayed = _playedFrames;
      await _readPlayed(generation);
      if (generation != _audioGeneration || _closed || _finishing) return;
      _releaseFrames();
      await _evaluateMeditation();
      if (generation != _audioGeneration || _closed || _finishing) return;
      if (engine!.terminal) {
        _finishInBackground();
        return;
      }
      // Streaming AudioTrack will not consume until its startup buffer is
      // full. A shorter fixed lead waits forever at played frame zero.
      final due = min(
        MeditationRenderer.durationFrames,
        _playedFrames + max<int>(7200, _startupThresholdFrames),
      );
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
        _inFlightFrames = frames;
        final neededPriming = _needsPriming;
        await audio.write(pcm).timeout(_audioWriteTimeout);
        if (generation != _audioGeneration || _closed) return;
        _audioFramesWritten += frames;
        _inFlightFrames = 0;
        _acknowledgePriming(neededPriming);
      }
      if (_audioFramesWritten == MeditationRenderer.durationFrames &&
          _playedFrames < _audioFramesWritten &&
          _playedFrames == previousPlayed) {
        _audioWritePending = true;
        await _primeFinalBuffer(generation);
      }
      _releaseFrames();
      if (!_closed) notifyListeners();
    } catch (failure) {
      if (generation != _audioGeneration || _closed || _finishing) return;
      _audioFailed(failure);
    } finally {
      _audioWritePending = false;
      if (generation == _audioGeneration) _releaseFrames();
    }
  }

  Future<void> _evaluateMeditation({bool selectNext = true}) async {
    final protocol = engine;
    if (protocol is! MeditationProtocol) return;
    final adaptation = protocol.adaptation;
    if (adaptation == null || !adaptation.isDue(_playedFrames)) return;
    final mapped = protocol.frames
        .map((f) => protocol.mapFrame(f, config.welchWindowSeconds))
        .toList();
    while (true) {
      final decision = adaptation.evaluate(
        sessionId: protocol.sessionId,
        playedFrames: _playedFrames,
        ownedFrames: _audioFramesWritten,
        frames: mapped,
        selectNext: selectNext,
        checkpointReason: _finishing ? 'session_stopped' : 'playback_paused',
      );
      if (decision == null) break;
      final start = decision['transition_start_frame'] as int?;
      if (start != null) {
        await _renderer!.scheduleAction(start, adaptation.action);
      }
    }
  }

  Future<void> _stopRamp() async {
    final generation = _audioGeneration;
    try {
      await _readPlayed(generation);
      await audio.stop();
      _outputAcquired = false;
      if (_closed || generation != _audioGeneration) return;
      final starting = audio.start(48000);
      _outputStart = starting;
      await starting;
      _outputAcquired = true;
      if (_closed || generation != _audioGeneration) return;
      _playbackBase = _playedFrames;
      _paddingFrames = 0;
      await _readStartupThreshold(generation);
      if (_closed || generation != _audioGeneration) return;
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
      if (_closed || generation != _audioGeneration) return;
      _inFlightFrames = frames;
      await audio.write(pcm).timeout(_audioWriteTimeout);
      if (_closed || generation != _audioGeneration) return;
      _audioFramesWritten = _playedFrames + frames;
      _inFlightFrames = 0;
      _lastPlayedObserved = _observedSeconds;
      _progressStall
        ..reset()
        ..start();
      while (_playedFrames < _audioFramesWritten &&
          !_closed &&
          generation == _audioGeneration) {
        await _readStartupThreshold(generation);
        if (_closed || generation != _audioGeneration) return;
        final previousPlayed = _playedFrames;
        await _readPlayed(generation);
        if (_playedFrames == previousPlayed) {
          await _primeFinalBuffer(generation);
        }
        if (_playedFrames < _audioFramesWritten) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    } catch (failure) {
      if (_closed || generation != _audioGeneration) return;
      if (failure is PlatformException &&
          failure.code == 'AUDIO_FOCUS_DENIED') {
        _recordDiagnostic('audio_interruption', {
          'reason': 'focus_denied',
          'available': false,
        });
        return;
      }
      _recordDiagnostic('audio_failed', {
        'error': '$failure',
        'played_frames': _playedFrames,
      });
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
    if (current is MeditationProtocol && current.adaptation != null) {
      final statistics = current.adaptation!.statistics;
      statistics.attachChecksum(manifest.sessionId, checksum);
      await meditation!.saveStatistics?.call(statistics);
    }
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

BanditSnapshot _currentSnapshot(
  ExperimentConfig configured,
  DataOrigin origin,
  BanditSnapshot snapshot,
) {
  final current = configured.forCurrentProcessing();
  return snapshot.experimentVersion == current.version &&
          snapshot.dataOrigin == origin.name
      ? snapshot
      : BanditSnapshot.empty(
          experimentVersion: current.version,
          origin: origin,
          epsilon: current.epsilon,
        );
}
