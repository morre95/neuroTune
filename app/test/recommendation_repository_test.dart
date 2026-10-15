import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/meditation_preference_repository.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show metadata, wave, owner;

Future<CalibrationPlan> restoreSeries(
  CalibrationRepository calibration,
  SessionRepository sessions,
  AudioProfileVersion profile,
  DataOrigin origin,
  (int, int) Function(StimulusAction) ratings, {
  int slots = 10,
  EyeState eyes = EyeState.closed,
  Random? random,
}) async {
  final plan = await calibration.createPlan(
    ownerAccountId: profile.ownerAccountId,
    profile: profile,
    eyeState: eyes,
    origin: origin,
    random: random,
  );
  for (var slot = 0; slot < slots; slot++) {
    final id = '${plan.id}-$slot';
    await calibration.reserveAttempt(profile.ownerAccountId, plan.id, id);
    final protocol = MeditationProtocol(
      context: SessionContext(
        sessionId: id,
        origin: origin,
        eyeState: eyes,
        sampleRateHz: 256,
        channelNames: simulatorChannels,
        seed: 1,
        startedAt: DateTime.utc(2026, 1, slot + 1),
      ),
      profile: profile,
      action: plan.schedule[slot],
      metadata: plan.sessionMetadata(slot),
    );
    protocol.playback(MeditationProtocol.totalFrames, 600);
    final raw = utf8.encode('{}');
    final checksum = sha256Hex(raw);
    await sessions.saveSession(
      manifest: protocol.manifest(checksum: checksum),
      decisions: [],
      frames: [],
      raw: raw,
      checksum: checksum,
      status: 'completed',
    );
    final (busy, relaxed) = ratings(plan.schedule[slot]);
    await calibration.saveFeedback(
      profile.ownerAccountId,
      id,
      mentalBusyness: busy,
      relaxation: relaxed,
    );
  }
  return plan;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'recommendations prefer exact setup then pool, with deterministic ties and source isolation',
    () async {
      final dir = await Directory.systemTemp.createTemp('recommendation');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final db = AppDatabase(NativeDatabase.memory());
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final repository = MeditationPreferenceRepository(db, calibration);
      final a = AudioProfileVersion.fromJson(metadata(wave()));
      final b = AudioProfileVersion.fromJson({
        ...a.toJson(),
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'carrier_hz': 300,
      });
      final c = AudioProfileVersion.fromJson({
        ...a.toJson(),
        'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      });
      final setupA = MeditationSetupContext(
        profile: a,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final setupB = MeditationSetupContext(
        profile: b,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final setupC = MeditationSetupContext(
        profile: c,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      await restoreSeries(
        calibration,
        sessions,
        a,
        DataOrigin.muse,
        (_) => (4, 8),
      );
      expect(
        (await repository.resolve(owner, setupA)).recommendation!.action,
        StimulusAction.control,
      );
      // 6 Hz observations score 10 and 0: mean 5. 8 and 10 Hz each score 7,
      // so 8 Hz wins the deterministic tie. Control/12 score 4.
      final first = (await calibration.allProgress(owner)).single;
      for (var slot = 0; slot < 10; slot++) {
        final action = first.plan.schedule[slot];
        final (busy, relaxed) = action == StimulusAction.binaural6
            ? (slot == first.plan.schedule.indexOf(action) ? (0, 10) : (10, 0))
            : (action == StimulusAction.binaural8 ||
                      action == StimulusAction.binaural10
                  ? (2, 6)
                  : (6, 4));
        await calibration.saveFeedback(
          owner,
          first.results[slot]!.id,
          mentalBusyness: busy,
          relaxation: relaxed,
        );
      }
      final scored = await repository.resolve(owner, setupA);
      expect(scored.recommendation!.action, StimulusAction.binaural8);
      expect(scored.recommendation!.means[StimulusAction.binaural6], 5);
      expect(scored.recommendation!.means[StimulusAction.binaural8], 7);
      expect(scored.recommendation!.pooled, false);
      for (var slot = 0; slot < 10; slot++) {
        if (first.plan.schedule[slot] == StimulusAction.binaural6) {
          await calibration.saveFeedback(
            owner,
            first.results[slot]!.id,
            mentalBusyness: 2,
            relaxation: 6,
          );
        }
      }
      expect(
        (await repository.resolve(owner, setupA)).recommendation!.action,
        StimulusAction.binaural6,
      );

      await restoreSeries(
        calibration,
        sessions,
        b,
        DataOrigin.muse,
        (a) => a == StimulusAction.binaural12 ? (4, 8) : (10, 0),
      );
      expect(
        (await repository.resolve(owner, setupB)).recommendation!.action,
        StimulusAction.binaural12,
      );
      final pooled = await repository.resolve(owner, setupC);
      expect(pooled.recommendation!.pooled, true);
      expect(pooled.recommendation!.action, StimulusAction.binaural12);
      await restoreSeries(
        calibration,
        sessions,
        c,
        DataOrigin.simulator,
        (_) => (0, 10),
      );
      expect(
        (await repository.resolve(owner, setupC)).recommendation!.action,
        StimulusAction.binaural12,
      );
      // A partial exact-setup series must not reveal its first assignment via
      // a fixed recommendation or per-action means before the series finishes.
      final partial = await restoreSeries(
        calibration,
        sessions,
        c,
        DataOrigin.muse,
        (_) => (10, 0),
        slots: 1,
      );
      final exactPartial = await repository.resolve(owner, setupC);
      expect(exactPartial.recommendation!.pooled, true);
      expect(exactPartial.recommendation!.action, StimulusAction.binaural12);
      expect(exactPartial.recommendation!.sessionCount, 20);
      expect(await repository.revealedResults(owner, partial.id), isEmpty);
      final openEyes = MeditationSetupContext(
        profile: c,
        eyeState: EyeState.open,
        origin: DataOrigin.muse,
      );
      expect(
        (await repository.resolve(owner, openEyes)).recommendation!.pooled,
        true,
      );
      expect(
        () =>
            repository.resolve('99999999-9999-4999-8999-999999999999', setupA),
        throwsArgumentError,
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'explicit preferences survive restart and remain isolated from source setup and account',
    () async {
      final dir = await Directory.systemTemp.createTemp('preference-restart');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final path = File('${dir.path}/state.sqlite');
      var db = AppDatabase(NativeDatabase(path));
      var sessions = SessionRepository(db);
      var calibration = CalibrationRepository(db, sessions);
      var repository = MeditationPreferenceRepository(db, calibration);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      final first = await restoreSeries(
        calibration,
        sessions,
        profile,
        DataOrigin.simulator,
        (_) => (4, 8),
      );
      final original = jsonEncode(first.toJson());
      final checksum = (await sessions.listSessions()).first.checksum;
      expect(
        (await repository.resolve(owner, setup)).action,
        StimulusAction.control,
      );
      await repository.choose(owner, setup, StimulusAction.binaural12);
      await db.close();
      db = AppDatabase(NativeDatabase(path));
      sessions = SessionRepository(db);
      calibration = CalibrationRepository(db, sessions);
      repository = MeditationPreferenceRepository(db, calibration);
      expect(
        (await repository.resolve(owner, setup)).action,
        StimulusAction.binaural12,
      );
      expect((await sessions.listSessions()).first.checksum, checksum);
      expect(
        (await repository.resolve(
          owner,
          MeditationSetupContext(
            profile: profile,
            eyeState: EyeState.open,
            origin: DataOrigin.simulator,
          ),
        )).preference,
        isNull,
      );
      expect(
        (await repository.resolve(
          owner,
          MeditationSetupContext(
            profile: profile,
            eyeState: EyeState.closed,
            origin: DataOrigin.muse,
          ),
        )).action,
        StimulusAction.control,
      );
      const other = '99999999-9999-4999-8999-999999999999';
      final otherSetup = MeditationSetupContext(
        profile: AudioProfileVersion.fromJson({
          ...profile.toJson(),
          'owner_account_id': other,
        }),
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      expect(
        (await repository.resolve(other, otherSetup)).action,
        StimulusAction.control,
      );
      final additional = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      expect(additional.id, isNot(first.id));
      for (final action in StimulusAction.values) {
        expect(additional.schedule.where((a) => a == action).length, 2);
      }
      expect(
        jsonEncode((await calibration.plan(owner, first.id)).toJson()),
        original,
      );
      final different = await calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: EyeState.open,
        origin: DataOrigin.muse,
      );
      expect(different.eyeState, EyeState.open);
      expect(different.origin, DataOrigin.muse);
      expect(await repository.revealedResults(owner, additional.id), isEmpty);
      expect((await repository.revealedResults(owner, first.id)).length, 10);
      // Fixed ratings have no calibration attempt and must not enter the means.
      final fixed = MeditationProtocol(
        context: SessionContext(
          sessionId: 'fixed-rated',
          origin: DataOrigin.simulator,
          eyeState: EyeState.closed,
          sampleRateHz: 256,
          channelNames: simulatorChannels,
          seed: 1,
          startedAt: DateTime.utc(2026),
        ),
        profile: profile,
        action: StimulusAction.binaural6,
        metadata: {'mode': 'fixed', 'owner_account_id': owner},
      );
      fixed.playback(MeditationProtocol.totalFrames, 600);
      final bytes = utf8.encode('{}');
      await sessions.saveSession(
        manifest: fixed.manifest(checksum: sha256Hex(bytes)),
        decisions: [],
        frames: [],
        raw: bytes,
        checksum: sha256Hex(bytes),
        status: 'completed',
      );
      await calibration.saveFeedback(
        owner,
        'fixed-rated',
        mentalBusyness: 0,
        relaxation: 10,
      );
      expect(
        (await repository.resolve(owner, setup)).recommendation!.sessionCount,
        10,
      );
      expect(
        (await repository.resolve(owner, setup)).recommendation!.action,
        StimulusAction.control,
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
