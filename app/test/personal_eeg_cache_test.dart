import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
