import 'dart:math';
import 'audio_profile.dart';
import 'meditation.dart';
import 'models.dart';

/// The complete immutable blinded schedule and context of one comparison series.
class CalibrationPlan {
  CalibrationPlan({
    required this.id,
    required this.ownerAccountId,
    required this.profile,
    required this.eyeState,
    required this.origin,
    required List<StimulusAction> schedule,
    required this.createdAt,
  }) : schedule = List.unmodifiable(schedule) {
    if (!isAccountUuid(id) ||
        !isAccountUuid(ownerAccountId) ||
        profile.ownerAccountId != ownerAccountId ||
        origin == DataOrigin.playback ||
        schedule.length != 10 ||
        StimulusAction.values.any(
          (a) => schedule.where((s) => s == a).length != 2,
        )) {
      throw const FormatException('Invalid calibration plan');
    }
  }
  final String id, ownerAccountId;
  final AudioProfileVersion profile;
  final EyeState eyeState;
  final DataOrigin origin;
  final List<StimulusAction> schedule;
  final DateTime createdAt;
  static List<StimulusAction> shuffled(Random random) => [
    for (final action in StimulusAction.values) ...[action, action],
  ]..shuffle(random);
  Map<String, dynamic> sessionMetadata(int slot) {
    if (slot < 0 || slot >= 10) throw RangeError.range(slot, 0, 9);
    return {
      'mode': 'calibration',
      'owner_account_id': ownerAccountId,
      'calibration_plan_id': id,
      'calibration_slot': slot,
      'calibration_schema_version': 1,
    };
  }

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'id': id,
    'owner_account_id': ownerAccountId,
    'protocol_version': MeditationProtocol.protocolVersion,
    'profile_version_id': profile.id,
    'profile': profile.toJson(),
    'eye_state': eyeState.name,
    'origin': origin.name,
    'duration_seconds': 600,
    'schedule': schedule.map((a) => a.id).toList(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };
  factory CalibrationPlan.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['duration_seconds'] != 600 ||
        json['protocol_version'] != MeditationProtocol.protocolVersion) {
      throw const FormatException('Unsupported calibration plan');
    }
    final profile = AudioProfileVersion.fromJson(
      Map<String, dynamic>.from(json['profile'] as Map),
    );
    if (json['profile_version_id'] != profile.id) {
      throw const FormatException('Profile mismatch');
    }
    return CalibrationPlan(
      id: json['id'] as String,
      ownerAccountId: json['owner_account_id'] as String,
      profile: profile,
      eyeState: EyeState.values.byName(json['eye_state'] as String),
      origin: DataOrigin.values.byName(json['origin'] as String),
      schedule: [
        for (final id in json['schedule'] as List)
          StimulusAction.byId(id as String),
      ],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Mutable post-session ratings live outside the immutable recording.
class MeditationFeedback {
  const MeditationFeedback({
    required this.ownerAccountId,
    required this.sessionId,
    this.mentalBusyness,
    this.relaxation,
    required this.revision,
  });
  final String ownerAccountId, sessionId;
  final int? mentalBusyness, relaxation;
  final int revision;
  bool get complete => mentalBusyness != null && relaxation != null;
  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'owner_account_id': ownerAccountId,
    'session_id': sessionId,
    'mental_busyness': mentalBusyness,
    'relaxation': relaxation,
    'revision': revision,
  };
}
