import 'dart:convert';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'calibration_repository.dart';

class FixedMeditationChoice {
  const FixedMeditationChoice(this.setup, this.recommendation, this.preference);
  final MeditationSetupContext setup;
  final FixedActionRecommendation? recommendation;
  final StimulusAction? preference;
  StimulusAction get action =>
      preference ?? recommendation?.action ?? StimulusAction.control;
}

class CalibrationSlotResult {
  const CalibrationSlotResult(this.slot, this.action, this.feedback);
  final int slot;
  final StimulusAction action;
  final MeditationFeedback feedback;
  double get score => combinedMeditationScore(feedback);
}

/// Recommendations always derive from retained rated sessions. Explicit choices
/// have their own namespace and survive removal of calibration evidence.
class MeditationPreferenceRepository {
  MeditationPreferenceRepository(this.db, this.calibration);
  final AppDatabase db;
  final CalibrationRepository calibration;

  void _owned(String owner, MeditationSetupContext setup) {
    if (!isAccountUuid(owner) ||
        setup.profile.ownerAccountId != owner ||
        setup.origin == DataOrigin.playback) {
      throw ArgumentError('An owned Muse or simulator setup is required');
    }
  }

  String _key(String owner, MeditationSetupContext setup) =>
      'meditation_preference:v1:$owner:${setup.key}';

  Future<StimulusAction?> preference(
    String owner,
    MeditationSetupContext setup,
  ) async {
    _owned(owner, setup);
    final raw = await db.getKv(_key(owner, setup));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['schema_version'] != 1 ||
        json['owner_account_id'] != owner ||
        json['setup_key'] != setup.key ||
        jsonEncode(json['setup']) != jsonEncode(setup.toJson())) {
      throw const FormatException(
        'Unsupported or mismatched meditation preference',
      );
    }
    return StimulusAction.byId(json['action'] as String);
  }

  Future<void> choose(
    String owner,
    MeditationSetupContext setup,
    StimulusAction action,
  ) async {
    _owned(owner, setup);
    await db.putKv(
      _key(owner, setup),
      jsonEncode({
        'schema_version': 1,
        'owner_account_id': owner,
        'setup_key': setup.key,
        'setup': setup.toJson(),
        'action': action.id,
        'modified_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<FixedMeditationChoice> resolve(
    String owner,
    MeditationSetupContext setup,
  ) async {
    _owned(owner, setup);
    final observations = <CalibrationObservation>[];
    for (final progress in await calibration.allProgress(owner)) {
      // Completion is a session-level rule. An unfinished series contributes
      // its fully rated slots, while its result table stays blinded in the UI.
      final plan = progress.plan;
      if (plan.origin != setup.origin) continue;
      final context = MeditationSetupContext(
        profile: plan.profile,
        eyeState: plan.eyeState,
        origin: plan.origin,
      );
      for (final entry in progress.results.entries) {
        final feedback = await calibration.feedback(owner, entry.value.id);
        if (feedback?.complete == true) {
          observations.add(
            CalibrationObservation(
              setup: context,
              action: plan.schedule[entry.key],
              feedback: feedback!,
            ),
          );
        }
      }
    }
    return FixedMeditationChoice(
      setup,
      recommendFixedAction(owner, setup, observations),
      await preference(owner, setup),
    );
  }

  /// This public presentation boundary never reveals a partially finished plan.
  Future<List<CalibrationSlotResult>> revealedResults(
    String owner,
    String planId,
  ) async {
    final progress = await calibration.progress(owner, planId);
    if (!progress.complete) return [];
    return [
      for (var slot = 0; slot < 10; slot++)
        CalibrationSlotResult(
          slot,
          progress.plan.schedule[slot],
          (await calibration.feedback(owner, progress.results[slot]!.id))!,
        ),
    ];
  }
}
