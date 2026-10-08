import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'audio_profile.dart';
import 'models.dart';
import 'meditation.dart';
import 'calibration.dart';

double combinedMeditationScore(MeditationFeedback feedback) {
  final busy = feedback.mentalBusyness;
  final relaxed = feedback.relaxation;
  if (busy == null ||
      relaxed == null ||
      busy < 0 ||
      busy > 10 ||
      relaxed < 0 ||
      relaxed > 10) {
    throw ArgumentError('Complete ratings from 0 to 10 are required');
  }
  return (relaxed + 10 - busy) / 2;
}

/// Exact sound/eye/source identity. Display names do not affect comparisons.
class MeditationSetupContext {
  const MeditationSetupContext({
    required this.profile,
    required this.eyeState,
    required this.origin,
  });
  final AudioProfileVersion profile;
  final EyeState eyeState;
  final DataOrigin origin;
  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'profile_version_id': profile.id,
    'background_asset_id': profile.backgroundAssetId,
    'checksum_sha256': profile.checksumSha256,
    'carrier_hz': profile.carrierHz,
    'tone_gain': profile.toneGain,
    'background_gain': profile.backgroundGain,
    'loop': profile.loop,
    'background_duration_seconds': profile.durationSeconds,
    'eye_state': eyeState.name,
    'origin': origin.name,
    'protocol_version': MeditationProtocol.protocolVersion,
    'duration_seconds': 600,
  };
  String get key =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

class CalibrationObservation {
  CalibrationObservation({
    required this.setup,
    required this.action,
    required this.feedback,
  });
  final MeditationSetupContext setup;
  final StimulusAction action;
  final MeditationFeedback feedback;
  double get score => combinedMeditationScore(feedback);
}

const fixedActionOrder = [
  StimulusAction.control,
  StimulusAction.binaural6,
  StimulusAction.binaural8,
  StimulusAction.binaural10,
  StimulusAction.binaural12,
];

class FixedActionRecommendation {
  const FixedActionRecommendation(
    this.action,
    this.means,
    this.counts,
    this.pooled,
  );
  final StimulusAction action;
  final Map<StimulusAction, double> means;
  final Map<StimulusAction, int> counts;
  final bool pooled;
  int get sessionCount => counts.values.fold(0, (a, b) => a + b);
}

FixedActionRecommendation? recommendFixedAction(
  String owner,
  MeditationSetupContext setup,
  Iterable<CalibrationObservation> observations,
) {
  final eligible = observations
      .where(
        (o) =>
            o.feedback.ownerAccountId == owner &&
            o.setup.profile.ownerAccountId == owner &&
            o.setup.origin == setup.origin &&
            o.feedback.complete,
      )
      .toList();
  final matching = eligible.where((o) => o.setup.key == setup.key).toList();
  final selected = matching.isEmpty ? eligible : matching;
  if (selected.isEmpty) return null;
  final sums = <StimulusAction, double>{}, counts = <StimulusAction, int>{};
  for (final o in selected) {
    sums[o.action] = (sums[o.action] ?? 0) + o.score;
    counts[o.action] = (counts[o.action] ?? 0) + 1;
  }
  final means = {
    for (final action in fixedActionOrder)
      if (counts.containsKey(action)) action: sums[action]! / counts[action]!,
  };
  var best = means.keys.first;
  for (final action in means.keys) {
    if (means[action]! > means[best]!) best = action;
  }
  return FixedActionRecommendation(
    best,
    Map.unmodifiable(means),
    Map.unmodifiable(counts),
    matching.isEmpty,
  );
}
