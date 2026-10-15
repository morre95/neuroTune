import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune/ui/history_page.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'profile_library_test.dart' show metadata, owner;

final _profile = AudioProfileVersion.fromJson(metadata(Uint8List(0)));
const _email = 'synthetic@example.com';

Map<String, dynamic> _manifest(String id, {bool large = false}) {
  final protocol = MeditationProtocol(
    context: SessionContext(
      sessionId: id,
      origin: DataOrigin.muse,
      eyeState: EyeState.closed,
      sampleRateHz: 256,
      channelNames: ['TP9', 'AF7', 'AF8', 'TP10'],
      seed: 1,
      startedAt: DateTime.utc(2026),
    ),
    profile: _profile,
    action: StimulusAction.control,
  )..playback(600 * 48000, 600);
  final manifest = protocol.manifest().toJson();
  if (large) {
    (manifest['meditation'] as Map)['playback_timeline'] = [
      for (var i = 0; i < 12000; i++)
        {'observed_seconds': i / 20, 'played_frames': i * 2400},
    ];
    manifest['diagnostics'] = [
      for (var i = 0; i < 1000; i++)
        {
          'time_seconds': i / 2,
          'type': 'battery',
          'values': {'percent': 80},
        },
    ];
  }
  return manifest;
}

Future<void> _insert(
  AppDatabase db,
  String id, {
  String email = _email,
  String frames = '[]',
  bool large = false,
}) async {
  await db
      .into(db.storedSessions)
      .insert(
        StoredSessionsCompanion.insert(
          id: id,
          origin: 'muse',
          mode: 'meditation',
          manifestJson: jsonEncode(_manifest(id, large: large)),
          decisionsJson: '[]',
          framesJson: frames,
          status: 'completed',
          checksum: 'checksum-$id',
          rawPath: '/unused',
          createdAt: DateTime.utc(2026),
        ),
      );
  await db
      .into(db.uploadJobs)
      .insert(
        UploadJobsCompanion.insert(
          sessionId: id,
          ownerEmail: Value(email),
          checksum: 'checksum-$id',
          payloadPath: '/unused',
          state: 'done',
        ),
      );
}

class _MetadataOnlyRepository extends SessionRepository {
  _MetadataOnlyRepository(super.db);
  @override
  Future<List<SavedSession>> listSessions() =>
      throw StateError('Full history must not be loaded');
  @override
  Future<SavedSession?> sessionById(String id, {String? ownerEmail}) =>
      throw StateError('Detail must not be loaded');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'metadata paths ignore EEG payloads and discard large timelines',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _insert(db, 'one', frames: 'invalid EEG payload', large: true);
      final repo = _MetadataOnlyRepository(db);
      final summary = (await repo.ownedSummaryPage(_email)).sessions.single;
      expect(summary.manifest.diagnostics, isEmpty);
      expect(
        summary.manifest.meditation!.containsKey('playback_timeline'),
        false,
      );
      expect(summary.manifest.durationSeconds, 600);
      final calibration = CalibrationRepository(db, repo);
      for (var i = 0; i < 8; i++) {
        await calibration.createPlan(
          ownerAccountId: owner,
          profile: _profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        );
      }
      final state = await calibration.snapshot(owner);
      expect(state.progress, hasLength(8));
      expect(state.pendingFeedback.map((s) => s.id), ['one']);
      await UploadSync(
        repository: repo,
        api: ApiClient(baseUrl: 'http://unused'),
      ).flush(_email);
    },
  );

  test(
    'keyset pages keep tied dates stable and exclude other accounts',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < 103; i++) {
        await _insert(db, 'session-${i.toString().padLeft(3, '0')}');
      }
      await _insert(db, 'foreign', email: 'other@example.com');
      final repo = SessionRepository(db);
      final first = await repo.ownedSummaryPage(_email);
      expect(first.sessions, hasLength(50));
      final second = await repo.ownedSummaryPage(_email, before: first.next);
      expect(second.sessions, hasLength(50));
      final third = await repo.ownedSummaryPage(_email, before: second.next);
      expect(third.sessions, hasLength(3));
      expect(third.next, isNull);
      final ids = [
        ...first.sessions,
        ...second.sessions,
        ...third.sessions,
      ].map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(103));
      expect(ids, await repo.ownedSessionIds(_email));
      expect(await repo.sessionById('foreign', ownerEmail: _email), isNull);
      await repo.deleteSessions(
        [first.sessions.last.id],
        _email,
        cleanupRaw: false,
      );
      final afterDeletion = await repo.ownedSummaryPage(
        _email,
        before: first.next,
      );
      expect(
        afterDeletion.sessions.map((s) => s.id),
        second.sessions.map((s) => s.id),
      );
    },
  );

  test(
    'v6 migration preserves originals and rebuilds summaries after updates',
    () async {
      final dir = await Directory.systemTemp.createTemp('summary-migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      await _insert(db, 'retained', large: true);
      final original = (await db.select(db.storedSessions).get()).single;
      await db.customStatement('DROP TRIGGER session_summary_insert');
      await db.customStatement('DROP TRIGGER session_summary_update');
      await db.customStatement(
        'ALTER TABLE stored_sessions DROP COLUMN summary_json',
      );
      await db.customStatement(
        'ALTER TABLE stored_sessions DROP COLUMN decision_count',
      );
      await db.customStatement('PRAGMA user_version = 6');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final repo = SessionRepository(db);
      final summary = (await repo.ownedSummaryPage(_email)).sessions.single;
      expect(summary.manifest.durationSeconds, 600);
      expect(summary.manifest.diagnostics, isEmpty);
      final restored = (await db.select(db.storedSessions).get()).single;
      expect(restored.manifestJson, original.manifestJson);
      expect(restored.framesJson, original.framesJson);
      expect(restored.decisionsJson, original.decisionsJson);
      expect(restored.checksum, original.checksum);
      final details = await repo.sessionById('retained', ownerEmail: _email);
      expect(details!.manifest.diagnostics, hasLength(1000));
      expect(
        details.manifest.meditation!['playback_timeline'],
        hasLength(12000),
      );
      final changed = jsonDecode(original.manifestJson) as Map<String, dynamic>;
      changed['duration_seconds'] = 123;
      await (db.update(
        db.storedSessions,
      )..where((s) => s.id.equals('retained'))).write(
        StoredSessionsCompanion(manifestJson: Value(jsonEncode(changed))),
      );
      expect(
        (await repo.summaryById('retained'))!.manifest.durationSeconds,
        123,
      );
    },
  );

  testWidgets(
    'select all includes unloaded sessions and prunes retired selections',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _insert(db, 'visible');
      final summary = (await SessionRepository(
        db,
      ).ownedSummaryPage(_email)).sessions.single;
      List<String>? deleted;
      Future<void> show(Set<String>? valid) => tester.pumpWidget(
        MaterialApp(
          home: HistoryPage(
            sessions: [summary],
            onOpen: (_) {},
            onBack: () {},
            onSelectAll: () async => ['visible', 'unloaded'],
            validSelectionIds: valid,
            onDelete: (ids) async => deleted = ids,
          ),
        ),
      );
      await show(null);
      await tester.tap(find.text('Välj'));
      await tester.pump();
      await tester.tap(find.text('Välj alla'));
      await tester.pump();
      expect(find.text('2 valda'), findsOneWidget);
      await show({'visible'});
      expect(find.text('1 valda'), findsOneWidget);
      await tester.tap(find.text('Radera valda (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Radera'));
      await tester.pumpAndSettle();
      expect(deleted, ['visible']);
    },
  );

  testWidgets('history builds visible rows and shows loading and retry', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _insert(db, 'one');
    final summary = (await SessionRepository(
      db,
    ).ownedSummaryPage(_email)).sessions.single;
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          sessions: [
            for (var i = 0; i < 100; i++)
              SessionSummary(
                id: 'row-$i',
                origin: summary.origin,
                mode: summary.mode,
                manifest: summary.manifest,
                decisionCount: 0,
                status: summary.status,
                checksum: summary.checksum,
                createdAt: summary.createdAt,
              ),
          ],
          onOpen: (_) {},
          onBack: () {},
          loading: false,
          message: 'Testfel',
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
    await tester.tap(find.text('Försök igen'));
    expect(retried, true);
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          sessions: const [],
          onOpen: (_) {},
          onBack: () {},
          loading: true,
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Inga sessioner ännu.'), findsNothing);
  });
  test(
    'navigation workload scales without decoding EEG or timelines',
    () async {
      final frames = jsonEncode([
        for (var i = 0; i < 600; i++)
          FeatureFrame(
            timeSeconds: i.toDouble(),
            sampleRateHz: 256,
            channels: [
              for (final name in ['TP9', 'AF7', 'AF8', 'TP10'])
                ChannelFeature(
                  name: name,
                  valid: true,
                  contact: 1,
                  absoluteTheta: 10,
                  absoluteAlpha: 20,
                  absoluteBeta: 5,
                  relativeTheta: .2,
                  relativeAlpha: .4,
                  relativeBeta: .1,
                  totalPower: 50,
                  reasons: [],
                ),
            ],
            rejected: false,
            reasons: [],
          ).toJson(),
      ]);
      for (final large in [false, true]) {
        for (final count in [10, 40, 80]) {
          final db = AppDatabase(NativeDatabase.memory());
          try {
            final repo = _MetadataOnlyRepository(db);
            final calibration = CalibrationRepository(db, repo);
            for (var p = 0; p < count ~/ 10; p++) {
              await calibration.createPlan(
                ownerAccountId: owner,
                profile: _profile,
                eyeState: EyeState.closed,
                origin: DataOrigin.muse,
              );
            }
            await db.transaction(() async {
              for (var i = 0; i < count; i++) {
                await _insert(db, 'synthetic-$i', frames: frames, large: large);
              }
            });
            await calibration.snapshot(owner); // Warm the metadata path.
            final times = <int>[];
            for (var run = 0; run < 3; run++) {
              final clock = Stopwatch()..start();
              final state = await calibration.snapshot(owner);
              final page = await repo.ownedSummaryPage(_email);
              await repo.pendingDeletions(_email);
              clock.stop();
              expect(state.progress, hasLength(count ~/ 10));
              expect(state.pendingFeedback, hasLength(count));
              expect(page.sessions, hasLength(count < 50 ? count : 50));
              times.add(clock.elapsedMicroseconds);
            }
            times.sort();
            // ignore: avoid_print
            print(
              'NAVIGATION sessions=$count plans=${count ~/ 10} '
              'large_manifest=$large full_scans=0 decoded_frames=0 '
              'median_ms=${times[1] / 1000}',
            );
          } finally {
            await db.close();
          }
        }
      }
    },
  );
}
