import 'dart:convert';
import 'models.dart';
import 'personal_eeg.dart';
import 'recommendation.dart';

/// Contributions, rather than opaque totals, allow owned deletion to rebuild
/// the same model/setup bucket. Every score was produced by this model version.
class MeditationActionStatistics {
  MeditationActionStatistics._(this.owner, this.setup, this.model, this._items);
  final String owner;
  final MeditationSetupContext setup;
  final PersonalEegModel model;
  final List<Map<String, dynamic>> _items;
  List<Map<String, dynamic>> get contributions => [
    for (final item in _items) Map<String, dynamic>.from(item),
  ];
  List<String> get includedSessionIds => {
    ...model.includedSessionIds,
    ..._items.map((i) => i['session_id'] as String),
  }.toList()..sort();
  Map<StimulusAction, int> get counts => {
    for (final action in fixedActionOrder)
      action: _items.where((i) => i['action'] == action.id).length,
  };
  Map<StimulusAction, double> get means {
    final result = <StimulusAction, double>{};
    for (final action in fixedActionOrder) {
      final scores = _items
          .where((i) => i['action'] == action.id)
          .map((i) => (i['score'] as num).toDouble())
          .toList();
      if (scores.isNotEmpty) {
        final mean = scores.fold<double>(
          0,
          (sum, score) => sum + score / scores.length,
        );
        if (!mean.isFinite) throw StateError('Non-finite action mean');
        result[action] = mean;
      }
    }
    return result;
  }

  factory MeditationActionStatistics.seeded(
    String owner,
    MeditationSetupContext setup,
    PersonalEegModel model,
  ) {
    if (model.ownerAccountId != owner ||
        setup.profile.ownerAccountId != owner ||
        model.origin != setup.origin.name) {
      throw ArgumentError('Owned source-specific model required');
    }
    final stats = MeditationActionStatistics._(owner, setup, model, []);
    final p = setup.profile;
    for (final seed in model.fixedMinutes) {
      // A profile version is immutable. Also validate every exported context
      // field, never pool scores from a different sound/eye/setup.
      if (seed['profile_version_id'] != p.id ||
          seed['background_asset_id'] != p.backgroundAssetId ||
          seed['eye_state'] != setup.eyeState.name ||
          seed['carrier_hz'] != p.carrierHz ||
          seed['tone_gain'] != p.toneGain ||
          seed['background_gain'] != p.backgroundGain)
        continue;
      final evidence = model.evidence.where(
        (e) => e['session_id'] == seed['session_id'],
      );
      if (evidence.isEmpty) continue;
      stats._add({
        'kind': 'fixed',
        'session_id': seed['session_id'],
        'minute': seed['minute'],
        'action': seed['fixed_action'],
        'score': seed['score'],
        'checksum_sha256': evidence.single['checksum_sha256'],
        'feedback_revision': evidence.single['feedback_revision'],
      });
    }
    return stats;
  }
  void _add(Map<String, dynamic> item) {
    if (!['fixed', 'adaptive'].contains(item['kind']) ||
        item['session_id'] is! String ||
        (item['session_id'] as String).isEmpty ||
        item['minute'] is! int ||
        item['minute'] < 0 ||
        item['minute'] >= 10 ||
        !fixedActionOrder.any((a) => a.id == item['action']) ||
        item['score'] is! num ||
        !(item['score'] as num).isFinite ||
        (item['checksum_sha256'] != null &&
            (item['checksum_sha256'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(item['checksum_sha256'] as String)))) {
      throw const FormatException('Malformed meditation action contribution');
    }
    final id = '${item['kind']}:${item['session_id']}:${item['minute']}';
    if (_items.any(
      (i) => '${i['kind']}:${i['session_id']}:${i['minute']}' == id,
    ))
      return;
    _items.add(Map<String, dynamic>.from(item));
  }

  void observe(
    String sessionId,
    int minute,
    StimulusAction action,
    double score,
  ) => _add({
    'kind': 'adaptive',
    'session_id': sessionId,
    'minute': minute,
    'action': action.id,
    'score': score,
    'checksum_sha256': null,
  });
  void attachChecksum(String sessionId, String checksum) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum))
      throw ArgumentError('SHA256 required');
    for (final item in _items) {
      if (item['kind'] == 'adaptive' && item['session_id'] == sessionId)
        item['checksum_sha256'] = checksum;
    }
  }

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'owner_account_id': owner,
    'origin': setup.origin.name,
    'protocol_version': 'meditation-1',
    'setup_key': setup.key,
    'setup': setup.toJson(),
    'model_version': model.modelVersion,
    'model_id': model.id,
    'dataset_fingerprint': model.toJson()['dataset_fingerprint'],
    'model_evidence': model.evidence,
    'contributions': contributions,
  };
  factory MeditationActionStatistics.fromJson(
    Map<String, dynamic> json,
    String owner,
    MeditationSetupContext setup,
    PersonalEegModel model,
  ) {
    if (json['schema_version'] != 1 ||
        json['owner_account_id'] != owner ||
        json['origin'] != setup.origin.name ||
        json['protocol_version'] != 'meditation-1' ||
        json['setup_key'] != setup.key ||
        json['model_version'] != model.modelVersion ||
        json['model_id'] != model.id ||
        json['dataset_fingerprint'] != model.toJson()['dataset_fingerprint'] ||
        jsonEncode(json['setup']) != jsonEncode(setup.toJson()) ||
        jsonEncode(json['model_evidence']) != jsonEncode(model.evidence) ||
        json['contributions'] is! List) {
      throw const FormatException('Mismatched meditation statistics scope');
    }
    final result = MeditationActionStatistics.seeded(owner, setup, model);
    for (final item in json['contributions'] as List) {
      if (item is! Map) throw const FormatException('Malformed contribution');
      final value = Map<String, dynamic>.from(item);
      if (value['kind'] == 'fixed')
        continue; // Immutable artifact seeds are authoritative.
      result._add(value);
    }
    result.means; // Reject finite scores whose aggregate overflows.
    return result;
  }
}

/// Session-owned policy. The model, preprocessing and setup never change here.
class MeditationAdaptation {
  MeditationAdaptation({
    required this.statistics,
    required StimulusAction initialAction,
    required this.randomUnit,
  }) : action = initialAction;
  final MeditationActionStatistics statistics;
  final double Function() randomUnit;
  StimulusAction action;
  int _nextMinute = 0;
  final List<Map<String, dynamic>> decisions = [];
  String? get unsupportedReason {
    final s = statistics.setup, p = s.profile;
    return statistics.model.unsupportedReason(
      backgroundAssetId: p.backgroundAssetId,
      eyeState: s.eyeState.name,
      carrierHz: p.carrierHz,
      toneGain: p.toneGain,
      backgroundGain: p.backgroundGain,
    );
  }

  double _random() {
    final n = randomUnit();
    if (!n.isFinite || n < 0 || n >= 1)
      throw StateError('Random unit must be in [0,1)');
    return n;
  }

  Map<String, dynamic>? evaluate({
    required String sessionId,
    required int playedFrames,
    required int ownedFrames,
    required Iterable<FeatureFrame> frames,
  }) {
    if (_nextMinute >= 10 || playedFrames < (_nextMinute + 1) * 60 * 48000)
      return null;
    final minute = _nextMinute++;
    final available = extractMeditationMinutes(
      frames,
    ).where((m) => m.minute == minute);
    final qualified = available.isNotEmpty;
    double? score;
    final previous = action;
    if (qualified) {
      final s = statistics.setup, p = s.profile;
      score = statistics.model.predict(
        available.single.features,
        backgroundAssetId: p.backgroundAssetId,
        eyeState: s.eyeState.name,
        carrierHz: p.carrierHz,
        toneGain: p.toneGain,
        backgroundGain: p.backgroundGain,
      );
      statistics.observe(sessionId, minute, previous, score);
    }
    final terminal = minute == 9;
    var reason = qualified ? 'exploitation' : 'insufficient_eeg_coverage';
    Map<String, double> probabilities = {previous.id: 1};
    if (qualified && !terminal) {
      final means = statistics.means;
      var best = previous;
      for (final candidate in fixedActionOrder) {
        if (means[candidate] != null && means[candidate]! > means[best]!)
          best = candidate;
      }
      final exploit = best != previous && means[best]! - means[previous]! >= .5
          ? best
          : previous;
      probabilities = {
        for (final a in fixedActionOrder) a.id: a == exploit ? .92 : .02,
      };
      if (_random() < .1) {
        action = fixedActionOrder[(_random() * 5).floor()];
        reason = 'exploration';
      } else {
        action = exploit;
        reason = exploit == previous
            ? 'advantage_below_threshold'
            : 'exploitation';
      }
    }
    final changed = !terminal && action != previous;
    final start = ownedFrames > playedFrames ? ownedFrames : playedFrames;
    final decision = <String, dynamic>{
      'minute': minute,
      'boundary_played_frames': (minute + 1) * 60 * 48000,
      'evaluated_played_frames': playedFrames,
      'action': previous.id,
      'selected_action': terminal ? null : action.id,
      'score': score,
      'quality': {
        'eligible': qualified,
        'coverage': qualified ? available.single.coverage : <String, int>{},
        'denominator_seconds': 50,
        'required_seconds_per_channel': 40,
        'required_channels': 2,
      },
      'updated_statistics': qualified,
      'reason': terminal ? 'session_complete' : reason,
      'probabilities': terminal ? <String, double>{} : probabilities,
      'selection_probability': terminal ? null : probabilities[action.id],
      'transition_start_frame': changed ? start : null,
      'transition_duration_frames': changed ? 5 * 48000 : null,
      'from_beat_hz': previous.beatHz,
      'to_beat_hz': terminal ? null : action.beatHz,
      'model_version': statistics.model.modelVersion,
      'action_counts': {
        for (final e in statistics.counts.entries) e.key.id: e.value,
      },
      'action_means': {
        for (final e in statistics.means.entries) e.key.id: e.value,
      },
    };
    decisions.add(decision);
    return decision;
  }
}
