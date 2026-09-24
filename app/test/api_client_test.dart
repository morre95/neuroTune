import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';

void main() {
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
}
