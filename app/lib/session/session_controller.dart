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

class SessionController extends ChangeNotifier {
  SessionController({
    required this.repository,
    required this.api,
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
  final ApiClient api;
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
  final OpticsAccumulator _optics = OpticsAccumulator();
  SimulatorSource? _source;
  MuseChannel? _muse;
  DspHost? _dsp;
  StreamSubscription<EegBatch>? _batches;
  StreamSubscription<OpticsBatch>? _opticsSub;
  StreamSubscription<void>? _lost;
  StreamSubscription<FeatureFrame>? _frames;
  Timer? _audioTimer;
  BinauralSynth? _synth;
  var _finishing = false;
  var _closed = false;

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
    _frames = _dsp!.frames.listen(_onFrame);
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
      _batches = _muse!.eeg.listen((batch) {
        _raw.add(batch);
        _dsp?.addBatch(batch);
      });
      _opticsSub = _muse!.optics.listen((batch) {
        _opticsRaw.add(batch);
        _optics.addBatch(batch);
      });
      _lost = _muse!.disconnected.listen((_) {
        interrupt(StopReason.sourceDisconnected);
      });
    }
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
    _source?.start();
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

  /// Persisting can fail on a full disk or a closed database. The foreground
  /// service and the headband are released either way, or the app is left with
  /// an ongoing notification and a connected Muse that only a restart clears.
  Future<void> finish() async {
    if (_finishing || _closed) return;
    _finishing = true;
    try {
      final current = engine;
      if (current != null && current.phase == SessionPhase.sound) {
        current.interrupt(StopReason.manual);
      }
      _pauseOutputs();
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
    keepAlive.stop();
    _muse?.stop();
    _dsp?.close();
    super.dispose();
  }

  void _onFrame(FeatureFrame frame) {
    final current = engine;
    if (current == null || _closed || _finishing) return;
    final scored = frame.withOptics(
      _optics.consumeUntil(
        frame.timeSeconds,
        config,
        motion: frame.reasons.contains('motion'),
      ),
    );
    current.onFrame(scored);
    _synth?.setAction(current.currentAction);
    latest = scored;
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
    final raw = encodeSessionRaw(_raw, _opticsRaw);
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
