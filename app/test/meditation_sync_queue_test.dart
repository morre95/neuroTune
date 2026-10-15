import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'meditation_sync_test.dart' show fixture, token;
import 'profile_library_test.dart' show owner;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final stage in [
    'plan',
    'raw',
    'feedback_failure',
    'training_failure',
    'deletion_success',
  ]) {
    test(
      'account switch during queued SQLite $stage write preserves old queue',
      () async {
        final (db, repo, _, _, sid) = await fixture();
        if (stage != 'plan') {
          await db
              .update(db.calibrationPlans)
              .write(const CalibrationPlansCompanion(syncState: Value('done')));
        }
        if (stage.contains('failure')) {
          await repo.markUpload(sid, 'done');
        }
        if (stage == 'deletion_success') {
          await repo.deleteSessions([sid], 'owner@test');
        }
        final entered = Completer<void>(), response = Completer<void>();
        final api = ApiClient(
          baseUrl: 'http://local',
          httpClient: MockClient((req) async {
            final held = switch (stage) {
              'plan' => req.url.path.endsWith('calibration-plans'),
              'raw' => req.url.path == '/v1/sessions',
              'feedback_failure' => req.url.path.endsWith('/feedback'),
              'deletion_success' => req.url.path.endsWith('/delete'),
              _ => req.url.path.endsWith('/training/jobs'),
            };
            if (held) {
              entered.complete();
              await response.future;
            }
            if (held && stage.contains('failure')) {
              return http.Response('offline', 500);
            }
            if (req.url.path.endsWith('/delete')) {
              return http.Response(
                '{"deleted_session_ids":["durable-meditation"]}',
                200,
              );
            }
            if (req.url.path.endsWith('/training/jobs')) {
              return http.Response('{"id":"job"}', 202);
            }
            if (req.url.path == '/v1/sessions') return http.Response('{}', 200);
            return http.Response(req.body, 200);
          }),
        )..accessToken = token(owner);
        final sync = UploadSync(repository: repo, api: api);
        final run = sync.flush('owner@test');
        await entered.future;
        final locked = Completer<void>(), unlock = Completer<void>();
        final barrier = db.transaction(() async {
          await db.getKv('barrier');
          locked.complete();
          await unlock.future;
        });
        await locked.future;
        response.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        api.accessToken = token('22222222-2222-4222-8222-222222222222');
        unlock.complete();
        await barrier;
        await run;
        if (stage == 'plan') {
          expect(
            (await db.select(db.calibrationPlans).get()).single.syncState,
            'pending',
          );
        } else if (stage == 'raw') {
          expect(
            (await db.select(db.uploadJobs).get()).single.state,
            'pending',
          );
        } else if (stage == 'feedback_failure') {
          expect(
            (await db.select(db.meditationFeedbackRows).get()).single.attempts,
            0,
          );
        } else if (stage == 'deletion_success') {
          expect(await repo.pendingDeletions('owner@test'), hasLength(1));
        } else {
          expect(
            (await db.select(db.meditationTrainingOutbox).get())
                .single
                .attempts,
            0,
          );
        }
      },
    );
  }
}
