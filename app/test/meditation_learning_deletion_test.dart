import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/meditation_action_repository.dart';
import 'package:neurotune/data/meditation_preference_repository.dart';
import 'package:neurotune/data/personal_eeg_repository.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_adaptation_test.dart' show modelFor;
import 'meditation_sync_test.dart' show token;
import 'profile_library_test.dart' show owner, metadata, wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed or replacement latest retires old proxy totals and blocks stale publication without a new collection gate',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final model = modelFor(profile);
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final actions = MeditationActionRepository(db, sessions);
      final old = await actions.load(owner, setup, model);
      expect(await actions.save(old, isCurrent: () => true), true);
      var delivered = {
        ...model.toJson(),
        'status': 'failed_validation',
        'reasons': ['Validation failed'],
      };
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(delivered), 200),
        ),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      expect(
        await cache.refresh(owner, DataOrigin.muse, isCurrent: () => true),
        true,
      );
      expect(
        (await cache.load(owner, DataOrigin.muse))!.status,
        'failed_validation',
      );
      expect(
        await db.getKv(actions.key(old)),
        isNull,
        reason: 'old derived initialization survived latest failure',
      );
      expect(await actions.save(old, isCurrent: () => true), false);
      delivered = {
        ...model.toJson(),
        'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'model_version': 'fresh-model-version',
        'fixed_minutes': [],
      };
      await cache.refresh(owner, DataOrigin.muse, isCurrent: () => true);
      final fresh = await actions.load(
        owner,
        setup,
        (await cache.load(owner, DataOrigin.muse))!,
      );
      expect(fresh.contributions, isEmpty);
      expect(
        fresh.means,
        isEmpty,
        reason:
            'no old-version totals or artificial seed-count activation gate',
      );
      expect(await actions.save(fresh, isCurrent: () => true), true);
      expect(await actions.save(old, isCurrent: () => true), false);
      delivered = {
        ...delivered,
        'status': 'revoked',
        'reasons': ['Deleted model evidence'],
      };
      await cache.refresh(owner, DataOrigin.muse, isCurrent: () => true);
      expect(await db.getKv(actions.key(fresh)), isNull);
    },
  );
  test(
    'offline deletion retires full fitted evidence and seeds across restart while preserving unrelated learning and preference',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'learning-retirement',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/db.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final model = modelFor(profile);
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final actions = MeditationActionRepository(db, sessions);
      final stats = await actions.load(owner, setup, model);
      expect(stats.counts[StimulusAction.binaural12], 1);
      expect(await actions.save(stats, isCurrent: () => true), true);
      final otherModel = PersonalEegModel.fromJson({
        ...model.toJson(),
        'origin': 'simulator',
      });
      final otherSetup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      final otherStats = await actions.load(owner, otherSetup, otherModel);
      // A different source uses independent recording identities.
      final independent = PersonalEegModel.fromJson({
        ...otherModel.toJson(),
        'included_session_ids': [
          for (final sid in otherModel.includedSessionIds) 'other-$sid',
        ],
        'evidence': [
          for (final e in otherModel.evidence)
            {...e, 'session_id': 'other-${e['session_id']}'},
        ],
        'fixed_minutes': [],
      });
      final retained = await actions.load(owner, otherSetup, independent);
      expect(await actions.save(retained, isCurrent: () => true), true);
      final preferences = MeditationPreferenceRepository(db, calibration);
      await preferences.choose(owner, setup, StimulusAction.binaural8);
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(model.toJson()), 200),
        ),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      expect(
        await cache.refresh(owner, DataOrigin.muse, isCurrent: () => true),
        true,
      );
      final deleted = model.includedSessionIds.last;
      expect(
        stats.contributions.any((c) => c['session_id'] == deleted),
        false,
        reason:
            'deletion must revoke full fitted evidence, not only exact-setup seeds',
      );
      await sessions.enqueueUpload(
        deleted,
        'a' * 64,
        '${folder.path}/already-remote',
        'owner@test',
      );
      await sessions.deleteSessions(
        [deleted],
        'owner@test',
        ownerAccountId: owner,
      );
      expect((await cache.load(owner, DataOrigin.muse))!.status, 'revoked');
      expect(
        await db.getKv(actions.key(stats)),
        isNull,
        reason:
            'persisted derived initialization still contains revoked fitted evidence',
      );
      expect(await actions.save(stats, isCurrent: () => true), false);
      await expectLater(actions.load(owner, setup, model), throwsStateError);
      expect(await db.getKv(actions.key(retained)), isNotNull);
      expect(
        await preferences.preference(owner, setup),
        StimulusAction.binaural8,
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final restarted = SessionRepository(db);
      final restartedCache = PersonalEegRepository(
        db,
        restarted,
        CalibrationRepository(db, restarted),
        api,
      );
      expect(
        (await restartedCache.load(owner, DataOrigin.muse))!.status,
        'revoked',
      );
      expect(await db.getKv(actions.key(stats)), isNull);
      final removedBody =
          jsonDecode(
                (await db.getKv(
                  'meditation_model:v1:$owner:muse:meditation-1',
                ))!,
              )
              as Map;
      expect(removedBody['included_session_ids'], isEmpty);
      expect(removedBody['fixed_minutes'], isEmpty);
      expect(removedBody['coefficients'], isNull);
      expect(
        await MeditationPreferenceRepository(
          db,
          CalibrationRepository(db, restarted),
        ).preference(owner, setup),
        StimulusAction.binaural8,
      );
      expect(
        (await MeditationActionRepository(
          db,
          restarted,
        ).load(owner, otherSetup, independent)).contributions,
        retained.contributions,
      );
      // No generic epoch equality revokes unaffected source/setup statistics.
      await restarted.bumpEvidenceEpoch(owner);
      expect(await db.getKv(actions.key(retained)), isNotNull);
      expect(otherStats.setup.origin, DataOrigin.simulator);
    },
  );
}
