import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/audio/meditation_renderer.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive, SilentMuse;
import 'profile_library_test.dart' show wave, metadata;

class InterruptedAudio extends PlaybackAudio implements PcmInterruptionSource {
  final events = StreamController<PcmInterruption>.broadcast();
  @override
  Stream<PcmInterruption> get interruptions => events.stream;
  @override
  Future<int> pauseAndCheckpoint() async {
    if (playing) pausedHead = played;
    playing = false;
    pending?.complete();
    pending = null;
    // Native pauses retain the focus request for a later gain notification.
    return pausedHead;
  }

  bool focusOwned = false;
  int pausedHead = 0;
  final packets = <Uint8List>[];
  Completer<void>? pending;
  Completer<void>? heldStart;
  bool holdWrites = false;
  int starts = 0;
  bool failStart = false;
  bool denyFocus = false;
  bool autoPlay = false;
  bool failWrite = false;
  @override
  Future<double?> start(int rate) async {
    starts++;
    await heldStart?.future;
    if (denyFocus) throw PlatformException(code: 'AUDIO_FOCUS_DENIED');
    if (failStart) throw StateError('Output unavailable');
    final latency = await super.start(rate);
    pausedHead = 0;
    focusOwned = true;
    return latency;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    packets.add(Uint8List.fromList(bytes));
    accepted += bytes.length ~/ 4;
    if (autoPlay) played = accepted;
    if (failWrite) {
      played = 3600;
      throw StateError('PCM failed after partial playback');
    }
    if (holdWrites) {
      pending = Completer<void>();
      await pending!.future;
    }
  }

  @override
  Future<void> stop() async {
    focusOwned = false;
    pausedHead = 0;
    playing = false;
    played = 0;
    pending?.complete();
    pending = null;
  }
}

Future<(SessionController, SessionRepository, KeepAlive, MeditationSetup)>
setup(
  InterruptedAudio audio, {
  DataOrigin origin = DataOrigin.muse,
  bool dispose = true,
  double Function()? observedTimeSeconds,
}) async {
  final dir = await Directory.systemTemp.createTemp('meditation-interrupt');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  addTearDown(() => dir.delete(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
  final bytes = wave();
  final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
  final meditation = MeditationSetup(
    profile: AudioProfileVersion.fromJson(metadata(bytes)),
    file: file,
    action: StimulusAction.binaural8,
  );
  final repo = SessionRepository(db);
  final service = KeepAlive();
  final config = ExperimentConfig.defaults();
  final session = SessionController(
    repository: repo,
    ownerEmail: 'owner@test',
    audio: audio,
    keepAlive: service,
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: DataOrigin.muse,
    ),
    mode: SessionMode.comparison,
    eyeState: EyeState.closed,
    origin: origin,
    meditation: meditation,
    observedTimeSeconds: observedTimeSeconds,
  );
  if (dispose) addTearDown(session.dispose);
  addTearDown(audio.events.close);
  return (session, repo, service, meditation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pause captures freshly played pending PCM and resumes the same background and tone phase',
    () async {
      final audio = InterruptedAudio()..holdWrites = true;
      final (session, repo, service, meditation) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      while (audio.pending == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      audio.played = 3600;
      session.interrupt(StopReason.background);
      await session.continueSession();
      expect(session.activePlaybackFrames, 3600);
      expect(service.active, true);
      expect(session.engine!.currentAction, StimulusAction.binaural8);
      while (audio.packets.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final renderer = await MeditationRenderer.open(
        meditation.file,
        meditation.profile,
        meditation.action,
      );
      final expected = await renderer.render(
        3600,
        audio.packets[1].length ~/ 4,
      );
      await renderer.close();
      expect(audio.packets[1], expected);
      session.interrupt(StopReason.background);
      await session.finish();
      expect((await repo.listSessions()).single.manifest.durationSeconds, .075);
      expect(service.active, false);
    },
  );
  test(
    'real interruption events hold active time; focus gain does not auto resume',
    () async {
      final audio = InterruptedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      audio.played = 2400;
      audio.events.add(const PcmInterruption('focus_loss_transient'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.waitingForUser, true);
      expect(audio.playing, false);
      expect(session.activePlaybackFrames, 2400);
      expect(service.active, true);
      audio.events.add(const PcmInterruption('focus_gain', available: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(audio.playing, false);
      expect(session.activePlaybackFrames, 2400);
      await session.continueSession();
      expect(session.waitingForUser, false);
      expect(audio.playing, true);
      session.interrupt(StopReason.background);
      await session.finish();
      expect((await repo.listSessions()).single.manifest.durationSeconds, .05);
    },
  );
  test(
    'interruption during held initial start joins two resume taps without stale output',
    () async {
      final audio = InterruptedAudio()..heldStart = Completer<void>();
      final (session, _, service, _) = await setup(audio);
      final starting = session.start(muse: SilentMuse());
      while (audio.starts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      audio.events.add(const PcmInterruption('focus_loss_transient'));
      await Future<void>.delayed(Duration.zero);
      final first = session.continueSession();
      final second = session.continueSession();
      expect(service.active, true);
      audio.heldStart!.complete();
      expect(await starting, true);
      await Future.wait([first, second]);
      expect(audio.starts, 2);
      expect(session.waitingForUser, false);
      expect(audio.playing, true);
      expect(session.activePlaybackFrames, 0);
      session.interrupt(StopReason.background);
      await session.finish();
    },
  );

  test(
    'disposing during held resume cannot reopen output or recording',
    () async {
      final audio = InterruptedAudio();
      final (session, _, service, _) = await setup(audio, dispose: false);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      audio.heldStart = Completer<void>();
      final resuming = session.continueSession();
      while (audio.starts < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      session.dispose();
      audio.heldStart!.complete();
      await resuming;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(audio.playing, false);
      expect(audio.focusOwned, false);
      expect(service.active, false);
      expect(session.saved, false);
    },
  );

  test(
    'initial output failure releases the foreground service without caller disposal',
    () async {
      final audio = InterruptedAudio()..failStart = true;
      final (session, _, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), false);
      expect(service.active, false);
      expect(audio.playing, false);
    },
  );

  test(
    'simulator raw clock and recording continue throughout a playback pause',
    () async {
      final audio = InterruptedAudio();
      final (session, repo, _, _) = await setup(
        audio,
        origin: DataOrigin.simulator,
      );
      expect(await session.start(), true);
      await session.pumpPlayback();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      audio.played = 2400;
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(session.activePlaybackFrames, 2400);
      await session.continueSession();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      session.interrupt(StopReason.background);
      await session.finish();
      final saved = (await repo.listSessions()).single;
      final upload = (await repo.pendingUploads()).single;
      final raw =
          jsonDecode(await File(upload.payloadPath).readAsString()) as Map;
      final batches = raw['eeg'] as List;
      expect(batches.length, greaterThanOrEqualTo(6));
      expect(batches.last['time_seconds'], greaterThanOrEqualTo(2.5));
      for (var i = 1; i < batches.length; i++) {
        expect(
          (batches[i]['time_seconds'] as num) -
              (batches[i - 1]['time_seconds'] as num),
          .5,
        );
      }
      expect(saved.manifest.durationSeconds, .05);
    },
  );
  test(
    'finish joins a held resume and a second finish persists one stopped session',
    () async {
      final audio = InterruptedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      audio.played = 1200;
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      audio.heldStart = Completer<void>();
      final resuming = session.continueSession();
      while (audio.starts < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final first = session.finish();
      final second = session.finish();
      audio.heldStart!.complete();
      await Future.wait([resuming, first, second]);
      final saved = (await repo.listSessions()).single;
      expect(saved.status, 'stopped');
      expect(saved.manifest.durationSeconds, .025);
      expect((await repo.pendingUploads()).length, 1);
      expect(audio.playing, false);
      expect(service.active, false);
    },
  );

  test(
    'unrecoverable resume failure saves diagnostics once and releases service',
    () async {
      final audio = InterruptedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      audio.played = 1200;
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      audio.failStart = true;
      await session.continueSession();
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.status, 'stopped');
      expect(saved.manifest.stopReason, 'audioLost');
      expect(saved.manifest.durationSeconds, .025);
      expect(
        saved.manifest.diagnostics.any((d) => d.type == 'audio_failed'),
        true,
      );
      expect((await repo.pendingUploads()).length, 1);
      expect(service.active, false);
    },
  );
  test(
    'focus loss during a held final ramp cannot restart silent stopped audio',
    () async {
      final audio = InterruptedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      audio.heldStart = Completer<void>();
      audio.autoPlay = true;
      final finishing = session.finish();
      while (audio.starts < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      audio.events.add(const PcmInterruption('focus_loss_transient'));
      await Future<void>.delayed(Duration.zero);
      audio.heldStart!.complete();
      await finishing;
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.durationSeconds, 0);
      expect(saved.manifest.stopReason, 'manual');
      expect(audio.playing, false);
      expect(service.active, false);
    },
  );
  test(
    'partial playback before output failure survives in stopped persistence',
    () async {
      final audio = InterruptedAudio()..failWrite = true;
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.durationSeconds, .075);
      expect(saved.manifest.stopReason, 'audioLost');
      expect(saved.status, 'stopped');
      expect(
        saved.manifest.diagnostics.any((d) => d.type == 'audio_failed'),
        true,
      );
      expect((await repo.pendingUploads()).length, 1);
      expect(service.active, false);
    },
  );
  test(
    'denied audio focus stays paused and can retry the same durable session',
    () async {
      final audio = InterruptedAudio()..denyFocus = true;
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      final id = session.engine!.sessionId;
      expect(session.waitingForUser, true);
      expect(session.activePlaybackFrames, 0);
      expect(service.active, true);
      await session.continueSession();
      expect(session.saved, false);
      expect(session.waitingForUser, true);
      audio.denyFocus = false;
      await session.continueSession();
      expect(session.waitingForUser, false);
      expect(session.engine!.sessionId, id);
      expect(audio.playing, true);
      session.interrupt(StopReason.background);
      await session.finish();
      expect((await repo.listSessions()).single.manifest.sessionId, id);
      expect(service.active, false);
    },
  );
  test(
    'disposing releases retained native audio focus after a resumable pause',
    () async {
      final audio = InterruptedAudio();
      final (session, _, service, _) = await setup(audio, dispose: false);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(audio.playing, false);
      expect(
        audio.focusOwned,
        true,
        reason: 'A resumable native pause retains focus',
      );
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        audio.focusOwned,
        false,
        reason: 'Disposal must abandon retained focus',
      );
      expect(service.active, false);
    },
  );

  test(
    'ordinary disposal abandons focus while stopping playback and service',
    () async {
      final audio = InterruptedAudio();
      final (session, _, service, _) = await setup(audio, dispose: false);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      expect(audio.focusOwned, true);
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(audio.focusOwned, false);
      expect(audio.playing, false);
      expect(service.active, false);
    },
  );
}
