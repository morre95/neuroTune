import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/canonical_wave.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/profile_library.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;

void main() {
  test(
    'refresh reuses verification; playback, edits and restart still verify',
    () async {
      final dir = await Directory.systemTemp.createTemp('verification-cache');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final bytes = wave(seconds: 30);
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient(
          (request) async => request.url.path == '/v1/audio/profiles'
              ? http.Response(jsonEncode([metadata(bytes)]), 200)
              : http.Response.bytes(bytes, 200),
        ),
      )..accessToken = 'access';
      var verifications = 0;
      Future<CanonicalWave> verify(File file, String hash, int seconds) {
        verifications++;
        return CanonicalWave.verify(file, hash, seconds);
      }

      var library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
        verifyWave: verify,
      );
      await library.refresh();
      await library.download(version);
      expect(verifications, 1);
      await library.refresh();
      await Future.wait([library.loadCached(), library.loadCached()]);
      expect(verifications, 1);
      expect(await library.playableFile(version), isNotNull);
      expect(verifications, 2);
      await library.close();
      library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
        verifyWave: verify,
      );
      addTearDown(() => library.close());
      await Future.wait([library.loadCached(), library.loadCached()]);
      expect(
        verifications,
        3,
        reason: 'Concurrent initial checks share one hash',
      );
      final file = File('${dir.path}/audio_profiles/$owner/$version.wav');
      final output = await file.open(mode: FileMode.append);
      await output.writeByte(1);
      await output.close();
      await library.loadCached();
      expect(verifications, 4);
      expect(library.profiles.single.downloaded, false);
      expect(await library.playableFile(version), isNull);
    },
  );

  test(
    'playback hashes bytes even if file size and modification time match',
    () async {
      final dir = await Directory.systemTemp.createTemp('verification-force');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final bytes = wave();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient(
          (request) async => request.url.path == '/v1/audio/profiles'
              ? http.Response(jsonEncode([metadata(bytes)]), 200)
              : http.Response.bytes(bytes, 200),
        ),
      )..accessToken = 'access';
      final library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      addTearDown(library.close);
      await library.refresh();
      await library.download(version);
      final file = File('${dir.path}/audio_profiles/$owner/$version.wav');
      final modified = await file.lastModified();
      final broken = List<int>.of(bytes)..[100] = 1;
      await file.writeAsBytes(broken);
      await file.setLastModified(modified);
      expect(await library.playableFile(version), isNull);
      expect(library.profiles.single.downloaded, false);
    },
  );
}
