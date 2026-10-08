import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata, owner;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive, SilentMuse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'complete offline ten-session calibration waits for ratings and survives restart without reshuffling',
    () async {
      final dir = await Directory.systemTemp.createTemp('calibration');
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      var db = AppDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      var sessions = SessionRepository(db);
      var calibration = CalibrationRepository(db, sessions);
      final bytes = wave();
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final plan = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        random: Random(42),
      );
      expect(plan.schedule.map((a) => a.id).toList()..sort(), [
        'binaural_10',
        'binaural_10',
        'binaural_12',
        'binaural_12',
        'binaural_6',
        'binaural_6',
        'binaural_8',
        'binaural_8',
        'control',
        'control',
      ]);
      final config = ExperimentConfig.defaults();
      final audio = PlaybackAudio();
      final controller = SessionController(
        repository: sessions,
        ownerEmail: 'owner@test',
        audio: audio,
        keepAlive: KeepAlive(),
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.muse,
        ),
        mode: SessionMode.comparison,
        eyeState: plan.eyeState,
        origin: plan.origin,
        reservedSessionId: 'first-attempt',
        beforeAcquire: (id) async {
          await calibration.reserveAttempt(owner, plan.id, id);
          expect(
            (await calibration.progress(
              owner,
              plan.id,
            )).attempts.single.sessionId,
            id,
          );
          expect(audio.playing, false);
        },
        meditation: MeditationSetup(
          profile: plan.profile,
          file: file,
          action: plan.schedule.first,
          metadata: plan.sessionMetadata(0),
        ),
      );
      expect(await controller.start(muse: SilentMuse()), true);
      while (audio.accepted < MeditationProtocol.totalFrames) {
        await controller.pumpPlayback();
      }
      await controller.pumpPlayback();
      await controller.finish();
      controller.dispose();
      final checksum = (await sessions.listSessions()).single.checksum;
      expect((await calibration.progress(owner, plan.id)).completedSlots, 0);
      expect(
        (await calibration.pendingFeedback(owner)).single.id,
        'first-attempt',
      );
      await calibration.saveFeedback(owner, 'first-attempt', mentalBusyness: 3);
      expect((await calibration.progress(owner, plan.id)).completedSlots, 0);
      await db.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      addTearDown(db.close);
      sessions = SessionRepository(db);
      calibration = CalibrationRepository(db, sessions);
      expect((await calibration.plans(owner)).single.schedule, plan.schedule);
      expect(
        (await calibration.feedback(owner, 'first-attempt'))!.mentalBusyness,
        3,
      );
      await calibration.saveFeedback(owner, 'first-attempt', relaxation: 8);
      await calibration.saveFeedback(owner, 'first-attempt', relaxation: 8);
      expect((await calibration.progress(owner, plan.id)).completedSlots, 1);
      expect((await calibration.progress(owner, plan.id)).nextSlot, 1);
      expect(await calibration.pendingFeedback(owner), isEmpty);
      expect((await sessions.listSessions()).single.checksum, checksum);
      for (var slot = 1; slot < 10; slot++) {
        await runAttempt(calibration, sessions, plan, file, 'attempt-$slot');
        expect(
          (await calibration.progress(owner, plan.id)).completedSlots,
          slot,
        );
        await expectLater(
          calibration.reserveAttempt(owner, plan.id, 'premature-$slot'),
          throwsStateError,
        );
        await calibration.saveFeedback(
          owner,
          'attempt-$slot',
          mentalBusyness: slot,
          relaxation: 10 - slot,
        );
        expect(
          (await calibration.progress(owner, plan.id)).completedSlots,
          slot + 1,
        );
      }
      final finalState = await calibration.progress(owner, plan.id);
      expect(finalState.complete, true);
      expect(finalState.nextSlot, isNull);
      expect(
        (await sessions.listSessions())
            .map((s) => s.manifest.meditation!['fixed_action'])
            .toList()
          ..sort(),
        [
          'binaural_10',
          'binaural_10',
          'binaural_12',
          'binaural_12',
          'binaural_6',
          'binaural_6',
          'binaural_8',
          'binaural_8',
          'control',
          'control',
        ],
      );
      expect(
        (await sessions.listSessions()).every(
          (s) => s.manifest.durationSeconds == 600 && s.frames.isEmpty,
        ),
        true,
      );
      await expectLater(
        calibration.reserveAttempt(owner, plan.id, 'eleventh'),
        throwsStateError,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'completed fixed meditation has owner-scoped recoverable feedback without a calibration plan',
    () async {
      final dir = await Directory.systemTemp.createTemp('fixed-feedback');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final file = await File('${dir.path}/ready.wav').writeAsBytes(wave());
      await runFixedAttempt(sessions, profile, file, 'fixed');
      expect((await calibration.pendingFeedback(owner)).single.id, 'fixed');
      const other = '22222222-2222-4222-8222-222222222222';
      expect(await calibration.pendingFeedback(other), isEmpty);
      await expectLater(
        calibration.saveFeedback(other, 'fixed', relaxation: 5),
        throwsStateError,
      );
      await calibration.saveFeedback(
        owner,
        'fixed',
        mentalBusyness: 0,
        relaxation: 10,
      );
      expect((await calibration.feedback(owner, 'fixed'))!.complete, true);
      expect(await calibration.pendingFeedback(owner), isEmpty);
      expect(await calibration.plans(owner), isEmpty);
      expect(
        (await sessions.listSessions()).single.manifest.meditation!['mode'],
        'fixed',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'stopped and process-terminated attempts keep the slot assignment and owner after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('calibration-stopped');
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      var db = AppDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      var sessions = SessionRepository(db);
      var calibration = CalibrationRepository(db, sessions);
      final bytes = wave();
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final plan = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.open,
        origin: DataOrigin.muse,
      );
      await runAttempt(
        calibration,
        sessions,
        plan,
        file,
        'stopped',
        full: false,
      );
      expect((await calibration.progress(owner, plan.id)).nextSlot, 0);
      expect(await calibration.pendingFeedback(owner), isEmpty);
      await expectLater(
        calibration.saveFeedback(
          owner,
          'stopped',
          mentalBusyness: 0,
          relaxation: 10,
        ),
        throwsStateError,
      );
      expect(
        await calibration.reserveAttempt(owner, plan.id, 'process-died'),
        0,
      );
      expect(
        await calibration.reserveAttempt(owner, plan.id, 'process-died'),
        0,
      );
      await db.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
      addTearDown(db.close);
      sessions = SessionRepository(db);
      calibration = CalibrationRepository(db, sessions);
      await calibration.recoverInterruptedAttempts(owner);
      expect(
        (await calibration.progress(owner, plan.id)).attempts.last.status,
        'interrupted',
      );
      expect((await calibration.plans(owner)).single.schedule, plan.schedule);
      const other = '22222222-2222-4222-8222-222222222222';
      expect(await calibration.plans(other), isEmpty);
      expect(await calibration.pendingFeedback(other), isEmpty);
      await expectLater(
        calibration.reserveAttempt(other, plan.id, 'foreign'),
        throwsStateError,
      );
      await expectLater(
        calibration.saveFeedback(other, 'stopped', mentalBusyness: 0),
        throwsStateError,
      );
      await expectLater(
        calibration.createPlan(
          ownerAccountId: other,
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.simulator,
        ),
        throwsFormatException,
      );
      await runAttempt(calibration, sessions, plan, file, 'retry');
      final recorded = (await sessions.listSessions()).firstWhere(
        (s) => s.id == 'retry',
      );
      expect(
        recorded.manifest.meditation!['fixed_action'],
        plan.schedule.first.id,
      );
      expect(recorded.manifest.eyeState, 'open');
      await expectLater(
        calibration.saveFeedback(
          owner,
          'retry',
          mentalBusyness: -1,
          relaxation: 10,
        ),
        throwsArgumentError,
      );
      await expectLater(
        calibration.saveFeedback(
          owner,
          'retry',
          mentalBusyness: 1,
          relaxation: 11,
        ),
        throwsArgumentError,
      );
      await calibration.saveFeedback(
        owner,
        'retry',
        mentalBusyness: 0,
        relaxation: 10,
      );
      expect((await calibration.progress(owner, plan.id)).completedSlots, 1);
      await expectLater(
        calibration.reserveAttempt(owner, plan.id, 'retry'),
        throwsStateError,
      );
      final separate = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      expect(separate.id, isNot(plan.id));
      expect(separate.eyeState, EyeState.closed);
      expect(
        (await calibration.progress(owner, separate.id)).completedSlots,
        0,
      );
      expect((await calibration.progress(owner, plan.id)).completedSlots, 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a completed attempt with changed locked gains is excluded from its series',
    () async {
      final dir = await Directory.systemTemp.createTemp('calibration-lock');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final bytes = wave();
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final plan = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final changed = AudioProfileVersion.fromJson({
        ...profile.toJson(),
        'tone_gain': 0.1,
        'carrier_hz': 300,
      });
      await runAttempt(
        calibration,
        sessions,
        plan,
        file,
        'changed-setup',
        profile: changed,
      );
      expect(await calibration.pendingFeedback(owner), isEmpty);
      expect((await calibration.progress(owner, plan.id)).completedSlots, 0);
      await expectLater(
        calibration.saveFeedback(
          owner,
          'changed-setup',
          mentalBusyness: 1,
          relaxation: 9,
        ),
        throwsStateError,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> runAttempt(
  CalibrationRepository calibration,
  SessionRepository sessions,
  CalibrationPlan plan,
  File file,
  String id, {
  AudioProfileVersion? profile,
  bool full = true,
}) async {
  final state = await calibration.progress(plan.ownerAccountId, plan.id);
  final config = ExperimentConfig.defaults();
  final audio = PlaybackAudio();
  final controller = SessionController(
    repository: sessions,
    ownerEmail: 'owner@test',
    audio: audio,
    keepAlive: KeepAlive(),
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: plan.origin,
    ),
    mode: SessionMode.comparison,
    eyeState: plan.eyeState,
    origin: plan.origin,
    reservedSessionId: id,
    beforeAcquire: (id) async {
      await calibration.reserveAttempt(plan.ownerAccountId, plan.id, id);
    },
    meditation: MeditationSetup(
      profile: profile ?? plan.profile,
      file: file,
      action: plan.schedule[state.nextSlot!],
      metadata: plan.sessionMetadata(state.nextSlot!),
    ),
  );
  try {
    expect(await controller.start(muse: SilentMuse()), true);
    if (full) {
      while (audio.accepted < MeditationProtocol.totalFrames) {
        await controller.pumpPlayback();
      }
      await controller.pumpPlayback();
    }
    await controller.finish();
  } finally {
    controller.dispose();
  }
}

Future<void> runFixedAttempt(
  SessionRepository sessions,
  AudioProfileVersion profile,
  File file,
  String id,
) async {
  final config = ExperimentConfig.defaults();
  final audio = PlaybackAudio();
  final controller = SessionController(
    repository: sessions,
    ownerEmail: 'owner@test',
    audio: audio,
    keepAlive: KeepAlive(),
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: DataOrigin.muse,
    ),
    mode: SessionMode.comparison,
    eyeState: EyeState.closed,
    origin: DataOrigin.muse,
    reservedSessionId: id,
    meditation: MeditationSetup(
      profile: profile,
      file: file,
      action: StimulusAction.control,
      metadata: {'owner_account_id': profile.ownerAccountId},
    ),
  );
  try {
    expect(await controller.start(muse: SilentMuse()), true);
    while (audio.accepted < MeditationProtocol.totalFrames) {
      await controller.pumpPlayback();
    }
    await controller.pumpPlayback();
    await controller.finish();
  } finally {
    controller.dispose();
  }
}
