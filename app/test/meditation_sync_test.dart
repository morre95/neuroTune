import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/upload_sync.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uploaded meditation leaves NIR training policies untouched', () async {
    final dir = await Directory.systemTemp.createTemp('meditation-sync');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(() => dir.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    final repo = SessionRepository(db);
    final protocol = MeditationProtocol(
      context: SessionContext(
        sessionId: 'fixed-session',
        origin: DataOrigin.muse,
        eyeState: EyeState.closed,
        sampleRateHz: 256,
        channelNames: simulatorChannels,
        seed: 1,
        startedAt: DateTime.utc(2026),
      ),
      profile: AudioProfileVersion.fromJson(metadata(wave())),
      action: StimulusAction.control,
    );
    final raw = utf8.encode('{}');
    final checksum = sha256Hex(raw);
    final path = await repo.saveSession(
      manifest: protocol.manifest(checksum: checksum),
      decisions: [],
      frames: [],
      raw: raw,
      checksum: checksum,
      status: 'stopped',
    );
    await repo.enqueueUpload(protocol.sessionId, checksum, path, 'owner@test');
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.path != '/v1/sessions') {
          throw StateError('Unexpected NIR training request');
        }
        return http.Response('{}', 201);
      }),
    )..accessToken = 'access';
    await UploadSync(repository: repo, api: api).flush('owner@test');
    expect(requests, ['/v1/sessions']);
    expect(await repo.pendingUploads(), isEmpty);
  });
}
