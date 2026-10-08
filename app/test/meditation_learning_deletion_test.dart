import 'dart:convert';
import 'dart:async';
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
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_adaptation_test.dart' show modelFor, AdaptiveHarness;
import 'meditation_sync_test.dart' show token;
import 'profile_library_test.dart' show owner, metadata, wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final duringWrite in [false, true]) {
    test(
      duringWrite
          ? 'remote absent-phone retirement rolls back auth cancellation during SQLite marker write'
          : 'queued remote absent-phone retirement cannot mutate after account cancellation',
      () async {
        var current = true;
        final db = AppDatabase(
          NativeDatabase.memory(
            setup: (sqlite) {
              sqlite.createFunction(
                functionName: 'cancel_retirement',
                directOnly: false,
                function: (_) {
                  current = false;
                  return 0;
                },
              );
            },
          ),
        );
        addTearDown(db.close);
        final sessions = SessionRepository(db),
            calibration = CalibrationRepository(db, SessionRepository(db));
        final profile = AudioProfileVersion.fromJson(metadata(wave()));
        final model = modelFor(profile);
        final setup = MeditationSetupContext(
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        );
        final actions = MeditationActionRepository(db, sessions);
        final stats = await actions.load(owner, setup, model);
        expect(await actions.save(stats, isCurrent: () => current), true);
        final api = ApiClient(
          baseUrl: 'http://model',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode(model.toJson()), 200),
          ),
        )..accessToken = token(owner);
        final cache = PersonalEegRepository(db, sessions, calibration, api);
        await cache.refresh(owner, DataOrigin.muse, isCurrent: () => current);
        final sid = model.includedSessionIds.last;
        if (duringWrite) {
          await db.customStatement(
            "CREATE TRIGGER cancel_retirement AFTER INSERT ON session_tombstones BEGIN SELECT cancel_retirement(); END",
          );
          await expectLater(
            sessions.recordServerDeletions(
              [sid],
              'owner@test',
              owner,
              isCurrent: () => current,
            ),
            throwsStateError,
          );
          await db.customStatement('DROP TRIGGER cancel_retirement');
        } else {
          final locked = Completer<void>(), release = Completer<void>();
          final barrier = db.transaction(() async {
            await db.getKv('barrier');
            locked.complete();
            await release.future;
          });
          await locked.future;
          final pending = sessions.recordServerDeletions(
            [sid],
            'owner@test',
            owner,
            isCurrent: () => current,
          );
          current = false;
          release.complete();
          await barrier;
          await expectLater(pending, throwsStateError);
        }
        expect(await sessions.isTombstoned(owner, sid), false);
        expect((await cache.load(owner, DataOrigin.muse))!.status, 'ready');
        expect(await db.getKv(actions.key(stats)), isNotNull);
        current = true;
        await sessions.recordServerDeletions(
          [sid],
          'owner@test',
          owner,
          isCurrent: () => current,
        );
        expect(await sessions.isTombstoned(owner, sid), true);
        expect((await cache.load(owner, DataOrigin.muse))!.status, 'revoked');
        expect(await db.getKv(actions.key(stats)), isNull);
        final epoch = await sessions.readEvidenceEpoch(owner);
        await sessions.recordServerDeletions(
          [sid],
          'owner@test',
          owner,
          isCurrent: () => current,
        );
        expect(await sessions.readEvidenceEpoch(owner), epoch);
        expect(await sessions.pendingDeletions('owner@test'), isEmpty);
      },
    );
  }
  test(
    'idle sync discovers an already acknowledged remote adaptive deletion while the ready model version stays unchanged',
    () async {
      final h = await AdaptiveHarness.open();
      await h.advance(60);
      await h.stop();
      final saved = (await h.repository.listSessions()).single;
      final stats = await h.actions.load(owner, h.scope, h.model);
      var remoteDeleted = false;
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://sync',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/v1/sessions')
            return http.Response('{}', 200);
          if (request.url.path == '/v1/meditation/deletions')
            return http.Response(
              jsonEncode({
                'schema_version': 1,
                'deleted_session_ids': remoteDeleted ? [saved.id] : <String>[],
                'deletion_epoch': remoteDeleted ? 1 : 0,
              }),
              200,
            );
          if (request.url.path == '/v1/meditation/models/latest')
            return request.url.queryParameters['origin'] == 'muse'
                ? http.Response(jsonEncode(h.model.toJson()), 200)
                : http.Response('{}', 404);
          throw StateError('Unexpected route ${request.url}');
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: h.repository, api: api);
      await sync.flush('owner@test');
      expect(await h.repository.pendingUploads(), isEmpty);
      expect(stats.counts[StimulusAction.binaural6], 1);
      remoteDeleted = true;
      await sync.flush('owner@test', reconcileLearning: true);
      expect(await h.repository.listSessions(), isEmpty);
      expect(await h.repository.isTombstoned(owner, saved.id), true);
      expect(await h.repository.pendingDeletions('owner@test'), isEmpty);
      final cache = PersonalEegRepository(
        h.db,
        h.repository,
        CalibrationRepository(h.db, h.repository),
        api,
      );
      expect(
        (await cache.load(owner, DataOrigin.muse))!.modelVersion,
        h.model.modelVersion,
      );
      expect((await cache.load(owner, DataOrigin.muse))!.status, 'ready');
      final rebuilt = await h.actions.load(owner, h.scope, h.model);
      expect(rebuilt.counts[StimulusAction.binaural6], 0);
      expect(rebuilt.counts[StimulusAction.binaural12], 1);
      expect(await h.actions.save(stats, isCurrent: () => true), false);
      expect(paths.where((p) => p == '/v1/sessions').length, 1);
      expect(paths.any((p) => p == '/v1/training/jobs'), false);
    },
  );
  test(
    'idle synchronization reconciles model revocation and skips learning HTTP while playback is quiet',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = SessionRepository(db);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final model = modelFor(profile);
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final actions = MeditationActionRepository(db, sessions);
      final stats = await actions.load(owner, setup, model);
      expect(await actions.save(stats, isCurrent: () => true), true);
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://sync',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/v1/meditation/deletions') {
            return http.Response(
              jsonEncode({
                'schema_version': 1,
                'deleted_session_ids': [],
                'deletion_epoch': 0,
              }),
              200,
            );
          }
          expect(request.url.path, '/v1/meditation/models/latest');
          return request.url.queryParameters['origin'] == 'muse'
              ? http.Response(
                  jsonEncode({
                    ...model.toJson(),
                    'status': 'revoked',
                    'reasons': ['Remote fitted evidence deletion'],
                    'included_session_ids': [],
                    'evidence': [],
                    'fixed_minutes': [],
                  }),
                  200,
                )
              : http.Response('{}', 404);
        }),
      )..accessToken = token(owner);
      var quiet = true;
      final sync = UploadSync(repository: sessions, api: api);
      await sync.flush(
        'owner@test',
        reconcileLearning: true,
        canReconcileLearning: () => !quiet,
      );
      expect(paths, isEmpty);
      quiet = false;
      await sync.flush(
        'owner@test',
        reconcileLearning: true,
        canReconcileLearning: () => !quiet,
      );
      expect(paths, isNotEmpty);
      final cache = PersonalEegRepository(
        db,
        sessions,
        CalibrationRepository(db, sessions),
        api,
      );
      expect((await cache.load(owner, DataOrigin.muse))!.status, 'revoked');
      expect(await db.getKv(actions.key(stats)), isNull);
      expect(await actions.save(stats, isCurrent: () => true), false);
    },
  );
  test(
    'a held old latest response cannot overwrite a newer revocation from another repository instance',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = SessionRepository(db),
          calibration = CalibrationRepository(db, SessionRepository(db));
      final model = modelFor(AudioProfileVersion.fromJson(metadata(wave())));
      final held = Completer<http.Response>(), entered = Completer<void>();
      var first = true;
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient((_) {
          if (first) {
            first = false;
            entered.complete();
            return held.future;
          }
          return Future.value(
            http.Response(
              jsonEncode({
                ...model.toJson(),
                'status': 'revoked',
                'reasons': ['Remote deletion'],
              }),
              200,
            ),
          );
        }),
      )..accessToken = token(owner);
      final pending = PersonalEegRepository(
        db,
        sessions,
        calibration,
        api,
      ).refresh(owner, DataOrigin.muse, isCurrent: () => true);
      await entered.future;
      final current = PersonalEegRepository(db, sessions, calibration, api);
      expect(
        await current.refresh(owner, DataOrigin.muse, isCurrent: () => true),
        true,
      );
      held.complete(http.Response(jsonEncode(model.toJson()), 200));
      expect(await pending, false);
      expect((await current.load(owner, DataOrigin.muse))!.status, 'revoked');
    },
  );
  test(
    'deleting a durable stopped adaptive session rebuilds only its same-version contributions across restart',
    () async {
      final h = await AdaptiveHarness.open(durable: true);
      await h.advance(120);
      await h.stop();
      final saved = (await h.repository.listSessions()).single;
      expect(saved.manifest.meditation!['mode'], 'adaptive');
      expect(saved.decisions, isEmpty);
      final stats = await h.actions.load(owner, h.scope, h.model);
      expect(stats.counts[StimulusAction.binaural6], 1);
      expect(stats.counts[StimulusAction.binaural12], 2);
      expect(stats.means[StimulusAction.binaural12], 6.25);
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(h.model.toJson()), 200),
        ),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(
        h.db,
        h.repository,
        CalibrationRepository(h.db, h.repository),
        api,
      );
      await cache.refresh(owner, DataOrigin.muse, isCurrent: () => true);
      final rawJob = (await h.repository.pendingUploads()).single;
      final raw = await File(rawJob.payloadPath).readAsBytes();
      await h.repository.deleteSessions(
        [saved.id],
        'owner@test',
        ownerAccountId: owner,
      );
      expect(
        (await cache.load(owner, DataOrigin.muse))!.modelVersion,
        h.model.modelVersion,
      );
      expect((await cache.load(owner, DataOrigin.muse))!.status, 'ready');
      expect(await h.actions.save(stats, isCurrent: () => true), false);
      final retired =
          jsonDecode((await h.db.getKv(h.actions.key(stats)))!) as Map;
      expect(
        (retired['contributions'] as List).any(
          (c) => c['session_id'] == saved.id,
        ),
        false,
      );
      await expectLater(
        h.repository.saveSession(
          manifest: saved.manifest,
          decisions: saved.decisions,
          frames: saved.frames,
          raw: raw,
          checksum: saved.checksum,
          status: saved.status,
        ),
        throwsStateError,
      );
      await h.db.close();
      final reopened = AppDatabase(
        NativeDatabase(File('${h.dir.path}/state.sqlite')),
      );
      addTearDown(reopened.close);
      final rebuilt = await MeditationActionRepository(
        reopened,
        SessionRepository(reopened),
      ).load(owner, h.scope, h.model);
      expect(rebuilt.counts[StimulusAction.binaural6], 0);
      expect(rebuilt.counts[StimulusAction.binaural12], 1);
      expect(rebuilt.means[StimulusAction.binaural12], 6.5);
      expect(rebuilt.contributions.every((c) => c['kind'] == 'fixed'), true);
    },
  );
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
      await db.putKv(actions.key(old), '{broken');
      await expectLater(actions.load(owner, setup, model), throwsStateError);
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
