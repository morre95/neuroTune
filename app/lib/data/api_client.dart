import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:neurotune_core/neurotune_core.dart';

class ApiException implements Exception {
  ApiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'API $status: $body';
}

class AuthTokens {
  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
  });
  final String accessToken;
  final String refreshToken;
  final String email;

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'email': email,
  };

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    email: json['email'] as String,
  );
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration requestTimeout;
  String? _accessToken;
  String? refreshToken;
  int _authGeneration = 0;
  int get authGeneration => _authGeneration;
  String? get accessToken => _accessToken;
  set accessToken(String? value) {
    if (_accessToken != value) {
      _authGeneration++;
      _refreshing = null;
    }
    _accessToken = value;
  }

  String? get accountId {
    try {
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(accessToken!.split('.')[1]),
                  ),
                ),
              )
              as Map;
      final sub = payload['sub'];
      return sub is String && isAccountUuid(sub) ? sub : null;
    } catch (_) {
      return null;
    }
  }

  void _checkGeneration(int generation) {
    if (_authGeneration != generation) throw StateError('Account changed');
  }

  Future<void> Function(String access, String refresh)? onTokensRefreshed;
  Future<void>? _refreshing;

  Future<AuthTokens> register(String email, String password) =>
      _tokens('/v1/auth/register', email, password);

  Future<AuthTokens> login(String email, String password) =>
      _tokens('/v1/auth/login', email, password);

  Future<AuthTokens> _tokens(String path, String email, String password) async {
    final generation = ++_authGeneration;
    _refreshing = null;
    final response = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(requestTimeout);
    _expect(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _checkGeneration(generation);
    _accessToken = json['access_token'] as String;
    refreshToken = json['refresh_token'] as String;
    return AuthTokens(
      accessToken: accessToken!,
      refreshToken: refreshToken!,
      email: email,
    );
  }

  Future<void> refresh() async {
    final generation = _authGeneration;
    final currentRefresh = refreshToken;
    if (currentRefresh == null) throw StateError('No refresh token');
    final response = await _http
        .post(
          Uri.parse('$baseUrl/v1/auth/refresh'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'refresh_token': currentRefresh}),
        )
        .timeout(requestTimeout);
    _expect(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _checkGeneration(generation);
    final nextAccess = json['access_token'] as String;
    final nextRefresh = json['refresh_token'] as String;
    _accessToken = nextAccess;
    refreshToken = nextRefresh;
    await onTokensRefreshed?.call(nextAccess, nextRefresh);
  }

  Future<void> _refreshOnce() {
    final active = _refreshing;
    if (active != null) return active;
    final next = refresh();
    _refreshing = next;
    return next.whenComplete(() {
      if (identical(_refreshing, next)) _refreshing = null;
    });
  }

  Future<void> logout() async {
    final response = await _send('POST', '/v1/auth/logout', {
      'refresh_token': refreshToken,
    });
    _expect(response);
    accessToken = null;
    refreshToken = null;
  }

  Future<List<AudioProfileVersion>> audioProfiles() async {
    final response = await _send('GET', '/v1/audio/profiles');
    _expect(response);
    return [
      for (final json in jsonDecode(response.body) as List)
        AudioProfileVersion.fromJson(Map<String, dynamic>.from(json as Map)),
    ];
  }

  Future<http.StreamedResponse> audioProfileStream(
    String versionId, {
    bool preview = false,
    required Future<void> abortTrigger,
  }) async {
    if (!isAccountUuid(versionId)) throw ArgumentError('Invalid version');
    final generation = _authGeneration;
    final usedAccess = accessToken;
    Future<http.StreamedResponse> request() {
      final req = http.AbortableRequest(
        'GET',
        Uri.parse(
          '$baseUrl/v1/audio/profiles/versions/$versionId/${preview ? 'preview' : 'download'}',
        ),
        abortTrigger: abortTrigger,
      );
      if (accessToken != null) {
        req.headers['authorization'] = 'Bearer $accessToken';
      }
      return _http.send(req).timeout(requestTimeout);
    }

    var response = await request();
    _checkGeneration(generation);
    if (response.statusCode == 401 &&
        usedAccess != null &&
        refreshToken != null) {
      await response.stream.drain<void>();
      if (accessToken == usedAccess) await _refreshOnce();
      _checkGeneration(generation);
      response = await request();
      _checkGeneration(generation);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      throw ApiException(status, 'Audio unavailable');
    }
    return response;
  }

  Future<ExperimentConfig> activeExperiment() async {
    final response = await _send('GET', '/v1/experiments/active');
    _expect(response);
    return ExperimentConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<BanditSnapshot> latestBandit({
    required String origin,
    required String experimentVersion,
  }) async {
    final response = await _send(
      'GET',
      '/v1/bandit/latest?origin=$origin&experiment_version=$experimentVersion',
    );
    _expect(response);
    return BanditSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<int> uploadSession({
    required SessionManifest manifest,
    required List<DecisionEvent> decisions,
    required List<FeatureFrame> frames,
    required List<int> raw,
    required String checksum,
  }) async {
    final response = await _send('POST', '/v1/sessions', {
      'manifest': manifest.toJson(),
      'decisions': [for (final decision in decisions) decision.toJson()],
      'frames': [for (final frame in frames) frame.toJson()],
      'raw_base64': base64Encode(raw),
      'checksum_sha256': checksum,
    });
    if (response.statusCode == 409) return 409;
    _expect(response);
    return response.statusCode;
  }

  Future<void> createCalibrationPlan(CalibrationPlan plan) async {
    final response = await _send(
      'POST',
      '/v1/meditation/calibration-plans',
      plan.toJson(),
    );
    _expect(response);
    final accepted = CalibrationPlan.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    final received = accepted.toJson(), expected = plan.toJson();
    for (final body in [received, expected]) {
      final profile = body['profile'] as Map<String, dynamic>;
      final created = DateTime.parse(profile['created_at'] as String);
      if (!created.isUtc) throw StateError('Invalid profile timestamp');
      profile['created_at'] = created.toUtc().toIso8601String();
    }
    if (!_sameJson(received, expected)) {
      throw StateError('Calibration acknowledgement does not match');
    }
  }

  Future<void> saveMeditationFeedback(MeditationFeedback feedback) async {
    final response = await _send(
      'POST',
      '/v1/meditation/sessions/${feedback.sessionId}/feedback',
      feedback.toJson(),
    );
    _expect(response);
    final accepted = jsonDecode(response.body) as Map<String, dynamic>;
    final expected = feedback.toJson();
    if (!_sameJson(accepted, expected)) {
      throw StateError('Feedback acknowledgement does not match');
    }
  }

  Future<String> createMeditationTrainingJob(
    Map<String, dynamic> request,
  ) async {
    final response = await _send(
      'POST',
      '/v1/meditation/training/jobs',
      request,
    );
    _expect(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<String> createTrainingJob({
    required String origin,
    required String experimentVersion,
  }) async {
    final response = await _send('POST', '/v1/training/jobs', {
      'origin': origin,
      'experiment_version': experimentVersion,
    });
    _expect(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<void> deleteSessions(List<String> sessionIds) async {
    final response = await _send('POST', '/v1/sessions/delete', {
      'session_ids': sessionIds,
    });
    _expect(response);
    final confirmed =
        (jsonDecode(response.body)
                as Map<String, dynamic>)['deleted_session_ids']
            as List;
    if (!sessionIds.every(confirmed.contains)) {
      throw StateError('Backenden bekräftade inte alla raderingar.');
    }
  }

  Future<http.Response> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final generation = _authGeneration;
    final usedAccess = accessToken;
    var response = await _request(method, path, body);
    _checkGeneration(generation);
    if (response.statusCode == 401 &&
        usedAccess != null &&
        refreshToken != null) {
      if (accessToken == usedAccess) await _refreshOnce();
      _checkGeneration(generation);
      response = await _request(method, path, body);
      _checkGeneration(generation);
    }
    return response;
  }

  Future<http.Response> _request(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    final headers = {
      'content-type': 'application/json',
      if (accessToken != null) 'authorization': 'Bearer $accessToken',
    };
    final uri = Uri.parse('$baseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);
    final request = switch (method) {
      'POST' => _http.post(uri, headers: headers, body: encoded),
      'GET' => _http.get(uri, headers: headers),
      _ => throw UnsupportedError(method),
    };
    return request.timeout(requestTimeout);
  }

  void _expect(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}

// JSON key order and the encoding of equivalent numbers do not change context.
bool _sameJson(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _sameJson(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _sameJson(left[index], right[index]));
  }
  return left == right;
}

Uint8List encodePcm16(Float64List stereo) {
  final bytes = Uint8List(stereo.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < stereo.length; i++) {
    final sample = (stereo[i] * 32767).round().clamp(-32767, 32767);
    view.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}
