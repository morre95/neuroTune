import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:neurotune/data/meditation_sync_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:neurotune/ui/meditation_sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show metadata, wave, owner;

String token(String id) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': id})))}.signature';

Future<
  (
    AppDatabase,
    SessionRepository,
    CalibrationRepository,
    CalibrationPlan,
    String,
  )
>
fixture() async {
  final dir = await Directory.systemTemp.createTemp('meditation-sync');
  addTearDown(() => dir.delete(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
  final db = AppDatabase(NativeDatabase(File('${dir.path}/local.sqlite')));
  addTearDown(db.close);
  final repo = SessionRepository(db);
  final calibration = CalibrationRepository(db, repo);
  final plan = await calibration.createPlan(
    ownerAccountId: owner,
    profile: AudioProfileVersion.fromJson(metadata(wave())),
    eyeState: EyeState.closed,
    origin: DataOrigin.muse,
  );
  const sid = 'durable-meditation';
  await calibration.reserveAttempt(owner, plan.id, sid);
  final protocol = MeditationProtocol(
    context: SessionContext(
      sessionId: sid,
      origin: plan.origin,
      eyeState: plan.eyeState,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 1,
      startedAt: DateTime.utc(2026),
    ),
    profile: plan.profile,
    action: plan.schedule[0],
    metadata: plan.sessionMetadata(0),
  );
  protocol.playback(MeditationProtocol.totalFrames, 600);
  final raw = utf8.encode('{"eeg":[]}');
  final digest = sha256Hex(raw);
  final path = await repo.saveSession(
    manifest: protocol.manifest(checksum: digest),
    decisions: [],
    frames: [],
    raw: raw,
    checksum: digest,
    status: 'completed',
  );
  await repo.enqueueUpload(sid, digest, path, 'owner@test');
  await calibration.saveFeedback(owner, sid, mentalBusyness: 3, relaxation: 7);
  return (db, repo, calibration, plan, sid);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline calibration synchronizes plan then unchanged recording then ratings and distinct training',
    () async {
      final (_, repo, calibration, _, sid) = await fixture();
      final checksum = (await repo.listSessions()).single.checksum;
      var offline = true;
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          if (offline) throw const SocketException('offline');
          paths.add(req.url.path);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (req.url.path.endsWith('/training/jobs')) {
            return http.Response(
              '{"id":"meditation-job","status":"queued"}',
              202,
            );
          }
          if (req.url.path.endsWith('/sessions')) {
            return http.Response('{}', 200);
          }
          return http.Response(jsonEncode(body), 200);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      await sync.flush('owner@test');
      expect(await repo.pendingUploads(), hasLength(1));
      offline = false;
      await sync.flush('owner@test');
      expect(paths, [
        '/v1/meditation/calibration-plans',
        '/v1/sessions',
        '/v1/meditation/sessions/$sid/feedback',
        '/v1/meditation/training/jobs',
      ]);
      expect(await repo.pendingUploads(), isEmpty);
      expect((await repo.listSessions()).single.checksum, checksum);
      expect((await calibration.feedback(owner, sid))!.relaxation, 7);
      paths.clear();
      await sync.flush('owner@test');
      expect(paths, isEmpty);
    },
  );
  test(
    'delayed edited ratings flush with no raw upload and held acknowledgement cannot accept new revision',
    () async {
      final (db, repo, calibration, _, sid) = await fixture();
      await db.delete(db.meditationFeedbackRows).go();
      var hold = false;
      final entered = Completer<void>(), released = Completer<void>();
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          paths.add(req.url.path);
          if (hold && req.url.path.endsWith('/feedback')) {
            entered.complete();
            await released.future;
          }
          if (req.url.path.endsWith('/training/jobs')) {
            return http.Response('{"id":"job"}', 202);
          }
          if (req.url.path.endsWith('/sessions')) {
            return http.Response('{}', 200);
          }
          return http.Response(req.body, 200);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      await sync.flush('owner@test');
      expect(await repo.pendingUploads(), isEmpty);
      await calibration.saveFeedback(
        owner,
        sid,
        mentalBusyness: 2,
        relaxation: 6,
      );
      paths.clear();
      hold = true;
      final running = sync.flush('owner@test');
      await entered.future;
      await calibration.saveFeedback(owner, sid, relaxation: 9);
      released.complete();
      await running;
      expect(paths, ['/v1/meditation/sessions/$sid/feedback']);
      final state = (await db.select(db.meditationFeedbackRows).get()).single;
      expect(state.revision, 2);
      expect(state.syncState, 'pending');
      expect(await db.select(db.meditationTrainingOutbox).get(), isEmpty);
      paths.clear();
      hold = false;
      await sync.flush('owner@test');
      expect(paths, [
        '/v1/meditation/sessions/$sid/feedback',
        '/v1/meditation/training/jobs',
      ]);
      expect((await calibration.feedback(owner, sid))!.relaxation, 9);
    },
  );

  test(
    'failed training request survives restart with its ID and does not reupload recording',
    () async {
      final (db, repo, _, _, _) = await fixture();
      final requests = <Map<String, dynamic>>[];
      var fail = true;
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path.endsWith('/training/jobs')) {
            requests.add(jsonDecode(req.body) as Map<String, dynamic>);
            if (fail) throw const SocketException('training offline');
            return http.Response('{"id":"job"}', 202);
          }
          if (req.url.path.endsWith('/sessions')) {
            return http.Response('{}', 200);
          }
          return http.Response(req.body, 200);
        }),
      )..accessToken = token(owner);
      await UploadSync(repository: repo, api: api).flush('owner@test');
      final queued =
          (await db.select(db.meditationTrainingOutbox).get()).single;
      expect(queued.syncState, 'pending');
      expect(queued.attempts, 1);
      final file = (await db.customSelect('PRAGMA database_list').get()).first
          .read<String>('file');
      await db.close();
      final reopened = AppDatabase(NativeDatabase(File(file)));
      addTearDown(reopened.close);
      paths.clear();
      fail = false;
      await UploadSync(
        repository: SessionRepository(reopened),
        api: api,
      ).flush('owner@test');
      expect(paths, ['/v1/meditation/training/jobs']);
      expect(requests[0], requests[1]);
      expect(
        (await reopened.select(reopened.meditationTrainingOutbox).get())
            .single
            .syncState,
        'done',
      );
    },
  );

  for (final changeAccount in [true, false]) {
    test(
      'held response ${changeAccount ? 'account switch' : 'cancel'} leaves owned queue unchanged',
      () async {
        final (db, repo, _, _, _) = await fixture();
        final entered = Completer<void>(), release = Completer<void>();
        final api = ApiClient(
          baseUrl: 'http://local',
          httpClient: MockClient((req) async {
            entered.complete();
            await release.future;
            throw const SocketException('old account response');
          }),
        )..accessToken = token(owner);
        final sync = UploadSync(repository: repo, api: api);
        final running = sync.flush('owner@test');
        await entered.future;
        if (changeAccount) {
          api.accessToken = token('22222222-2222-4222-8222-222222222222');
        } else {
          sync.cancel();
        }
        release.complete();
        await running;
        final plan = (await db.select(db.calibrationPlans).get()).single;
        expect(plan.syncState, 'pending');
        expect(plan.attempts, 0);
        expect(plan.lastError, isNull);
        expect(await repo.pendingUploads(), hasLength(1));
        expect(
          (await db.select(db.meditationFeedbackRows).get()).single.syncState,
          'pending',
        );
        if (changeAccount) {
          // The same email is not enough to transfer UUID-owned meditation data.
          var foreignCalls = 0;
          final foreign = ApiClient(
            baseUrl: 'http://local',
            httpClient: MockClient((_) async {
              foreignCalls++;
              return http.Response('{}', 200);
            }),
          )..accessToken = api.accessToken;
          await UploadSync(repository: repo, api: foreign).flush('owner@test');
          expect(foreignCalls, 0);
        }
      },
    );
  }

  test(
    'deleted-session feedback response terminates retries and never trains',
    () async {
      final (db, repo, _, _, sid) = await fixture();
      await (db.update(
        db.calibrationPlans,
      )).write(const CalibrationPlansCompanion(syncState: Value('done')));
      await repo.markUpload(sid, 'done');
      var calls = 0;
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          calls++;
          expect(req.url.path.endsWith('/feedback'), isTrue);
          return http.Response('{"detail":"deleted"}', 410);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      await sync.flush('owner@test');
      await sync.flush('owner@test');
      expect(calls, 1);
      expect(
        (await db.select(db.meditationFeedbackRows).get()).single.syncState,
        'deleted',
      );
      expect(await db.select(db.meditationTrainingOutbox).get(), isEmpty);
    },
  );

  test(
    'deletion precedes plan and prevents held raw response from resurrecting queue',
    () async {
      final (db, repo, _, _, sid) = await fixture();
      final entered = Completer<void>(), release = Completer<void>();
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path == '/v1/sessions') {
            entered.complete();
            await release.future;
            return http.Response('{}', 200);
          }
          if (req.url.path.endsWith('/delete')) {
            return http.Response(
              jsonEncode({
                'deleted_session_ids': [sid],
              }),
              200,
            );
          }
          return http.Response(req.body, 200);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      final running = sync.flush('owner@test');
      await entered.future;
      await repo.deleteSessions([sid], 'owner@test');
      release.complete();
      await running;
      expect(await repo.pendingDeletions('owner@test'), hasLength(1));
      expect(
        paths.where(
          (p) => p.endsWith('/feedback') || p.endsWith('/training/jobs'),
        ),
        isEmpty,
      );
      paths.clear();
      await sync.flush('owner@test');
      expect(paths.first, '/v1/sessions/delete');
      expect(await repo.pendingDeletions('owner@test'), isEmpty);
    },
  );

  test(
    'schema four migration preserves plan ratings and raw checksum',
    () async {
      final (db, repo, _, _, sid) = await fixture();
      final original = (await repo.listSessions()).single;
      final file = (await db.customSelect('PRAGMA database_list').get()).first
          .read<String>('file');
      await db.customStatement('DROP TABLE meditation_training_outbox');
      await db.customStatement('PRAGMA user_version = 4');
      await db.close();
      final reopened = AppDatabase(NativeDatabase(File(file)));
      addTearDown(reopened.close);
      expect(
        (await SessionRepository(reopened).listSessions()).single.checksum,
        original.checksum,
      );
      expect(
        (await reopened.select(reopened.meditationFeedbackRows).get())
            .single
            .relaxation,
        7,
      );
      expect(
        (await reopened.select(reopened.calibrationPlans).get()).single.id,
        isNotEmpty,
      );
      expect(
        await reopened.select(reopened.meditationTrainingOutbox).get(),
        isEmpty,
      );
      expect(
        (await reopened.select(reopened.uploadJobs).get()).single.sessionId,
        sid,
      );
      expect(
        (await reopened.customSelect('PRAGMA user_version').get()).single
            .read<int>('user_version'),
        5,
      );
    },
  );
  test(
    'server raw tombstone retires dependent feedback without repeated HTTP',
    () async {
      final (db, repo, _, _, _) = await fixture();
      await db
          .update(db.calibrationPlans)
          .write(const CalibrationPlansCompanion(syncState: Value('done')));
      var calls = 0;
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          calls++;
          expect(req.url.path, '/v1/sessions');
          return http.Response('{"detail":"deleted"}', 410);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      await sync.flush('owner@test');
      await sync.flush('owner@test');
      expect(calls, 1);
      expect(
        (await db.select(db.meditationFeedbackRows).get()).single.syncState,
        'deleted',
      );
      expect(await db.select(db.meditationTrainingOutbox).get(), isEmpty);
    },
  );

  for (final mode in ['fixed', 'adaptive']) {
    test(
      '$mode feedback keeps source and protocol while routing only fixed training',
      () async {
        final (db, repo, calibration, _, sid) = await fixture();
        final stored = (await db.select(db.storedSessions).get()).single;
        final manifest =
            jsonDecode(stored.manifestJson) as Map<String, dynamic>;
        final meta = manifest['meditation'] as Map<String, dynamic>;
        meta['quality_version'] = 'eeg-fixture-1';
        meta['mode'] = mode;
        meta['origin'] = 'simulator';
        manifest['data_origin'] = 'simulator';
        for (final key in [
          'calibration_plan_id',
          'calibration_slot',
          'calibration_schema_version',
        ]) {
          meta.remove(key);
        }
        await db
            .update(db.storedSessions)
            .write(
              StoredSessionsCompanion(
                origin: const Value('simulator'),
                manifestJson: Value(jsonEncode(manifest)),
              ),
            );
        await db
            .update(db.calibrationPlans)
            .write(const CalibrationPlansCompanion(syncState: Value('done')));
        await db.delete(db.meditationFeedbackRows).go();
        await calibration.saveFeedback(owner, sid, mentalBusyness: 4);
        final paths = <String>[];
        final api = ApiClient(
          baseUrl: 'http://local',
          httpClient: MockClient((req) async {
            paths.add(req.url.path);
            if (req.url.path.endsWith('/training/jobs')) {
              expect(req.url.path, '/v1/meditation/training/jobs');
              final body = jsonDecode(req.body) as Map;
              expect(body['origin'], 'simulator');
              expect(body['protocol_version'], 'meditation-1');
              return http.Response('{"id":"job"}', 202);
            }
            if (req.url.path.endsWith('/sessions')) {
              return http.Response('{}', 200);
            }
            return http.Response(req.body, 200);
          }),
        )..accessToken = token(owner);
        final sync = UploadSync(repository: repo, api: api);
        await sync.flush('owner@test');
        expect(paths, ['/v1/sessions']); // Incomplete drafts remain on device.
        paths.clear();
        await calibration.saveFeedback(owner, sid, relaxation: 8);
        await sync.flush('owner@test');
        expect(paths, [
          '/v1/meditation/sessions/$sid/feedback',
          if (mode == 'fixed') '/v1/meditation/training/jobs',
        ]);
        expect(
          (await repo.listSessions())
              .single
              .manifest
              .meditation!['quality_version'],
          'eeg-fixture-1',
        );
      },
    );
  }

  test('ownerless meditation is never claimed as legacy NIR work', () async {
    final (db, repo, _, _, _) = await fixture();
    await db
        .update(db.uploadJobs)
        .write(const UploadJobsCompanion(ownerEmail: Value(null)));
    await repo.claimLegacyUploads('foreign@test');
    expect((await repo.pendingUploads()).single.ownerEmail, isNull);
  });

  testWidgets(
    'pending sync error and recovered state are visible without revealing actions',
    (tester) async {
      final (db, repo, _, _, _) = (await tester.runAsync(fixture))!;
      final status = MeditationSyncRepository(
        db,
      ).watchStatus(owner, 'owner@test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MeditationSyncStatusView(status: status)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('väntar på synk'), findsOneWidget);
      var offline = true;
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((req) async {
          if (offline) throw const SocketException('offline');
          if (req.url.path.endsWith('/training/jobs')) {
            return http.Response('{"id":"job"}', 202);
          }
          if (req.url.path.endsWith('/sessions')) {
            return http.Response('{}', 200);
          }
          return http.Response(req.body, 200);
        }),
      )..accessToken = token(owner);
      final sync = UploadSync(repository: repo, api: api);
      await tester.runAsync(() => sync.flush('owner@test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('försök misslyckades'), findsOneWidget);
      offline = false;
      await tester.runAsync(() => sync.flush('owner@test'));
      await tester.pumpAndSettle();
      expect(find.text('Synkroniserat med ditt konto.'), findsOneWidget);
      expect(find.textContaining('binaural'), findsNothing);
      expect(find.textContaining('binaural_'), findsNothing);
    },
  );
}
