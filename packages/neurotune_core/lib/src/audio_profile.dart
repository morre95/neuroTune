import 'dart:convert';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
bool isAccountUuid(String value) => _uuid.hasMatch(value);

/// An immutable owned background and its independent tone settings.
class AudioProfileVersion {
  AudioProfileVersion._(this._json);
  final Map<String, dynamic> _json;
  String get id => _json['id'] as String;
  String get ownerAccountId => _json['owner_account_id'] as String;
  String get profileId => _json['profile_id'] as String;
  int get version => _json['version'] as int;
  String get name => _json['name'] as String;
  String get backgroundAssetId => _json['background_asset_id'] as String;
  int get durationSeconds => _json['duration_seconds'] as int;
  double get carrierHz => (_json['carrier_hz'] as num).toDouble();
  double get toneGain => (_json['tone_gain'] as num).toDouble();
  double get backgroundGain => (_json['background_gain'] as num).toDouble();
  bool get loop => _json['loop'] as bool;
  String get checksumSha256 => _json['checksum_sha256'] as String;
  String get previewChecksumSha256 =>
      _json['preview_checksum_sha256'] as String;
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
  factory AudioProfileVersion.fromJson(Map<String, dynamic> json) {
    void require(bool value) {
      if (!value) throw const FormatException('Invalid audio profile');
    }

    require(
      json['schema_version'] == 1 &&
          json['sample_rate_hz'] == 48000 &&
          json['channels'] == 2 &&
          json['sample_width_bytes'] == 2,
    );
    for (final key in [
      'id',
      'owner_account_id',
      'profile_id',
      'background_asset_id',
    ]) {
      require(json[key] is String && isAccountUuid(json[key] as String));
    }
    require(json['version'] is int && (json['version'] as int) >= 1);
    require(
      json['name'] is String &&
          (json['name'] as String).isNotEmpty &&
          (json['name'] as String).length <= 120,
    );
    require(
      json['duration_seconds'] is int &&
          (json['duration_seconds'] as int) >= 30 &&
          (json['duration_seconds'] as int) <= 600,
    );
    for (final key in ['checksum_sha256', 'preview_checksum_sha256']) {
      require(
        json[key] is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(json[key] as String),
      );
    }
    bool range(String key, double low, double high) =>
        json[key] is num &&
        (json[key] as num).isFinite &&
        (json[key] as num) >= low &&
        (json[key] as num) <= high;
    require(
      range('carrier_hz', 100, 400) &&
          range('tone_gain', 0, .95) &&
          range('background_gain', 0, .95),
    );
    require(
      (json['tone_gain'] as num) + (json['background_gain'] as num) <=
          .95 + 2.220446049250313e-16,
    );
    require(
      range('normalization_factor', double.minPositive, 1) &&
          json['loop'] is bool,
    );
    require(
      json['recipe'] is Map &&
          json['recipe']['schema_version'] == 1 &&
          json['recipe']['duration_seconds'] == json['duration_seconds'],
    );
    final tracks = json['recipe']['tracks'];
    require(tracks is List && tracks.isNotEmpty && tracks.length <= 4);
    for (final track in tracks as List) {
      require(
        track is Map &&
            track['asset_id'] is String &&
            isAccountUuid(track['asset_id'] as String),
      );
      final start = track['trim_start_seconds'] ?? 0;
      final end = track['trim_end_seconds'];
      final gain = track['gain'] ?? 1;
      require(
        start is num &&
            start.isFinite &&
            start >= 0 &&
            end is num &&
            end.isFinite &&
            end > start &&
            end <= 600 &&
            gain is num &&
            gain.isFinite &&
            gain >= 0 &&
            gain <= 4 &&
            (track['loop'] ?? false) is bool,
      );
    }
    require(
      json['created_at'] is String &&
          DateTime.tryParse(json['created_at'] as String) != null,
    );
    return AudioProfileVersion._(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
  }
}
