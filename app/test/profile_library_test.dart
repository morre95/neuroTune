import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/ui/profiles_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/profile_library.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const version = '22222222-2222-4222-8222-222222222222';
Uint8List wave({int seconds = 30}) {
  final bytes = Uint8List(44 + seconds * 192000);
  final b = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  b.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 2, Endian.little);
  b.setUint32(24, 48000, Endian.little);
  b.setUint32(28, 192000, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  b.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

Map<String, dynamic> metadata(
  Uint8List bytes, {
  String id = version,
  int number = 1,
  String account = owner,
}) => {
  'schema_version': 1,
  'id': id,
  'owner_account_id': account,
  'profile_id': '33333333-3333-4333-8333-333333333333',
  'version': number,
  'name': 'Rain',
  'background_asset_id': '44444444-4444-4444-8444-444444444444',
  'recipe': {
    'schema_version': 1,
    'duration_seconds': 30,
    'tracks': [
      {
        'asset_id': '55555555-5555-4555-8555-555555555555',
        'trim_start_seconds': 0,
        'trim_end_seconds': 30,
        'gain': 1,
        'loop': false,
      },
    ],
  },
  'carrier_hz': 220,
  'tone_gain': .2,
  'background_gain': .6,
  'loop': true,
  'duration_seconds': 30,
  'normalization_factor': 1,
  'checksum_sha256': sha256.convert(bytes).toString(),
  'preview_checksum_sha256': sha256.convert(bytes).toString(),
  'sample_rate_hz': 48000,
  'channels': 2,
  'sample_width_bytes': 2,
  'created_at': '2026-10-08T00:00:00Z',
};
void main() {
  test('compatible profile settings accept the exact headroom boundary', () {
    final json = metadata(wave());
    json['tone_gain'] = .55;
    json['background_gain'] = .4;
    expect(AudioProfileVersion.fromJson(json).toneGain, .55);
    json['tone_gain'] = .5501;
    expect(() => AudioProfileVersion.fromJson(json), throwsFormatException);
  });

  test(
    'downloaded idle preview works offline and refuses competing audio',
    () async {
      final dir = await Directory.systemTemp.createTemp('profiles-preview');
      final db = AppDatabase(NativeDatabase.memory());
      final bytes = wave();
      var offline = false;
      var busy = false;
      final audio = FakeAudio();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((r) async {
          if (offline) throw const SocketException('offline');
          return r.url.path == '/v1/audio/profiles'
              ? http.Response(jsonEncode([metadata(bytes)]), 200)
              : http.Response.bytes(bytes, 200);
        }),
      )..accessToken = 'access';
      final library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
        audio: audio,
        audioBusy: () => busy,
      );
      await library.refresh();
      await library.download(version);
      offline = true;
      await library.refresh();
      busy = true;
      expect(() => library.preview(version), throwsStateError);
      expect(audio.starts, 0);
      busy = false;
      final play = library.preview(version);
      final stopped = expectLater(play, throwsStateError);
      await audio.firstWrite.future.timeout(const Duration(seconds: 2));
      expect(audio.starts, 1);
      expect(library.previewing, true);
      expect(() => library.preview(version), throwsStateError);
      await library.stopPreview();
      await stopped;
      expect(library.previewing, false);
      expect(audio.stops, greaterThan(0));
      await library.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  testWidgets(
    'library browsing exposes ready state, downloads and local removal',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('profiles-ui'),
      ))!;
      final db = AppDatabase(NativeDatabase.memory());
      final bytes = wave();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient(
          (r) async => r.url.path == '/v1/audio/profiles'
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
      await tester.runAsync(library.refresh);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilesPage(library: library, onBack: () async {}),
        ),
      );
      expect(find.text('Rain · version 1'), findsOneWidget);
      expect(find.text('Redo på servern · inte nedladdad'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Ladda ned'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (library.progress.isNotEmpty) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError(
              'Download pending: ${library.progress} ${library.error}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(find.text('Nedladdad · redo offline'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Ta bort lokal kopia'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('Ladda ned'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await library.close();
        await db.close();
        await dir.delete(recursive: true);
      });
    },
  );

  test('corrupt bytes and a noncanonical WAV never become playable', () async {
    final dir = await Directory.systemTemp.createTemp('profiles-corrupt');
    final db = AppDatabase(NativeDatabase.memory());
    final bytes = wave();
    var payload = Uint8List.fromList(bytes)..[100] = 1;
    var meta = metadata(bytes);
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (r) async => r.url.path == '/v1/audio/profiles'
            ? http.Response(jsonEncode([meta]), 200)
            : http.Response.bytes(payload, 200),
      ),
    )..accessToken = 'access';
    final library = ProfileLibrary(
      database: db,
      api: api,
      directory: dir,
      ownerAccountId: owner,
    );
    await library.refresh();
    await expectLater(library.download(version), throwsFormatException);
    expect(await library.playableFile(version), isNull);
    payload = Uint8List.fromList(bytes);
    ByteData.sublistView(payload).setUint32(24, 44100, Endian.little);
    // A new immutable version has a matching checksum but an invalid PCM format.
    const next = '66666666-6666-4666-8666-666666666666';
    meta = metadata(payload, id: next, number: 2);
    await library.refresh();
    await expectLater(library.download(next), throwsFormatException);
    expect(library.profiles.every((p) => !p.downloaded), true);
    expect(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    await library.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'versions and account caches are isolated, including a late authenticated response',
    () async {
      final dir = await Directory.systemTemp.createTemp('profiles-owner');
      final db = AppDatabase(NativeDatabase.memory());
      final bytes = wave();
      const next = '66666666-6666-4666-8666-666666666666';
      const other = '77777777-7777-4777-8777-777777777777';
      var account = owner;
      var hold = false;
      final pending = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((r) async {
          if (hold && r.url.path == '/v1/audio/profiles') return pending.future;
          if (r.url.path == '/v1/audio/profiles') {
            return http.Response(
              jsonEncode([
                metadata(bytes, account: account),
                metadata(bytes, id: next, number: 2, account: account),
              ]),
              200,
            );
          }
          return http.Response.bytes(bytes, 200);
        }),
      )..accessToken = 'access';
      final a = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      await a.refresh();
      await a.download(version);
      expect(
        a.profiles.firstWhere((p) => p.profile.id == next).downloaded,
        false,
      );
      hold = true;
      final request = a.refresh();
      final failure = expectLater(request, throwsStateError);
      api.accessToken = 'other-access';
      account = other;
      pending.complete(
        http.Response(jsonEncode([metadata(bytes, account: owner)]), 200),
      );
      await failure;
      await a.close();
      hold = false;
      final b = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: other,
      );
      await b.refresh();
      expect(b.profiles.every((p) => !p.downloaded), true);
      expect(b.profiles.every((p) => p.profile.ownerAccountId == other), true);
      expect(await b.playableFile(version), isNull);
      await b.close();
      api.accessToken = 'access';
      account = owner;
      final restored = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      await restored.refresh();
      expect(await restored.playableFile(version), isNotNull);
      await restored.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'cancellation releases a stalled transfer and never publishes partial audio',
    () async {
      final dir = await Directory.systemTemp.createTemp('profiles-cancel');
      final db = AppDatabase(NativeDatabase.memory());
      final bytes = wave();
      final body = StreamController<List<int>>();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient.streaming((request, _) async {
          if (request.url.path == '/v1/audio/profiles') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode([metadata(bytes)]))),
              200,
            );
          }
          return http.StreamedResponse(body.stream, 200);
        }),
      )..accessToken = 'access';
      final library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      await library.refresh();
      final job = library.download(version);
      final failed = expectLater(job, throwsStateError);
      body.add(bytes.sublist(0, 100));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(library.progress[version]!.received, 100);
      library.cancelDownload(version);
      await failed.timeout(const Duration(seconds: 1));
      expect(library.profiles.single.downloaded, false);
      expect(library.progress, isEmpty);
      expect(
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
      await library.close();
      await db.close();
      await body.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'owned immutable download is verified, survives restart offline and can be removed',
    () async {
      final dir = await Directory.systemTemp.createTemp('profiles-test');
      final dbPath = File('${dir.path}/db.sqlite');
      var db = AppDatabase(NativeDatabase(dbPath));
      var offline = false;
      final bytes = wave();
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer access');
          if (offline) throw const SocketException('offline');
          if (request.url.path == '/v1/audio/profiles') {
            return http.Response(jsonEncode([metadata(bytes)]), 200);
          }
          return http.Response.bytes(bytes, 200);
        }),
      )..accessToken = 'access';
      var library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      await library.refresh();
      expect(library.profiles.single.downloaded, false);
      await library.download(version);
      expect(library.profiles.single.downloaded, true);
      expect(await library.playableFile(version), isNotNull);
      await library.close();
      await db.close();
      db = AppDatabase(NativeDatabase(dbPath));
      offline = true;
      library = ProfileLibrary(
        database: db,
        api: api,
        directory: dir,
        ownerAccountId: owner,
      );
      await library.refresh();
      expect(library.offline, true);
      expect(library.profiles.single.downloaded, true);
      await library.removeLocal(version);
      expect(library.profiles.single.downloaded, false);
      expect(await library.playableFile(version), isNull);
      expect(
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.wav')),
        isEmpty,
      );
      await library.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}

class FakeAudio implements PcmOutput {
  int starts = 0;
  int stops = 0;
  final firstWrite = Completer<void>();
  @override
  Future<double?> start(int rate) async {
    starts++;
    return 0;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (!firstWrite.isCompleted) firstWrite.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
