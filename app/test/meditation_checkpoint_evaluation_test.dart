import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_adaptation_test.dart' show modelFor, liveFrame;
import 'meditation_session_test.dart'
    show ClockedPlaybackAudio, KeepAlive, SilentMuse;
import 'profile_library_test.dart' show metadata, wave, owner;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the final pause checkpoint evaluates a newly completed valid minute before stopped persistence',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'review-adaptive-checkpoint',
      );
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SessionRepository(db);
      final bytes = wave(),
          profile = AudioProfileVersion.fromJson(metadata(wave()));
      final audio = ClockedPlaybackAudio();
      var observed = 0.0;
      final config = ExperimentConfig.defaults();
      final session = SessionController(
        repository: repo,
        ownerEmail: 'owner@test',
        audio: audio,
        keepAlive: KeepAlive(),
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.muse,
        ),
        mode: SessionMode.personal,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        observedTimeSeconds: () => observed,
        randomUnit: () => .9,
        meditation: MeditationSetup(
          profile: profile,
          file: await File('${dir.path}/background.wav').writeAsBytes(bytes),
          action: StimulusAction.binaural6,
          model: modelFor(profile),
          metadata: {'owner_account_id': owner},
        ),
      );
      addTearDown(session.dispose);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      final protocol = session.engine! as MeditationProtocol;
      protocol.sourceAnchor(0, 0);
      for (var tick = 1; tick <= 399; tick++) {
        observed = tick * .15;
        audio.played = (observed * 48000).round();
        if (tick % 7 == 0) protocol.queueFrame(liveFrame(observed));
        await session.pumpPlayback();
      }
      expect(protocol.adaptation!.decisions, isEmpty);
      // Native consumed the already accepted final packet before the timer's next
      // pump; an interruption's fresh checkpoint is the first proof of minute60.
      observed = 60;
      audio.played = 60 * 48000;
      session.interrupt(StopReason.background);
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.durationSeconds, 60);
      expect(extractMeditationMinutes(saved.frames), hasLength(1));
      final decisions =
          saved.manifest.meditation!['adaptive_decisions'] as List;
      expect(
        decisions,
        hasLength(1),
        reason:
            'a complete valid played minute must be scored before the stopped record is saved',
      );
      expect(decisions.single['score'], 6);
    },
  );
}
