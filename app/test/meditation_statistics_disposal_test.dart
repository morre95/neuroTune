import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/meditation_action_repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_adaptation_test.dart' show modelFor, liveFrame;
import 'meditation_session_test.dart'
    show ClockedPlaybackAudio, KeepAlive, SilentMuse;
import 'profile_library_test.dart' show metadata, wave, owner;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a restarted policy never learns from an unsaved session with no review or deletion record',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'review-adaptive-orphan',
      );
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final file = File('${dir.path}/db.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final sessions = SessionRepository(db),
          actions = MeditationActionRepository(db, SessionRepository(db));
      final bytes = wave();
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final model = modelFor(profile);
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final audio = ClockedPlaybackAudio();
      var observed = 0.0;
      final config = ExperimentConfig.defaults();
      final session = SessionController(
        repository: sessions,
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
          model: model,
          metadata: {'owner_account_id': owner},
          saveStatistics: (stats) async {
            await actions.save(stats, isCurrent: () => true);
          },
        ),
      );
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      final protocol = session.engine! as MeditationProtocol;
      protocol.sourceAnchor(0, 0);
      for (var tick = 1; tick <= 400; tick++) {
        observed = tick * .15;
        audio.played = (observed * 48000).round();
        if (tick % 7 == 0) protocol.queueFrame(liveFrame(observed));
        await session.pumpPlayback();
      }
      expect(
        protocol.adaptation!.statistics.counts[StimulusAction.binaural6],
        1,
      );
      // A process exit has no awaited finish/persistence path. Dispose also cannot
      // call finish, and exposes the same persisted policy without a raw record.
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await sessions.listSessions(), isEmpty);
      expect(await sessions.pendingUploads(), isEmpty);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final restarted = await MeditationActionRepository(
        db,
        SessionRepository(db),
      ).load(owner, setup, model);
      expect(
        restarted.counts[StimulusAction.binaural6],
        0,
        reason:
            'no durable raw/decision record exists to review or delete this learned observation',
      );
    },
  );
}
