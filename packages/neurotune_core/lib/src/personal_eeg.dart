import 'dart:math' as math;
import 'models.dart';

const meditationEegPreprocessing = 'meditation-eeg-1';
const meditationEegQuality = '2026.4-unverified';

bool isCompatibleMeditationEegConfig(ExperimentConfig config) =>
    config.qualityVersion == meditationEegQuality &&
    config.welchWindowSeconds == 4 &&
    config.welchHopSeconds == 1 &&
    config.thetaHz == (4.0, 8.0) &&
    config.alphaHz == (8.0, 13.0) &&
    config.betaHz == (13.0, 30.0);

class MeditationMinute {
  MeditationMinute(this.minute, this.features, this.coverage);
  final int minute;
  final List<double> features;
  final Map<String, int> coverage;
}

/// Confirmed active endpoint bins, canonical frame before QC, 40/50 seconds
/// on at least two named channels. The first ten seconds never contribute.
List<MeditationMinute> extractMeditationMinutes(Iterable<FeatureFrame> frames) {
  int? bin(FeatureFrame f) {
    final t = f.activeTimeSeconds;
    if (f.playbackActive != true ||
        t == null ||
        !t.isFinite ||
        !f.timeSeconds.isFinite ||
        t <= 0 ||
        t > 600) {
      return null;
    }
    final b = (t - 1e-9).ceil();
    return b >= 1 && b <= 600 ? b : null;
  }

  final indexed = frames
      .toList()
      .asMap()
      .entries
      .where((e) => bin(e.value) != null)
      .toList();
  indexed.sort((a, b) {
    final active = a.value.activeTimeSeconds!.compareTo(
      b.value.activeTimeSeconds!,
    );
    if (active != 0) return active;
    final source = a.value.timeSeconds.compareTo(b.value.timeSeconds);
    return source != 0 ? source : a.key.compareTo(b.key);
  });
  final canonical = <int, FeatureFrame>{};
  for (final e in indexed) {
    canonical.putIfAbsent(bin(e.value)!, () => e.value);
  }
  final periods = <int, Map<String, Map<int, List<double>>>>{};
  for (final e in canonical.entries) {
    final minute = (e.key - 1) ~/ 60;
    if ((e.key - 1) % 60 < 10 || e.value.rejected) continue;
    final names = <String, int>{};
    for (final c in e.value.channels) {
      names.update(c.name, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final c in e.value.channels) {
      final powers = [c.absoluteTheta, c.absoluteAlpha, c.absoluteBeta];
      if (!c.valid ||
          names[c.name] != 1 ||
          powers.any((p) => !p.isFinite || p <= 0)) {
        continue;
      }
      final pair = [
        math.log(c.absoluteTheta) - math.log(c.absoluteAlpha),
        math.log(c.absoluteBeta) - math.log(c.absoluteAlpha),
      ];
      periods
              .putIfAbsent(minute, () => {})
              .putIfAbsent(c.name, () => {})[e.key] =
          pair;
    }
  }
  final result = <MeditationMinute>[];
  for (final minute in periods.keys.toList()..sort()) {
    final eligible = Map<String, Map<int, List<double>>>.fromEntries(
      periods[minute]!.entries.where((e) => e.value.length >= 40),
    );
    if (eligible.length < 2) continue;
    final pairs = eligible.values.expand((v) => v.values).toList();
    result.add(
      MeditationMinute(
        minute,
        [
          for (var i = 0; i < 2; i++)
            pairs.fold<double>(0, (sum, p) => sum + p[i]) / pairs.length,
        ],
        {
          for (final name in eligible.keys.toList()..sort())
            name: eligible[name]!.length,
        },
      ),
    );
  }
  return result;
}

/// Authenticated server artifact. A failed latest version is also an artifact,
/// and replaces an older ready version in the account/source cache.
class PersonalEegModel {
  PersonalEegModel._(this._json);
  final Map<String, dynamic> _json;
  String get ownerAccountId => _json['owner_account_id'] as String;
  String get origin => _json['origin'] as String;
  String get id => _json['id'] as String;
  String get modelVersion => _json['model_version'] as String;
  String get status => _json['status'] as String;
  Map<String, dynamic> get validation =>
      _deepCopy(Map<String, dynamic>.from(_json['validation'] as Map));
  List<String> get reasons =>
      List<String>.unmodifiable((_json['reasons'] as List).cast<String>());
  List<String> get backgrounds => List<String>.unmodifiable(
    (_json['backgrounds'] as List? ?? []).cast<String>(),
  );
  List<String> get eyes =>
      List<String>.unmodifiable((_json['eyes'] as List? ?? []).cast<String>());
  List<String> get includedSessionIds => List<String>.unmodifiable(
    (_json['included_session_ids'] as List).cast<String>(),
  );
  List<Map<String, dynamic>> get evidence => [
    for (final e in _json['evidence'] as List)
      _deepCopy(Map<String, dynamic>.from(e as Map)),
  ];
  List<Map<String, dynamic>> get fixedMinutes => [
    for (final e in _json['fixed_minutes'] as List? ?? [])
      _deepCopy(Map<String, dynamic>.from(e as Map)),
  ];
  Map<String, dynamic> toJson() => _deepCopy(_json);

  factory PersonalEegModel.fromJson(Map<String, dynamic> json) {
    void require(bool condition) {
      if (!condition) {
        throw const FormatException(
          'Unsupported or malformed personal EEG model',
        );
      }
    }

    bool number(dynamic v) => v is num && v.isFinite;
    require(
      json['schema_version'] == 1 &&
          json['preprocessing_version'] == meditationEegPreprocessing &&
          json['protocol_version'] == 'meditation-1' &&
          json['quality_version'] == meditationEegQuality,
    );
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    require(
      json['owner_account_id'] is String &&
          uuid.hasMatch(json['owner_account_id'] as String),
    );
    require(json['id'] is String && uuid.hasMatch(json['id'] as String));
    require(
      ['muse', 'simulator', 'playback'].contains(json['origin']) &&
          json['model_version'] is String,
    );
    require(
      [
        'ready',
        'insufficient',
        'failed_validation',
        'failed',
        'revoked',
        'stale',
      ].contains(json['status']),
    );
    require(
      json['dataset_fingerprint'] is String &&
          RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(json['dataset_fingerprint'] as String),
    );
    require(
      json['server_deletion_epoch'] is int &&
          (json['server_deletion_epoch'] as int) >= 0,
    );
    require(
      json['reasons'] is List &&
          (json['reasons'] as List).every((v) => v is String),
    );
    require(
      json['validation'] is Map &&
          json['evidence'] is List &&
          json['included_session_ids'] is List,
    );
    final ids = json['included_session_ids'] as List;
    require(ids.every((v) => v is String) && ids.toSet().length == ids.length);
    final evidence = json['evidence'] as List;
    require(
      evidence.length == ids.length &&
          evidence.every(
            (e) =>
                e is Map &&
                ids.contains(e['session_id']) &&
                e['checksum_sha256'] is String &&
                RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(e['checksum_sha256'] as String) &&
                e['feedback_revision'] is int &&
                e['feedback_revision'] >= 1,
          ),
    );
    require(evidence.map((e) => e['session_id']).toSet().length == ids.length);
    if (json['status'] == 'ready') {
      final validation = json['validation'] as Map;
      require(
        validation['session_count'] is int &&
            validation['session_count'] >= 20 &&
            validation['session_count'] == ids.length,
      );
      require(
        number(validation['mae']) &&
            validation['mae'] <= 2 &&
            validation['mae'] >= 0 &&
            number(validation['correlation']) &&
            validation['correlation'] >= .5 &&
            validation['correlation'] <= 1 &&
            number(validation['context_mae']) &&
            validation['context_mae'] > 0 &&
            validation['mae'] <= .8 * validation['context_mae'],
      );
      require(
        validation['gates'] is Map &&
            [
              'session_count',
              'mae',
              'correlation',
              'improvement',
            ].every((k) => validation['gates'][k] == true),
      );
      require(json['backgrounds'] is List && json['eyes'] is List);
      final bg = json['backgrounds'] as List, eyes = json['eyes'] as List;
      require(
        bg.isNotEmpty &&
            bg.every((v) => v is String) &&
            bg.toSet().length == bg.length &&
            eyes.isNotEmpty &&
            eyes.every((v) => ['open', 'closed'].contains(v)) &&
            eyes.toSet().length == eyes.length,
      );
      final order = [
        'log_theta_alpha',
        'log_beta_alpha',
        'carrier_hz',
        'tone_gain',
        'background_gain',
        ...bg.map((v) => 'background:$v'),
        ...eyes.map((v) => 'eye:$v'),
      ];
      require(
        json['feature_order'] is List &&
            (json['feature_order'] as List).join('|') == order.join('|'),
      );
      for (final k in ['means', 'scales', 'coefficients']) {
        require(
          json[k] is List &&
              (json[k] as List).length == order.length &&
              (json[k] as List).every(number),
        );
      }
      require(
        (json['scales'] as List).every((v) => v > 0) &&
            number(json['intercept']),
      );
      require(
        json['training_ranges'] is Map && json['supported_contexts'] is List,
      );
      for (final k in ['carrier_hz', 'tone_gain', 'background_gain']) {
        final range = json['training_ranges'][k];
        require(
          range is List &&
              range.length == 2 &&
              range.every(number) &&
              range[0] <= range[1],
        );
      }
      require(
        (json['supported_contexts'] as List).every(
          (c) =>
              c is Map &&
              bg.contains(c['background_asset_id']) &&
              eyes.contains(c['eye_state']) &&
              c['session_count'] is int &&
              c['session_count'] > 0,
        ),
      );
    }
    return PersonalEegModel._(_deepCopy(json));
  }

  String? unsupportedReason({
    required String backgroundAssetId,
    required String eyeState,
    required double carrierHz,
    required double toneGain,
    required double backgroundGain,
    ExperimentConfig? eegConfig,
  }) {
    if (eegConfig != null && !isCompatibleMeditationEegConfig(eegConfig)) {
      return 'The EEG preprocessing configuration is unsupported';
    }
    if (status != 'ready') {
      return reasons.isEmpty
          ? 'More rated fixed sessions are needed'
          : reasons.join('; ');
    }
    final contexts = _json['supported_contexts'] as List;
    if (!eyes.contains(eyeState) ||
        !contexts.any(
          (c) =>
              c['background_asset_id'] == backgroundAssetId &&
              c['eye_state'] == eyeState &&
              c['session_count'] >= 5,
        )) {
      return 'Collect at least five usable fixed sessions for this background and eye state';
    }
    final values = {
      'carrier_hz': carrierHz,
      'tone_gain': toneGain,
      'background_gain': backgroundGain,
    };
    for (final e in values.entries) {
      final range = _json['training_ranges'][e.key] as List;
      if (!e.value.isFinite || e.value < range[0] || e.value > range[1]) {
        return 'These audio settings are outside the training range';
      }
    }
    return null;
  }

  double predict(
    List<double> features, {
    required String backgroundAssetId,
    required String eyeState,
    required double carrierHz,
    required double toneGain,
    required double backgroundGain,
    ExperimentConfig? eegConfig,
  }) {
    final reason = unsupportedReason(
      backgroundAssetId: backgroundAssetId,
      eyeState: eyeState,
      carrierHz: carrierHz,
      toneGain: toneGain,
      backgroundGain: backgroundGain,
      eegConfig: eegConfig,
    );
    if (reason != null ||
        features.length != 2 ||
        features.any((v) => !v.isFinite)) {
      throw StateError(reason ?? 'Finite EEG feature pair required');
    }
    final row = [
      ...features,
      carrierHz,
      toneGain,
      backgroundGain,
      ...backgrounds.map((v) => v == backgroundAssetId ? 1.0 : 0.0),
      ...eyes.map((v) => v == eyeState ? 1.0 : 0.0),
    ];
    var result = (_json['intercept'] as num).toDouble();
    for (var i = 0; i < row.length; i++) {
      result +=
          (_json['coefficients'][i] as num).toDouble() *
          (row[i] - (_json['means'][i] as num).toDouble()) /
          (_json['scales'][i] as num).toDouble();
    }
    if (!result.isFinite) throw StateError('Non-finite prediction');
    return result;
  }
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) {
  dynamic copy(dynamic v) => v is Map
      ? {for (final e in v.entries) e.key as String: copy(e.value)}
      : v is List
      ? v.map(copy).toList()
      : v;
  return copy(value) as Map<String, dynamic>;
}
