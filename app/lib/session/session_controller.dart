import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/api_client.dart';
import '../data/repository.dart';
import '../dsp/dsp_isolate.dart';
import '../platform/channels.dart';
import '../ui/session_page.dart';

class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController({
    required this.repository,
    required this.api,
    required this.audio,
    required this.config,
    required this.snapshot,
    required this.mode,
    required this.eyeState,
    required this.origin,
    this.sampleRateHz = 256,
  });

  final SessionRepository repository;
  final ApiClient api;
  final PcmOutput audio;
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
  SimulatorSource? _source;
  DspHost? _dsp;
  StreamSubscription<EegBatch>? _batches;
  StreamSubscription<FeatureFrame>? _frames;
  StreamSubscription<bool>? _audioStatus;
  Timer? _audioTimer;
  BinauralSynth? _synth;
  var _finishing = false;
  var _closed = false;

  Future<bool> start() async {
    if (!await audio.hasStereoOutput()) {
      error = 'Sessionen kräver stereohörlurar.';
      notifyListeners();
      return false;
    }
    WidgetsBinding.instance.addObserver(this);
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    _source = SimulatorSource(
      config: config,
      sampleRateHz: sampleRateHz,
      seed: seed,
    );
    engine = SessionEngine(
      config: config,
      snapshot: snapshot,
      sessionId: newSessionId(Random(seed)),
      origin: origin,
      mode: mode,
      eyeState: eyeState,
      sampleRateHz: sampleRateHz,
      channelNames: _source!.channels,
      seed: seed,
      startedAt: DateTime.now().toUtc(),
    );
    _dsp = await DspHost.start(
      config: config,
      sampleRateHz: sampleRateHz,
      channelNames: _source!.channels,
    );
    _frames = _dsp!.frames.listen(_onFrame);
    _batches = _source!.batches.listen((batch) {
      _raw.add(batch);
      _dsp?.addBatch(batch);
    });
    _synth = BinauralSynth(
      sampleRateHz: config.audioSampleRateHz.toDouble(),
      carrierHz: config.carrierHz,
      amplitude: config.amplitude,
      fadeSeconds: config.fadeMs / 1000,
    );
    latencyMs = await audio.start(config.audioSampleRateHz);
    _audioTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _writeAudio(),
    );
    _audioStatus = audio.stereoConnected.listen((connected) {
      if (!connected) interrupt(StopReason.audioLost);
    });
    _source!.start();
    notifyListeners();
    return true;
  }

  SessionView get view {
    final current = engine;
    final frame = latest;
    final selected = current?.selectedChannels ?? const <String>[];
    final channels = [
      for (final channel in frame?.channels ?? const <ChannelFeature>[])
        if (selected.isEmpty || selected.contains(channel.name)) channel,
    ];
    final valid = channels
        .where((channel) => channel.valid && frame?.rejected != true)
        .length;
    return SessionView(
      message: error ?? current?.message ?? 'Startar session.',
      phase: current?.phase.name ?? 'start',
      blockLabel: '${current?.completedBlocks ?? 0}/${config.blockCount}',
      actionLabel: actionLabel(current?.currentAction?.id),
      theta: _mean(channels, (channel) => channel.relativeTheta),
      alpha: _mean(channels, (channel) => channel.relativeAlpha),
      beta: _mean(channels, (channel) => channel.relativeBeta),
      quality: frame == null ? '-' : '$valid/${channels.length} kanaler',
      canContinue: waitingForUser,
    );
  }

  void interrupt(StopReason reason) {
    final current = engine;
    if (current == null || current.terminal || _finishing) return;
    current.interrupt(reason);
    _pauseOutputs();
    waitingForUser =
        reason == StopReason.manual &&
        current.phase == SessionPhase.waitingStable;
    if (current.terminal) {
      finish();
      return;
    }
    notifyListeners();
  }

  Future<void> continueSession() async {
    if (!await audio.hasStereoOutput()) {
      error = 'Sessionen kräver stereohörlurar.';
      notifyListeners();
      return;
    }
    error = null;
    waitingForUser = false;
    latencyMs = await audio.start(config.audioSampleRateHz);
    _audioTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _writeAudio(),
    );
    _source?.start();
    notifyListeners();
  }

  Future<void> finish() async {
    if (_finishing || _closed) return;
    _finishing = true;
    final current = engine;
    if (current != null && current.phase == SessionPhase.sound) {
      current.interrupt(StopReason.manual);
    }
    _pauseOutputs();
    if (current != null) await _persist(current);
    saved = true;
    if (!_closed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      interrupt(StopReason.background);
    } else if (state == AppLifecycleState.resumed && !waitingForUser) {
      continueSession();
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _pauseOutputs();
    _frames?.cancel();
    _batches?.cancel();
    _audioStatus?.cancel();
    _dsp?.close();
    super.dispose();
  }

  void _onFrame(FeatureFrame frame) {
    final current = engine;
    if (current == null || _closed || _finishing) return;
    current.onFrame(frame);
    _synth?.setAction(current.currentAction);
    latest = frame;
    if (current.terminal) {
      finish();
    } else if (!_closed) {
      notifyListeners();
    }
  }

  void _writeAudio() {
    final synth = _synth;
    if (synth == null || _finishing) return;
    final frames = (0.05 * config.audioSampleRateHz).round();
    audio.write(encodePcm16(synth.render(frames)));
  }

  void _pauseOutputs() {
    _audioTimer?.cancel();
    _audioTimer = null;
    _synth?.setAction(null);
    _source?.stop();
    audio.stop();
  }

  Future<void> _persist(SessionEngine current) async {
    final raw = encodeBatches(_raw);
    final checksum = sha256Hex(raw);
    final manifest = current.manifest(
      audioLatencyMs: latencyMs,
      checksum: checksum,
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
    await repository.enqueueUpload(manifest.sessionId, checksum, rawPath);
    await _flush();
  }

  Future<void> _flush() async {
    final pending = await repository.pendingUploads();
    final sessions = await repository.listSessions();
    for (final job in pending) {
      try {
        final saved = sessions.firstWhere(
          (session) => session.id == job.sessionId,
        );
        final bytes = await File(job.payloadPath).readAsBytes();
        final status = await api.uploadSession(
          manifest: saved.manifest,
          decisions: saved.decisions,
          frames: saved.frames,
          raw: bytes,
          checksum: job.checksum,
        );
        if (status == 200 || status == 201) {
          await repository.markUpload(job.sessionId, 'done');
          await api.createTrainingJob(
            origin: origin.name,
            experimentVersion: config.version,
          );
        } else if (status == 409) {
          await repository.markUpload(
            job.sessionId,
            'conflict',
            error: 'checksum',
          );
        }
      } catch (error) {
        await repository.markUpload(
          job.sessionId,
          'pending',
          attempts: job.attempts + 1,
          error: '$error',
        );
      }
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
