import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune_core/neurotune_core.dart';

class _Repository extends SessionRepository {
  _Repository(super.db, this.session, this.job);

  final SavedSession session;
  final PendingUpload job;
  String? marked;

  @override
  Future<List<PendingUpload>> pendingUploads() async => [job];

  @override
  Future<List<SavedSession>> listSessions() async => [session];

  @override
  Future<void> markUpload(
    String sessionId,
    String state, {
    int? attempts,
    String? error,
  }) async => marked = state;
}

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://unused');

  String? trainedOrigin;
  String? trainedVersion;

  @override
  Future<int> uploadSession({
    required SessionManifest manifest,
    required List<DecisionEvent> decisions,
    required List<FeatureFrame> frames,
    required List<int> raw,
    required String checksum,
  }) async => 200;

  @override
  Future<String> createTrainingJob({
    required String origin,
    required String experimentVersion,
  }) async {
    trainedOrigin = origin;
    trainedVersion = experimentVersion;
    return 'job-1';
  }
}

void main() {
  test('retry trains the uploaded session origin and version', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp(
      'neurotune-upload-',
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    final rawFile = File('${directory.path}/session.bin');
    await rawFile.writeAsBytes([1, 2, 3]);
    final manifest = SessionManifest(
      sessionId: 'older-muse-session',
      userId: null,
      experimentVersion: 'older-version',
      policyVersion: '0',
      dataOrigin: 'muse',
      mode: 'personal',
      eyeState: 'open',
      sampleRateHz: 256,
      channelNames: const [],
      selectedChannels: const [],
      startedAtIso: DateTime.utc(2026).toIso8601String(),
      durationSeconds: 1,
      audioLatencyMs: null,
      audioLatencySource: 'test',
      timeline: 'test',
      seed: 1,
      checksumSha256: 'checksum',
    );
    final repository = _Repository(
      database,
      SavedSession(
        id: manifest.sessionId,
        origin: manifest.dataOrigin,
        mode: manifest.mode,
        manifest: manifest,
        decisions: const [],
        frames: const [],
        status: 'completed',
        checksum: 'checksum',
        createdAt: DateTime.utc(2026),
      ),
      PendingUpload(
        sessionId: manifest.sessionId,
        ownerEmail: 'person@example.com',
        checksum: 'checksum',
        payloadPath: rawFile.path,
        attempts: 0,
      ),
    );
    final api = _Api();

    await UploadSync(
      repository: repository,
      api: api,
    ).flush('person@example.com');

    expect(api.trainedOrigin, 'muse');
    expect(api.trainedVersion, 'older-version');
    expect(repository.marked, 'done');
  });

  test('retry does not upload another account’s session', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final manifest = SessionManifest(
      sessionId: 'other-account',
      userId: null,
      experimentVersion: '2026.2',
      policyVersion: '0',
      dataOrigin: 'simulator',
      mode: 'personal',
      eyeState: 'open',
      sampleRateHz: 256,
      channelNames: const [],
      selectedChannels: const [],
      startedAtIso: DateTime.utc(2026).toIso8601String(),
      durationSeconds: 1,
      audioLatencyMs: null,
      audioLatencySource: 'test',
      timeline: 'test',
      seed: 1,
      checksumSha256: 'checksum',
    );
    final repository = _Repository(
      database,
      SavedSession(
        id: manifest.sessionId,
        origin: manifest.dataOrigin,
        mode: manifest.mode,
        manifest: manifest,
        decisions: const [],
        frames: const [],
        status: 'completed',
        checksum: 'checksum',
        createdAt: DateTime.utc(2026),
      ),
      PendingUpload(
        sessionId: manifest.sessionId,
        ownerEmail: 'alice@example.com',
        checksum: 'checksum',
        payloadPath: '/not-read',
        attempts: 0,
      ),
    );
    final api = _Api();

    await UploadSync(repository: repository, api: api).flush('bob@example.com');

    expect(api.trainedOrigin, isNull);
    expect(repository.marked, isNull);
  });
}
