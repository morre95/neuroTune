import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';

void main() {
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
