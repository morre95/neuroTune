import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune/ui/history_page.dart';
import 'package:neurotune_core/neurotune_core.dart';

SessionManifest manifest(String id) {
  final config = ExperimentConfig.defaults();
  return SessionEngine(
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: DataOrigin.muse,
    ),
    sessionId: id,
    origin: DataOrigin.muse,
    mode: SessionMode.personal,
    eyeState: EyeState.open,
    sampleRateHz: 256,
    channelNames: ['EEG1'],
    seed: 1,
    startedAt: DateTime.utc(2026),
  ).manifest();
}

SavedSession saved(String id) => SavedSession(
  id: id,
  origin: 'muse',
  mode: 'personal',
  manifest: manifest(id),
  decisions: [],
  frames: [],
  status: 'completed',
  checksum: 'checksum',
  createdAt: DateTime.utc(2026),
);

class DeletionApi extends ApiClient {
  DeletionApi() : super(baseUrl: 'http://unused');
  bool offline = true;
  List<List<String>> deletions = [];
  int uploads = 0;
  List<String> uploadedIds = [];
  Completer<void>? uploadPending;
  @override
  Future<void> deleteSessions(List<String> ids) async {
    if (offline) throw const SocketException('offline');
    deletions.add(List.of(ids));
  }

  @override
  Future<int> uploadSession({
    required SessionManifest manifest,
    required List<DecisionEvent> decisions,
    required List<FeatureFrame> frames,
    required List<int> raw,
    required String checksum,
  }) async {
    uploads++;
    uploadedIds.add(manifest.sessionId);
    if (offline) throw const SocketException('offline');
    await uploadPending?.future;
    return 200;
  }

  @override
  Future<String> createTrainingJob({
    required String origin,
    required String experimentVersion,
  }) async => 'job';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SessionRepository repository;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('neurotune-delete-');
    db = AppDatabase(NativeDatabase(File('${directory.path}/app.sqlite')));
    repository = SessionRepository(db);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<String> insert(String id, {String owner = 'owner@example.com'}) async {
    final path = await repository.saveSession(
      manifest: manifest(id),
      decisions: [],
      frames: [],
      raw: [1, 2, 3],
      checksum: 'checksum',
      status: 'completed',
    );
    await repository.enqueueUpload(id, 'checksum', path, owner);
    return path;
  }

  test(
    'offline deletion persists across restart and syncs without uploading',
    () async {
      final first = await insert('delete-a');
      final second = await insert('delete-b');
      await insert('keep');
      final api = DeletionApi();
      await repository.deleteSessions([
        'delete-a',
        'delete-b',
      ], 'owner@example.com');
      expect(await File(first).exists(), isFalse);
      expect(await File(second).exists(), isFalse);
      expect((await repository.listSessions()).map((s) => s.id), ['keep']);
      expect((await repository.pendingUploads()).map((job) => job.sessionId), [
        'keep',
      ]);
      await UploadSync(
        repository: repository,
        api: api,
      ).flush('owner@example.com');
      expect(
        await repository.pendingDeletions('owner@example.com'),
        hasLength(2),
      );
      expect(api.uploadedIds, ['keep']);
      await db.close();
      db = AppDatabase(NativeDatabase(File('${directory.path}/app.sqlite')));
      repository = SessionRepository(db);
      expect(
        await repository.pendingDeletions('owner@example.com'),
        hasLength(2),
      );
      api.offline = false;
      await db.putKv(
        'bandit:muse',
        'old-policy-fetched-before-deletion-synced',
      );
      await UploadSync(
        repository: repository,
        api: api,
      ).flush('owner@example.com');
      expect(api.deletions.single, containsAll(['delete-a', 'delete-b']));
      expect(await repository.pendingDeletions('owner@example.com'), isEmpty);
      expect(api.uploadedIds, ['keep', 'keep']);
      expect(await db.getKv('bandit:muse'), isNull);
    },
  );

  test('local and remote deletion cannot target another account', () async {
    final own = await insert('own');
    final foreign = await insert('foreign', owner: 'other@example.com');
    await expectLater(
      repository.deleteSessions(['own', 'foreign'], 'owner@example.com'),
      throwsStateError,
    );
    expect(await repository.listSessions(), hasLength(2));
    expect(await File(own).exists(), isTrue);
    expect(await File(foreign).exists(), isTrue);
    expect(
      (await repository.listOwnedSessions('owner@example.com')).single.id,
      'own',
    );
    await repository.deleteSessions(['own'], 'owner@example.com');
    final api = DeletionApi()..offline = false;
    await UploadSync(
      repository: repository,
      api: api,
    ).flush('other@example.com');
    expect(api.deletions, isEmpty);
    expect(
      await repository.pendingDeletions('owner@example.com'),
      hasLength(1),
    );
  });

  test(
    'an in-flight upload is drained before its deletion is queued',
    () async {
      await insert('racing');
      final api = DeletionApi()
        ..offline = false
        ..uploadPending = Completer<void>();
      final sync = UploadSync(repository: repository, api: api);
      final upload = sync.flush('owner@example.com');
      while (api.uploads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      sync.cancel();
      final idle = sync.waitForIdle();
      api.uploadPending!.complete();
      await idle;
      await upload;
      await repository.deleteSessions(['racing'], 'owner@example.com');
      await sync.flush('owner@example.com');
      expect(api.deletions.single, ['racing']);
      expect(await repository.pendingUploads(), isEmpty);
      expect(await repository.listSessions(), isEmpty);
    },
  );

  testWidgets(
    'select multiple sessions, cancel confirmation, then delete only selected',
    (tester) async {
      List<String>? deleted;
      final rows = [saved('a'), saved('b'), saved('c')];
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryPage(
            sessions: rows,
            onOpen: (_) {},
            onBack: () {},
            onDelete: (ids) async {
              deleted = ids;
            },
          ),
        ),
      );
      await tester.tap(find.text('Välj'));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.text('Radera valda (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avbryt'));
      await tester.pumpAndSettle();
      expect(deleted, isNull);
      expect(find.text('2 valda'), findsOneWidget);
      await tester.tap(find.text('Radera valda (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Radera'));
      await tester.pumpAndSettle();
      expect(deleted, ['a', 'b']);
      expect(find.byType(Checkbox), findsNothing);
    },
  );
}
