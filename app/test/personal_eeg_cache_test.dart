import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'profile_library_test.dart' show metadata, wave;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/personal_eeg_repository.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune_core/neurotune_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final json =
      (jsonDecode(
                File(
                  '../contracts/fixtures/personal_eeg.json',
                ).readAsStringSync(),
              )
              as Map)['model']
          as Map<String, dynamic>;
  final owner = json['owner_account_id'] as String;
  String token(String account) =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': account})))}.signature';
  test(
    'a model from the old raw-zero quality policy cannot enter the cache',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = SessionRepository(db);
      final api = ApiClient(
        baseUrl: 'http://legacy-model',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({...json, 'quality_version': '2026.3-unverified'}),
            200,
          ),
        ),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(
        db,
        sessions,
        CalibrationRepository(db, sessions),
        api,
      );
      // Refresh may publish an invalid-result marker successfully. It must never
      // make this incompatible artifact available for offline inference.
      expect(
        await cache.refresh(owner, DataOrigin.simulator, isCurrent: () => true),
        isTrue,
      );
      expect(await cache.load(owner, DataOrigin.simulator), isNull);
    },
  );
  test(
    'downloaded account model works with empty local history across restart and ordinary epochs',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      var delivered = json;
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/meditation/models/latest');
          expect(request.url.queryParameters['origin'], 'simulator');
          return http.Response(jsonEncode(delivered), 200);
        }),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      expect(
        await cache.refresh(owner, DataOrigin.simulator, isCurrent: () => true),
        isTrue,
      );
      expect((await cache.load(owner, DataOrigin.simulator))!.status, 'ready');
      await sessions.bumpEvidenceEpoch(owner);
      final restarted = PersonalEegRepository(db, sessions, calibration, api);
      expect(
        (await restarted.load(owner, DataOrigin.simulator))!.modelVersion,
        'v1',
      );
      expect(await cache.load(owner, DataOrigin.muse), isNull);
      expect(
        await cache.load(
          '99999999-9999-4999-8999-999999999999',
          DataOrigin.simulator,
        ),
        isNull,
      );
      delivered = {
        ...json,
        'status': 'failed_validation',
        'reasons': ['Correlation gate failed'],
      };
      await cache.refresh(owner, DataOrigin.simulator, isCurrent: () => true);
      expect(
        (await restarted.load(owner, DataOrigin.simulator))!.status,
        'failed_validation',
      );
      await db.close();
    },
  );
  test(
    'inflight download cannot publish after deletion epoch or auth generation changes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final sessions = SessionRepository(db);
      final calibration = CalibrationRepository(db, sessions);
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient((_) {
          entered.complete();
          return response.future;
        }),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      final downloading = cache.refresh(
        owner,
        DataOrigin.simulator,
        isCurrent: () => true,
      );
      await entered.future;
      await sessions.bumpEvidenceEpoch(owner);
      response.complete(http.Response(jsonEncode(json), 200));
      expect(await downloading, isFalse);
      expect(await cache.load(owner, DataOrigin.simulator), isNull);
      final second = Completer<http.Response>();
      final api2 = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient((_) => second.future),
      )..accessToken = token(owner);
      final cache2 = PersonalEegRepository(db, sessions, calibration, api2);
      final authChanged = cache2.refresh(
        owner,
        DataOrigin.simulator,
        isCurrent: () => true,
      );
      await Future<void>.delayed(Duration.zero);
      api2.accessToken = null;
      second.complete(http.Response(jsonEncode(json), 200));
      expect(await authChanged, isFalse);
      expect(await cache2.load(owner, DataOrigin.simulator), isNull);
      await db.close();
    },
  );
  test(
    'known included revision conflicts and owned deletion revoke only affected cache',
    () async {
      final dir = await Directory.systemTemp.createTemp('model-evidence');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final db = AppDatabase(NativeDatabase.memory());
      final sessions = SessionRepository(db),
          calibration = CalibrationRepository(db, SessionRepository(db));
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final protocol = MeditationProtocol(
        context: SessionContext(
          sessionId: 'literal-0',
          origin: DataOrigin.simulator,
          eyeState: EyeState.closed,
          sampleRateHz: 256,
          channelNames: simulatorChannels,
          seed: 1,
          startedAt: DateTime.utc(2026),
        ),
        profile: profile,
        action: StimulusAction.control,
      );
      protocol.playback(MeditationProtocol.totalFrames, 600);
      final raw = utf8.encode('{}'), checksum = sha256Hex(utf8.encode('{}'));
      final path = await sessions.saveSession(
        manifest: protocol.manifest(checksum: checksum),
        decisions: [],
        frames: [],
        raw: raw,
        checksum: checksum,
        status: 'completed',
      );
      await sessions.enqueueUpload('literal-0', checksum, path, 'owner@test');
      await calibration.saveFeedback(
        owner,
        'literal-0',
        mentalBusyness: 3,
        relaxation: 7,
      );
      final included = {
        ...json,
        'evidence': [
          for (final e in json['evidence'] as List)
            {
              ...e as Map<String, dynamic>,
              if (e['session_id'] == 'literal-0') 'checksum_sha256': checksum,
            },
        ],
      };
      final api = ApiClient(
        baseUrl: 'http://model',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(included), 200),
        ),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      await cache.refresh(owner, DataOrigin.simulator, isCurrent: () => true);
      expect((await cache.load(owner, DataOrigin.simulator))!.status, 'ready');
      await calibration.saveFeedback(
        owner,
        'literal-0',
        mentalBusyness: 4,
        relaxation: 7,
      );
      expect(
        (await cache.load(owner, DataOrigin.simulator))!.status,
        'revoked',
      );
      await sessions.deleteSessions(
        ['literal-0'],
        'owner@test',
        ownerAccountId: owner,
      );
      expect(
        (await cache.load(owner, DataOrigin.simulator))!.status,
        'revoked',
      );
      expect(
        await cache.refresh(owner, DataOrigin.simulator, isCurrent: () => true),
        isFalse,
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'synthetic API worker export remains ready offline after SQLite reopen with no phone history',
    () async {
      final artifact =
          (jsonDecode(
                    await File(
                      '../contracts/fixtures/synthetic_simulator_model.json',
                    ).readAsString(),
                  )
                  as Map)['model']
              as Map<String, dynamic>;
      final account = artifact['owner_account_id'] as String;
      final folder = await Directory.systemTemp.createTemp(
        'synthetic-model-cache',
      );
      final file = File('${folder.path}/cache.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'http://synthetic-worker',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(artifact), 200);
        }),
      )..accessToken = token(account);
      final sessions = SessionRepository(db);
      final cache = PersonalEegRepository(
        db,
        sessions,
        CalibrationRepository(db, sessions),
        api,
      );
      expect(
        await cache.refresh(
          account,
          DataOrigin.simulator,
          isCurrent: () => true,
        ),
        isTrue,
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      final reopenedSessions = SessionRepository(db);
      final reopened = PersonalEegRepository(
        db,
        reopenedSessions,
        CalibrationRepository(db, reopenedSessions),
        api,
      );
      final model = await reopened.load(account, DataOrigin.simulator);
      expect(model!.status, 'ready');
      expect(model.validation['session_count'], 20);
      expect(model.fixedMinutes, hasLength(29));
      expect(await reopenedSessions.listSessions(), isEmpty);
      expect(
        model.unsupportedReason(
          backgroundAssetId: model.backgrounds.first,
          eyeState: 'closed',
          carrierHz: 220,
          toneGain: .2,
          backgroundGain: .6,
        ),
        isNull,
      );
      expect(
        requests,
        1,
        reason: 'Cache load and readiness do not request a model in session',
      );
      await db.close();
      await folder.delete(recursive: true);
    },
  );
  test(
    'completed HTTP response queued behind SQLite cannot publish after logout',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final sessions = SessionRepository(db),
          calibration = CalibrationRepository(db, SessionRepository(db));
      final response = Completer<http.Response>(), entered = Completer<void>();
      final api = ApiClient(
        baseUrl: 'http://held-model',
        httpClient: MockClient((_) {
          entered.complete();
          return response.future;
        }),
      )..accessToken = token(owner);
      final cache = PersonalEegRepository(db, sessions, calibration, api);
      final download = cache.refresh(
        owner,
        DataOrigin.simulator,
        isCurrent: () => true,
      );
      await entered.future;
      final hold = Completer<void>(), acquired = Completer<void>();
      final transaction = db.transaction(() async {
        await db.customSelect('SELECT 1').get();
        acquired.complete();
        await hold.future;
      });
      await acquired.future;
      response.complete(http.Response(jsonEncode(json), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      api.accessToken = null;
      hold.complete();
      await transaction;
      expect(await download, isFalse);
      expect(await cache.load(owner, DataOrigin.simulator), isNull);
      await db.close();
    },
  );
}
