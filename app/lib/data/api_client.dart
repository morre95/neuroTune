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
  AuthTokens({required this.accessToken, required this.refreshToken, required this.email});
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
  ApiClient({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? accessToken;
  String? refreshToken;

  Future<AuthTokens> register(String email, String password) => _tokens('/v1/auth/register', email, password);

  Future<AuthTokens> login(String email, String password) => _tokens('/v1/auth/login', email, password);

  Future<AuthTokens> _tokens(String path, String email, String password) async {
    final response = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _expect(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = json['access_token'] as String;
    refreshToken = json['refresh_token'] as String;
    return AuthTokens(accessToken: accessToken!, refreshToken: refreshToken!, email: email);
  }

  Future<void> refresh() async {
    final response = await _http.post(
      Uri.parse('$baseUrl/v1/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    _expect(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = json['access_token'] as String;
    refreshToken = json['refresh_token'] as String;
  }

  Future<void> logout() async {
    final response = await _send('POST', '/v1/auth/logout', {'refresh_token': refreshToken});
    _expect(response);
    accessToken = null;
    refreshToken = null;
  }

  Future<ExperimentConfig> activeExperiment() async {
    final response = await _send('GET', '/v1/experiments/active');
    _expect(response);
    return ExperimentConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<BanditSnapshot> latestBandit({required String origin, required String experimentVersion}) async {
    final response = await _send('GET', '/v1/bandit/latest?origin=$origin&experiment_version=$experimentVersion');
    _expect(response);
    return BanditSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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

  Future<String> createTrainingJob({required String origin, required String experimentVersion}) async {
    final response = await _send('POST', '/v1/training/jobs', {
      'origin': origin,
      'experiment_version': experimentVersion,
    });
    _expect(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<http.Response> _send(String method, String path, [Map<String, dynamic>? body]) {
    final headers = {'content-type': 'application/json', if (accessToken != null) 'authorization': 'Bearer $accessToken'};
    final uri = Uri.parse('$baseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);
    return switch (method) {
      'POST' => _http.post(uri, headers: headers, body: encoded),
      'GET' => _http.get(uri, headers: headers),
      _ => throw UnsupportedError(method),
    };
  }

  void _expect(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
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
