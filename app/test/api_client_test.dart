import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show metadata, wave, owner;

void main() {
  test(
    'actual authenticated backend acknowledgement accepts immutable local plan',
    () async {
      final recorded =
          jsonDecode(
                File('test/fixtures/backend_plan_ack.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final plan = CalibrationPlan.fromJson(
        recorded['sent'] as Map<String, dynamic>,
      );
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(recorded['accepted']), 201),
        ),
      );
      await api.createCalibrationPlan(plan);
    },
  );

  test(
    'canonical backend plan acknowledgement accepts equivalent timestamps numbers and key order',
    () async {
      final plan = CalibrationPlan(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ownerAccountId: owner,
        profile: AudioProfileVersion.fromJson(metadata(wave())),
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        schedule: [
          for (final action in StimulusAction.values) ...[action, action],
        ],
        createdAt: DateTime.utc(2026),
      );
      var change = '';
      final api = ApiClient(
        baseUrl: 'http://local',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final profile = body['profile'] as Map<String, dynamic>;
          profile['created_at'] = '2026-10-08T00:00:00+00:00';
          body['created_at'] = '2026-01-01T01:00:00+01:00';
          for (final key in ['carrier_hz', 'normalization_factor']) {
            profile[key] = (profile[key] as num).toDouble();
          }
          for (final track in profile['recipe']['tracks'] as List) {
            for (final key in [
              'trim_start_seconds',
              'trim_end_seconds',
              'gain',
            ]) {
              track[key] = (track[key] as num).toDouble();
            }
          }
          if (change == 'profile') profile['carrier_hz'] = 221.0;
          if (change == 'schedule') {
            body['schedule'] = (body['schedule'] as List).reversed.toList();
          }
          if (change == 'owner') {
            body['owner_account_id'] = '22222222-2222-4222-8222-222222222222';
            profile['owner_account_id'] = body['owner_account_id'];
          }
          final reordered = Map<String, dynamic>.fromEntries(
            body.entries.toList().reversed,
          );
          return http.Response(jsonEncode(reordered), 201);
        }),
      );
      await api.createCalibrationPlan(plan);
      for (final changed in ['profile', 'schedule', 'owner']) {
        change = changed;
        await expectLater(api.createCalibrationPlan(plan), throwsStateError);
      }
    },
  );

  test(
    'obsolete refresh cannot install tokens into a different account',
    () async {
      final pending = Completer<http.Response>();
      final api =
          ApiClient(
              baseUrl: 'http://unused',
              httpClient: MockClient((_) => pending.future),
            )
            ..accessToken = 'old-access'
            ..refreshToken = 'old-refresh';
      final refresh = api.refresh();
      final failure = expectLater(refresh, throwsStateError);
      api.accessToken = 'new-account-access';
      api.refreshToken = 'new-account-refresh';
      pending.complete(
        http.Response(
          '{"access_token":"obsolete","refresh_token":"obsolete-refresh"}',
          200,
        ),
      );
      await failure;
      expect(api.accessToken, 'new-account-access');
      expect(api.refreshToken, 'new-account-refresh');
    },
  );

  test(
    'bulk deletion sends selected IDs and requires complete confirmation',
    () async {
      var complete = true;
      final api = ApiClient(
        baseUrl: 'http://unused',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/sessions/delete');
          expect(request.headers['authorization'], 'Bearer access');
          expect(jsonDecode(request.body), {
            'session_ids': ['a', 'b'],
          });
          return http.Response(
            jsonEncode({
              'deleted_session_ids': complete ? ['a', 'b'] : ['a'],
            }),
            200,
          );
        }),
      )..accessToken = 'access';
      await api.deleteSessions(['a', 'b']);
      complete = false;
      await expectLater(api.deleteSessions(['a', 'b']), throwsStateError);
    },
  );

  test('login request times out instead of remaining pending', () async {
    final pending = Completer<http.Response>();
    final api = ApiClient(
      baseUrl: 'http://unused',
      httpClient: MockClient((_) => pending.future),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      api.login('person@example.com', 'wrong-password'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('401 refreshes once, saves rotated tokens and retries', () async {
    var refreshes = 0;
    var requests = 0;
    String? savedAccess;
    String? savedRefresh;
    final api =
        ApiClient(
            baseUrl: 'http://unused',
            httpClient: MockClient((request) async {
              if (request.url.path == '/v1/auth/refresh') {
                refreshes++;
                expect(
                  jsonDecode(request.body)['refresh_token'],
                  'old-refresh',
                );
                return http.Response(
                  jsonEncode({
                    'access_token': 'new-access',
                    'refresh_token': 'new-refresh',
                  }),
                  200,
                );
              }
              requests++;
              if (request.headers['authorization'] == 'Bearer old-access') {
                return http.Response('expired', 401);
              }
              expect(request.headers['authorization'], 'Bearer new-access');
              return http.Response('{"id":"job-1"}', 200);
            }),
          )
          ..accessToken = 'old-access'
          ..refreshToken = 'old-refresh';
    api.onTokensRefreshed = (access, refresh) async {
      savedAccess = access;
      savedRefresh = refresh;
    };

    expect(
      await api.createTrainingJob(
        origin: 'simulator',
        experimentVersion: '2026.2',
      ),
      'job-1',
    );
    expect(refreshes, 1);
    expect(requests, 2);
    expect(savedAccess, 'new-access');
    expect(savedRefresh, 'new-refresh');
  });
}
