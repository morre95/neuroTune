import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/meditation_preference_repository.dart';
import 'package:neurotune/data/meditation_sync_repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_sync_test.dart' show fixture, token;
import 'profile_library_test.dart' show owner, metadata, wave;
import 'recommendation_repository_test.dart' show restoreSeries;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'acknowledged offline deletion survives restart and rejects delayed session and feedback restoration',
    () async {
      final (db, sessions, calibration, _, sid) = await fixture();
      final saved = (await sessions.listSessions()).single;
      final job = (await sessions.pendingUploads()).single;
      final raw = await File(job.payloadPath).readAsBytes();
      final file = (await db.customSelect('PRAGMA database_list').get()).first
          .read<String>('file');
      await sessions.deleteSessions([sid], 'owner@test');
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/delete')) {
            return http.Response(
              jsonEncode({
                'deleted_session_ids': [sid],
              }),
              200,
            );
          }
          return http.Response(request.body, 200);
        }),
      )..accessToken = token(owner);
      await UploadSync(repository: sessions, api: api).flush('owner@test');
      expect(await sessions.pendingDeletions('owner@test'), isEmpty);
      await db.close();
      final reopened = AppDatabase(NativeDatabase(File(file)));
      addTearDown(reopened.close);
      final retained = SessionRepository(reopened);
      final ratings = CalibrationRepository(reopened, retained);
      await expectLater(
        retained.saveSession(
          manifest: saved.manifest,
          decisions: saved.decisions,
          frames: saved.frames,
          raw: raw,
          checksum: saved.checksum,
          status: 'completed',
        ),
        throwsStateError,
      );
      await expectLater(
        retained.enqueueUpload(
          sid,
          saved.checksum,
          job.payloadPath,
          'owner@test',
        ),
        throwsStateError,
      );
      expect(await ratings.feedback(owner, sid), isNull);
      await expectLater(
        ratings.saveFeedback(owner, sid, mentalBusyness: 5, relaxation: 5),
        throwsStateError,
      );
      expect(await retained.listSessions(), isEmpty);
      expect(await File(job.payloadPath).exists(), isFalse);
    },
  );
  test(
    'deleted global recording ID cannot be reserved by a different account',
    () async {
      final (db, sessions, calibration, _, sid) = await fixture();
      await sessions.deleteSessions([sid], 'owner@test', ownerAccountId: owner);
      await sessions.completeDeletion(
        (await sessions.pendingDeletions('owner@test')).single,
      );
      const foreign = '99999999-9999-4999-8999-999999999999';
      final foreignProfile = AudioProfileVersion.fromJson({
        ...metadata(wave()),
        'owner_account_id': foreign,
      });
      final plan = await calibration.createPlan(
        ownerAccountId: foreign,
        profile: foreignProfile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      await expectLater(
        calibration.reserveAttempt(foreign, plan.id, sid),
        throwsStateError,
      );
      expect(
        await (db.select(
          db.calibrationAttempts,
        )..where((r) => r.ownerAccountId.equals(foreign))).get(),
        isEmpty,
      );
    },
  );

  test(
    'remaining scores and stable slots refresh while explicit preference survives deletion',
    () async {
      final (db, sessions, calibration, initial, sid) = await fixture();
      final preferences = MeditationPreferenceRepository(db, calibration);
      final profile = initial.profile;
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.simulator,
      );
      final plan = await restoreSeries(
        calibration,
        sessions,
        profile,
        DataOrigin.simulator,
        (_) => (4, 8),
      );
      final progress = await calibration.progress(owner, plan.id);
      final target = progress.results[0]!.id;
      final action = plan.schedule[0];
      await calibration.saveFeedback(
        owner,
        target,
        mentalBusyness: 0,
        relaxation: 10,
      );
      final saved = (await sessions.listSessions()).firstWhere(
        (s) => s.id == target,
      );
      final firstPath = (await (db.select(
        db.storedSessions,
      )..where((r) => r.id.equals(target))).getSingle()).rawPath;
      await sessions.enqueueUpload(
        target,
        saved.checksum,
        firstPath,
        'owner@test',
      );
      await preferences.choose(owner, setup, StimulusAction.binaural12);
      expect(
        (await preferences.resolve(owner, setup)).recommendation!.means[action],
        8.5,
      );
      expect(await preferences.revealedResults(owner, plan.id), hasLength(10));
      final preserved = (await sessions.listSessions())
          .where((s) => s.id != target)
          .map((s) => '${s.id}:${s.checksum}')
          .toSet();
      final epoch = await sessions.readEvidenceEpoch(owner);
      await sessions.deleteSessions(
        [target],
        'owner@test',
        ownerAccountId: owner,
      );
      expect(await sessions.readEvidenceEpoch(owner), epoch + 1);
      expect(await calibration.feedback(owner, target), isNull);
      expect(await preferences.revealedResults(owner, plan.id), isEmpty);
      final after = await calibration.progress(owner, plan.id);
      expect(after.complete, false);
      expect(after.completedSlots, 9);
      expect(after.nextSlot, 0);
      expect(jsonEncode(after.plan.toJson()), jsonEncode(plan.toJson()));
      expect(after.attempts.any((a) => a.sessionId == target), false);
      final choice = await preferences.resolve(owner, setup);
      expect(choice.preference, StimulusAction.binaural12);
      expect(choice.recommendation!.means[action], 7);
      expect(choice.recommendation!.sessionCount, 9);
      expect(
        (await sessions.listSessions())
            .map((s) => '${s.id}:${s.checksum}')
            .toSet(),
        preserved,
      );
      expect(
        await calibration.feedback(owner, sid),
        isNotNull,
      ); // Muse evidence retained.
      expect(
        await calibration.reserveAttempt(owner, plan.id, 'replacement-id'),
        0,
      );
      expect(
        (await calibration.progress(owner, plan.id)).plan.schedule[0],
        action,
      );
      await expectLater(
        calibration.reserveAttempt(owner, plan.id, target),
        throwsStateError,
      );
      final job = (await sessions.pendingDeletions('owner@test')).single;
      await sessions.completeDeletion(job);
      await sessions.deleteSessions(
        [target],
        'owner@test',
        ownerAccountId: owner,
      );
      expect(await sessions.readEvidenceEpoch(owner), epoch + 1);
      expect(await sessions.pendingDeletions('owner@test'), isEmpty);
    },
  );

  test(
    'owned deletion rejects another UUID even with the same email and retains their queued work',
    () async {
      final (db, sessions, calibration, _, sid) = await fixture();
      const foreign = '99999999-9999-4999-8999-999999999999';
      await expectLater(
        sessions.deleteSessions([sid], 'owner@test', ownerAccountId: foreign),
        throwsStateError,
      );
      expect(await calibration.feedback(owner, sid), isNotNull);
      expect(await sessions.listSessions(), hasLength(1));
      expect(await sessions.isTombstoned(owner, sid), false);
      await sessions.deleteSessions([sid], 'owner@test', ownerAccountId: owner);
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{}', 200);
        }),
      )..accessToken = token(foreign);
      await UploadSync(repository: sessions, api: api).flush('owner@test');
      expect(paths, isEmpty);
      expect(await sessions.pendingDeletions('owner@test'), hasLength(1));
      expect(await sessions.isTombstoned(foreign, sid), false);
    },
  );

  test(
    'failed raw unlink keeps a durable retry path and deletion epoch across restart',
    () async {
      final (db, sessions, calibration, _, sid) = await fixture();
      final job = (await sessions.pendingUploads()).single;
      final file = (await db.customSelect('PRAGMA database_list').get()).first
          .read<String>('file');
      await File(job.payloadPath).delete();
      await Directory(
        job.payloadPath,
      ).create(); // A directory forces an actual filesystem unlink failure.
      await sessions.deleteSessions([sid], 'owner@test', ownerAccountId: owner);
      expect(await sessions.listSessions(), isEmpty);
      expect(await calibration.feedback(owner, sid), isNull);
      final epoch = await sessions.readEvidenceEpoch(owner);
      await db.close();
      final reopened = AppDatabase(NativeDatabase(File(file)));
      addTearDown(reopened.close);
      final retained = SessionRepository(reopened);
      var acknowledgements = 0;
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/sessions/delete');
          acknowledgements++;
          return http.Response(
            jsonEncode({
              'deleted_session_ids': [sid],
              'deletion_epoch': 1,
            }),
            200,
          );
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: retained, api: api);
      await sync.flush('owner@test');
      final failed = (await retained.pendingDeletions('owner@test')).single;
      expect(failed.payloadPath, job.payloadPath);
      expect(failed.attempts, 1);
      expect(await retained.readEvidenceEpoch(owner), epoch);
      await Directory(job.payloadPath).delete();
      await sync.flush('owner@test');
      expect(acknowledgements, 2);
      expect(await retained.pendingDeletions('owner@test'), isEmpty);
      expect(await retained.isTombstoned(owner, sid), true);
      expect(await retained.readEvidenceEpoch(owner), epoch);
    },
  );

  test(
    'publication guards queued transactions, tombstones and freshness without blanket cache purges',
    () async {
      final (db, sessions, _, _, sid) = await fixture();
      final key = 'meditation_model:v1:$owner:muse';
      final statsKey = 'meditation_action_stats:v1:$owner:muse';
      await db.putKv(key, 'old-model');
      await db.putKv(statsKey, 'old-statistics');
      final epoch = await sessions.readEvidenceEpoch(owner);
      expect(
        await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: epoch,
          includedSessionIds: [sid],
          key: key,
          value: 'new-model',
        ),
        true,
      );
      final barrier = Completer<void>(), entered = Completer<void>();
      final holding = db.transaction(() async {
        await db.getKv('barrier');
        entered.complete();
        await barrier.future;
      });
      await entered.future;
      var current = true;
      final pending = sessions.publishEvidenceCache(
        owner,
        expectedLocalEpoch: epoch,
        includedSessionIds: [sid],
        key: key,
        value: 'stale-auth',
        isCurrent: () => current,
      );
      current = false;
      barrier.complete();
      await holding;
      expect(await pending, false);
      expect(await db.getKv(key), 'new-model');
      await sessions.deleteSessions([sid], 'owner@test', ownerAccountId: owner);
      expect(await db.getKv(key), 'new-model');
      expect(await db.getKv(statsKey), 'old-statistics');
      expect(
        await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: epoch,
          includedSessionIds: [],
          key: key,
          value: 'old-epoch',
        ),
        false,
      );
      expect(
        await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: await sessions.readEvidenceEpoch(owner),
          includedSessionIds: [sid],
          key: key,
          value: 'deleted-evidence',
        ),
        false,
      );
      const foreign = '99999999-9999-4999-8999-999999999999';
      expect(
        await sessions.publishEvidenceCache(
          foreign,
          expectedLocalEpoch: 0,
          includedSessionIds: [sid],
          key: 'meditation_model:v1:$foreign:simulator',
          value: 'foreign-cache',
        ),
        true,
      );
      await expectLater(
        sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: epoch,
          includedSessionIds: [],
          key: 'meditation_preference:v1:$owner:setup',
          value: 'wrong-namespace',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'adaptive saves and descriptive feedback do not stale evidence publication',
    () async {
      final (db, sessions, calibration, plan, _) = await fixture();
      final epoch = await sessions.readEvidenceEpoch(owner);
      final protocol = MeditationProtocol(
        context: SessionContext(
          sessionId: 'adaptive-description',
          origin: plan.origin,
          eyeState: plan.eyeState,
          sampleRateHz: 256,
          channelNames: simulatorChannels,
          seed: 1,
          startedAt: DateTime.utc(2026),
        ),
        profile: plan.profile,
        action: StimulusAction.control,
        metadata: {'mode': 'adaptive', 'owner_account_id': owner},
      );
      protocol.playback(MeditationProtocol.totalFrames, 600);
      final raw = utf8.encode('{}');
      await sessions.saveSession(
        manifest: protocol.manifest(checksum: sha256Hex(raw)),
        decisions: [],
        frames: [],
        raw: raw,
        checksum: sha256Hex(raw),
        status: 'completed',
      );
      await calibration.saveFeedback(
        owner,
        'adaptive-description',
        mentalBusyness: 4,
        relaxation: 7,
      );
      expect(await sessions.readEvidenceEpoch(owner), epoch);
      expect(
        await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: epoch,
          includedSessionIds: [],
          key: 'meditation_action_stats:v1:$owner:muse',
          value: 'statistics',
        ),
        true,
      );
    },
  );

  test(
    'schema five pending deletion backfills durable markers and removes orphaned private ratings',
    () async {
      final (db, sessions, calibration, plan, sid) = await fixture();
      final preferences = MeditationPreferenceRepository(db, calibration);
      final setup = MeditationSetupContext(
        profile: plan.profile,
        eyeState: plan.eyeState,
        origin: plan.origin,
      );
      await preferences.choose(owner, setup, StimulusAction.binaural10);
      final delivery = MeditationSyncRepository(db);
      final feedback = (await delivery.feedback(owner)).single;
      await delivery.acknowledgeFeedback(
        feedback,
        (await sessions.listSessions()).single,
        isCurrent: () => true,
      );
      expect(await delivery.training(owner), hasLength(1));
      final rawPath = (await sessions.pendingUploads()).single.payloadPath;
      // Version five deletion hid raw rows and queued removal but retained the
      // calibration attempt, ratings and training alias. Recreate that durable state.
      await db.delete(db.storedSessions).go();
      await db
          .update(db.uploadJobs)
          .write(const UploadJobsCompanion(state: Value('delete_pending')));
      await db.deleteKv('meditation_evidence_epoch:v1:$owner');
      final path = (await db.customSelect('PRAGMA database_list').get()).first
          .read<String>('file');
      await db.customStatement('DROP TABLE session_tombstones');
      await db.customStatement('PRAGMA user_version = 5');
      await db.close();
      final reopened = AppDatabase(NativeDatabase(File(path)));
      addTearDown(reopened.close);
      final retained = SessionRepository(reopened);
      expect(await retained.isTombstoned(owner, sid), true);
      expect(await retained.readEvidenceEpoch(owner), 1);
      expect(
        (await retained.pendingDeletions('owner@test')).single.payloadPath,
        rawPath,
      );
      expect(
        await reopened.select(reopened.meditationFeedbackRows).get(),
        isEmpty,
      );
      expect(
        await reopened.select(reopened.calibrationAttempts).get(),
        isEmpty,
      );
      expect(
        await reopened.select(reopened.meditationTrainingOutbox).get(),
        isEmpty,
      );
      final reopenedCalibration = CalibrationRepository(reopened, retained);
      expect(
        jsonEncode((await reopenedCalibration.plan(owner, plan.id)).toJson()),
        jsonEncode(plan.toJson()),
      );
      expect(
        await MeditationPreferenceRepository(
          reopened,
          reopenedCalibration,
        ).preference(owner, setup),
        StimulusAction.binaural10,
      );
      await retained.completeDeletion(
        (await retained.pendingDeletions('owner@test')).single,
      );
      expect(await retained.isTombstoned(owner, sid), true);
      expect(await File(rawPath).exists(), false);
    },
  );
  for (final stage in ['raw', 'feedback', 'training']) {
    test(
      'owned server tombstone at $stage retires recordings ratings and future restoration',
      () async {
        final (db, sessions, calibration, _, sid) = await fixture();
        final original = (await sessions.listSessions()).single;
        final job = (await sessions.pendingUploads()).single;
        final raw = await File(job.payloadPath).readAsBytes();
        await db
            .update(db.calibrationPlans)
            .write(const CalibrationPlansCompanion(syncState: Value('done')));
        if (stage != 'raw') await sessions.markUpload(sid, 'done');
        if (stage == 'training') {
          final delivery = MeditationSyncRepository(db);
          await delivery.acknowledgeFeedback(
            (await delivery.feedback(owner)).single,
            original,
            isCurrent: () => true,
          );
        }
        var calls = 0;
        final api = ApiClient(
          baseUrl: 'http://local',
          httpClient: MockClient((request) async {
            calls++;
            expect(request.url.path, switch (stage) {
              'raw' => '/v1/sessions',
              'feedback' => '/v1/meditation/sessions/$sid/feedback',
              _ => '/v1/meditation/training/jobs',
            });
            return http.Response('{"detail":"deleted"}', 410);
          }),
        )..accessToken = token(owner);
        final sync = UploadSync(repository: sessions, api: api);
        await sync.flush('owner@test');
        await sync.flush('owner@test');
        expect(calls, 1);
        expect(await sessions.listSessions(), isEmpty);
        expect(await calibration.feedback(owner, sid), isNull);
        expect(await sessions.isTombstoned(owner, sid), true);
        expect(await File(job.payloadPath).exists(), false);
        await expectLater(
          sessions.saveSession(
            manifest: original.manifest,
            decisions: original.decisions,
            frames: original.frames,
            raw: raw,
            checksum: original.checksum,
            status: 'completed',
          ),
          throwsStateError,
        );
      },
    );
  }

  test(
    'cache publication rolls back when authentication changes during the actual SQLite write',
    () async {
      var current = true;
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.createFunction(
              functionName: 'revoke_test_auth',
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
      final sessions = SessionRepository(db);
      final key = 'meditation_model:v1:$owner:muse';
      await db.customStatement(
        "CREATE TRIGGER revoke_auth AFTER INSERT ON kv_store WHEN NEW.key = '$key' BEGIN SELECT revoke_test_auth(); END",
      );
      expect(
        await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: 0,
          includedSessionIds: [],
          key: key,
          value: 'stale-response',
          isCurrent: () => current,
        ),
        false,
      );
      expect(current, false);
      expect(await db.getKv(key), isNull);
    },
  );
  test(
    'account cancellation before queued local deletion leaves raw ratings and epoch intact',
    () async {
      final (db, sessions, calibration, _, sid) = await fixture();
      final path = (await sessions.pendingUploads()).single.payloadPath;
      final epoch = await sessions.readEvidenceEpoch(owner);
      final entered = Completer<void>(), release = Completer<void>();
      final barrier = db.transaction(() async {
        await db.getKv('barrier');
        entered.complete();
        await release.future;
      });
      await entered.future;
      var current = true;
      final deletion = sessions.deleteSessions(
        [sid],
        'owner@test',
        ownerAccountId: owner,
        isCurrent: () => current,
      );
      final rejected = expectLater(deletion, throwsStateError);
      current = false;
      release.complete();
      await barrier;
      await rejected;
      expect(await sessions.isTombstoned(owner, sid), false);
      expect(await sessions.listSessions(), hasLength(1));
      expect(await calibration.feedback(owner, sid), isNotNull);
      expect(await sessions.readEvidenceEpoch(owner), epoch);
      expect(await sessions.pendingDeletions('owner@test'), isEmpty);
      expect(await File(path).exists(), true);
    },
  );
}
