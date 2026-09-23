import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Embedded copy of `contracts/default_experiment.json`.
const String defaultExperimentJson = '''
{
  "version": "2026.2",
  "quality_version": "2026.2-unverified",
  "hardware_approved": false,
  "notch_hz": 50.0,
  "notch_q": 30.0,
  "bandpass_low_hz": 1.0,
  "bandpass_high_hz": 40.0,
  "filter_order": 4,
  "theta_hz": [4.0, 8.0],
  "alpha_hz": [8.0, 13.0],
  "beta_hz": [13.0, 30.0],
  "total_hz": [1.0, 40.0],
  "welch_window_seconds": 4.0,
  "welch_segment_seconds": 2.0,
  "welch_overlap": 0.5,
  "welch_hop_seconds": 1.0,
  "baseline_seconds": 120.0,
  "block_count": 15,
  "sound_seconds": 30.0,
  "pause_seconds": 10.0,
  "reward_tail_seconds": 20.0,
  "min_valid_fraction": 0.8,
  "reward_clip": 3.0,
  "max_extra_attempts": 5,
  "stable_frames_required": 3,
  "min_channels": 2,
  "min_baseline_valid_fraction": 0.5,
  "min_baseline_std": 0.002,
  "epsilon": 0.2,
  "actions": ["binaural_6", "binaural_8", "binaural_10", "binaural_12", "control"],
  "carrier_hz": 220.0,
  "amplitude": 0.2,
  "fade_ms": 150.0,
  "audio_sample_rate_hz": 48000,
  "saturation_uv": 750.0,
  "flatline_std_uv": 0.5,
  "jump_uv": 150.0,
  "motion_accel_g": 0.3,
  "motion_gyro_dps": 40.0,
  "gap_samples": 2,
  "optics_flatline_std_ua": 0.0001,
  "outer_nir_channels": ["OPTICS3", "OPTICS4"]
}
''';

enum StimulusAction {
  binaural6('binaural_6', 6),
  binaural8('binaural_8', 8),
  binaural10('binaural_10', 10),
  binaural12('binaural_12', 12),
  control('control', 0);

  const StimulusAction(this.id, this.beatHz);
  final String id;
  final double beatHz;

  static StimulusAction byId(String id) =>
      StimulusAction.values.firstWhere((action) => action.id == id);

  /// Left and right carrier tones. Control is the same tone in both ears.
  (double left, double right) tones(double carrierHz) {
    if (beatHz == 0) return (carrierHz, carrierHz);
    return (carrierHz - beatHz / 2, carrierHz + beatHz / 2);
  }
}

enum DataOrigin { simulator, playback, muse }

enum SessionMode { personal, comparison }

enum EyeState { open, closed }

enum SessionPhase { baseline, sound, pause, waitingStable, completed, stopped }

enum StopReason {
  manual,
  audioLost,
  background,
  sourceDisconnected,
  baselineFailed,
  attemptLimit,
}

class ExperimentConfig {
  ExperimentConfig({
    required this.version,
    required this.qualityVersion,
    required this.hardwareApproved,
    required this.notchHz,
    required this.notchQ,
    required this.bandpassLowHz,
    required this.bandpassHighHz,
    required this.filterOrder,
    required this.thetaHz,
    required this.alphaHz,
    required this.betaHz,
    required this.totalHz,
    required this.welchWindowSeconds,
    required this.welchSegmentSeconds,
    required this.welchOverlap,
    required this.welchHopSeconds,
    required this.baselineSeconds,
    required this.blockCount,
    required this.soundSeconds,
    required this.pauseSeconds,
    required this.rewardTailSeconds,
    required this.minValidFraction,
    required this.rewardClip,
    required this.maxExtraAttempts,
    required this.stableFramesRequired,
    required this.minChannels,
    required this.minBaselineValidFraction,
    required this.minBaselineStd,
    required this.epsilon,
    required this.actions,
    required this.carrierHz,
    required this.amplitude,
    required this.fadeMs,
    required this.audioSampleRateHz,
    required this.saturationUv,
    required this.flatlineStdUv,
    required this.jumpUv,
    required this.motionAccelG,
    required this.motionGyroDps,
    required this.gapSamples,
    required this.opticsFlatlineStdUa,
    required this.outerNirChannels,
  });

  factory ExperimentConfig.defaults() => ExperimentConfig.fromJson(
    jsonDecode(defaultExperimentJson) as Map<String, dynamic>,
  );

  factory ExperimentConfig.fromJson(Map<String, dynamic> json) {
    return ExperimentConfig(
      version: json['version'] as String,
      qualityVersion: json['quality_version'] as String,
      hardwareApproved: json['hardware_approved'] as bool,
      notchHz: (json['notch_hz'] as num).toDouble(),
      notchQ: (json['notch_q'] as num).toDouble(),
      bandpassLowHz: (json['bandpass_low_hz'] as num).toDouble(),
      bandpassHighHz: (json['bandpass_high_hz'] as num).toDouble(),
      filterOrder: json['filter_order'] as int,
      thetaHz: _pair(json['theta_hz']),
      alphaHz: _pair(json['alpha_hz']),
      betaHz: _pair(json['beta_hz']),
      totalHz: _pair(json['total_hz']),
      welchWindowSeconds: (json['welch_window_seconds'] as num).toDouble(),
      welchSegmentSeconds: (json['welch_segment_seconds'] as num).toDouble(),
      welchOverlap: (json['welch_overlap'] as num).toDouble(),
      welchHopSeconds: (json['welch_hop_seconds'] as num).toDouble(),
      baselineSeconds: (json['baseline_seconds'] as num).toDouble(),
      blockCount: json['block_count'] as int,
      soundSeconds: (json['sound_seconds'] as num).toDouble(),
      pauseSeconds: (json['pause_seconds'] as num).toDouble(),
      rewardTailSeconds: (json['reward_tail_seconds'] as num).toDouble(),
      minValidFraction: (json['min_valid_fraction'] as num).toDouble(),
      rewardClip: (json['reward_clip'] as num).toDouble(),
      maxExtraAttempts: json['max_extra_attempts'] as int,
      stableFramesRequired: json['stable_frames_required'] as int,
      minChannels: json['min_channels'] as int,
      minBaselineValidFraction: (json['min_baseline_valid_fraction'] as num)
          .toDouble(),
      minBaselineStd: (json['min_baseline_std'] as num).toDouble(),
      epsilon: (json['epsilon'] as num).toDouble(),
      actions: (json['actions'] as List<dynamic>)
          .map((item) => '$item')
          .toList(),
      carrierHz: (json['carrier_hz'] as num).toDouble(),
      amplitude: (json['amplitude'] as num).toDouble(),
      fadeMs: (json['fade_ms'] as num).toDouble(),
      audioSampleRateHz: json['audio_sample_rate_hz'] as int,
      saturationUv: (json['saturation_uv'] as num).toDouble(),
      flatlineStdUv: (json['flatline_std_uv'] as num).toDouble(),
      jumpUv: (json['jump_uv'] as num).toDouble(),
      motionAccelG: (json['motion_accel_g'] as num).toDouble(),
      motionGyroDps: (json['motion_gyro_dps'] as num).toDouble(),
      gapSamples: json['gap_samples'] as int,
      opticsFlatlineStdUa: (json['optics_flatline_std_ua'] as num).toDouble(),
      outerNirChannels: (json['outer_nir_channels'] as List<dynamic>)
          .map((item) => '$item')
          .toList(),
    );
  }

  final String version;
  final String qualityVersion;
  final bool hardwareApproved;
  final double notchHz;
  final double notchQ;
  final double bandpassLowHz;
  final double bandpassHighHz;
  final int filterOrder;
  final (double, double) thetaHz;
  final (double, double) alphaHz;
  final (double, double) betaHz;
  final (double, double) totalHz;
  final double welchWindowSeconds;
  final double welchSegmentSeconds;
  final double welchOverlap;
  final double welchHopSeconds;
  final double baselineSeconds;
  final int blockCount;
  final double soundSeconds;
  final double pauseSeconds;
  final double rewardTailSeconds;
  final double minValidFraction;
  final double rewardClip;
  final int maxExtraAttempts;
  final int stableFramesRequired;
  final int minChannels;
  final double minBaselineValidFraction;
  final double minBaselineStd;
  final double epsilon;
  final List<String> actions;
  final double carrierHz;
  final double amplitude;
  final double fadeMs;
  final int audioSampleRateHz;
  final double saturationUv;
  final double flatlineStdUv;
  final double jumpUv;
  final double motionAccelG;
  final double motionGyroDps;
  final int gapSamples;

  /// Standard deviation below which an outer-NIR hop is flat, in microamps.
  final double opticsFlatlineStdUa;

  /// LibMuse 8.0.9 names for 850 nm left and right outer optics.
  final List<String> outerNirChannels;

  int samplesFor(double seconds, double sampleRateHz) =>
      (seconds * sampleRateHz).round();

  Map<String, dynamic> toJson() => {
    'version': version,
    'quality_version': qualityVersion,
    'hardware_approved': hardwareApproved,
    'notch_hz': notchHz,
    'notch_q': notchQ,
    'bandpass_low_hz': bandpassLowHz,
    'bandpass_high_hz': bandpassHighHz,
    'filter_order': filterOrder,
    'theta_hz': [thetaHz.$1, thetaHz.$2],
    'alpha_hz': [alphaHz.$1, alphaHz.$2],
    'beta_hz': [betaHz.$1, betaHz.$2],
    'total_hz': [totalHz.$1, totalHz.$2],
    'welch_window_seconds': welchWindowSeconds,
    'welch_segment_seconds': welchSegmentSeconds,
    'welch_overlap': welchOverlap,
    'welch_hop_seconds': welchHopSeconds,
    'baseline_seconds': baselineSeconds,
    'block_count': blockCount,
    'sound_seconds': soundSeconds,
    'pause_seconds': pauseSeconds,
    'reward_tail_seconds': rewardTailSeconds,
    'min_valid_fraction': minValidFraction,
    'reward_clip': rewardClip,
    'max_extra_attempts': maxExtraAttempts,
    'stable_frames_required': stableFramesRequired,
    'min_channels': minChannels,
    'min_baseline_valid_fraction': minBaselineValidFraction,
    'min_baseline_std': minBaselineStd,
    'epsilon': epsilon,
    'actions': actions,
    'carrier_hz': carrierHz,
    'amplitude': amplitude,
    'fade_ms': fadeMs,
    'audio_sample_rate_hz': audioSampleRateHz,
    'saturation_uv': saturationUv,
    'flatline_std_uv': flatlineStdUv,
    'jump_uv': jumpUv,
    'motion_accel_g': motionAccelG,
    'motion_gyro_dps': motionGyroDps,
    'gap_samples': gapSamples,
    'optics_flatline_std_ua': opticsFlatlineStdUa,
    'outer_nir_channels': outerNirChannels,
  };

  ExperimentConfig withProtocol({
    double? baselineSeconds,
    int? blockCount,
    double? soundSeconds,
    double? pauseSeconds,
    double? rewardTailSeconds,
    double? notchHz,
    bool? hardwareApproved,
  }) {
    final json = toJson();
    if (baselineSeconds != null) json['baseline_seconds'] = baselineSeconds;
    if (blockCount != null) json['block_count'] = blockCount;
    if (soundSeconds != null) json['sound_seconds'] = soundSeconds;
    if (pauseSeconds != null) json['pause_seconds'] = pauseSeconds;
    if (rewardTailSeconds != null) {
      json['reward_tail_seconds'] = rewardTailSeconds;
    }
    if (notchHz != null) json['notch_hz'] = notchHz;
    if (hardwareApproved != null) json['hardware_approved'] = hardwareApproved;
    return ExperimentConfig.fromJson(json);
  }
}

class EegBatch {
  EegBatch({
    required this.channelNames,
    required this.unit,
    required this.sampleRateHz,
    required this.timeSeconds,
    required this.eeg,
    required this.accel,
    required this.gyro,
    required this.contact,
  });

  final List<String> channelNames;
  final String unit;
  final double sampleRateHz;

  /// Session time of the first sample. Monotonic within the session.
  final double timeSeconds;

  /// Microvolts, shaped `[channel][sample]`.
  final List<List<double>> eeg;

  /// Acceleration in g, shaped `[sample][xyz]`.
  final List<List<double>> accel;

  /// Angular velocity in degrees per second, shaped `[sample][xyz]`.
  final List<List<double>> gyro;

  /// Contact codes per sample and channel. 1 is good, 2 is usable, 4 is bad.
  final List<List<int>> contact;

  int get sampleCount => eeg.isEmpty ? 0 : eeg.first.length;

  Map<String, dynamic> toJson() => {
    'channel_names': channelNames,
    'unit': unit,
    'sample_rate_hz': sampleRateHz,
    'time_seconds': timeSeconds,
    'eeg': eeg,
    'accel': accel,
    'gyro': gyro,
    'contact': contact,
  };

  factory EegBatch.fromJson(Map<String, dynamic> json) {
    return EegBatch(
      channelNames: (json['channel_names'] as List<dynamic>)
          .map((e) => '$e')
          .toList(),
      unit: json['unit'] as String,
      sampleRateHz: (json['sample_rate_hz'] as num).toDouble(),
      timeSeconds: (json['time_seconds'] as num).toDouble(),
      eeg: _matrix(json['eeg']),
      accel: _matrix(json['accel']),
      gyro: _matrix(json['gyro']),
      contact: [
        for (final row in json['contact'] as List<dynamic>)
          [for (final value in row as List<dynamic>) value as int],
      ],
    );
  }
}

/// Raw optics. LibMuse 8.0.9 reports these values in microamps.
class OpticsBatch {
  OpticsBatch({
    required this.channelNames,
    required this.unit,
    required this.sampleRateHz,
    required this.timeSeconds,
    required this.values,
  });

  final List<String> channelNames;
  final String unit;
  final double sampleRateHz;
  final double timeSeconds;

  /// Shaped `[channel][sample]`.
  final List<List<double>> values;

  int get sampleCount => values.isEmpty ? 0 : values.first.length;

  Map<String, dynamic> toJson() => {
    'channel_names': channelNames,
    'unit': unit,
    'sample_rate_hz': sampleRateHz,
    'time_seconds': timeSeconds,
    'values': values,
  };

  factory OpticsBatch.fromJson(Map<String, dynamic> json) {
    return OpticsBatch(
      channelNames: (json['channel_names'] as List<dynamic>)
          .map((item) => '$item')
          .toList(),
      unit: json['unit'] as String,
      sampleRateHz: (json['sample_rate_hz'] as num).toDouble(),
      timeSeconds: (json['time_seconds'] as num).toDouble(),
      values: _matrix(json['values']),
    );
  }
}

/// One-second mean of one optics channel.
class OpticsFeature {
  OpticsFeature({
    required this.name,
    required this.valid,
    required this.intensity,
    required this.reasons,
  });

  final String name;
  final bool valid;
  final double intensity;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
    'name': name,
    'valid': valid,
    'intensity': intensity,
    'reasons': reasons,
  };

  factory OpticsFeature.fromJson(Map<String, dynamic> json) => OpticsFeature(
    name: json['name'] as String,
    valid: json['valid'] as bool,
    intensity: (json['intensity'] as num).toDouble(),
    reasons: (json['reasons'] as List<dynamic>).map((item) => '$item').toList(),
  );
}

class ChannelFeature {
  ChannelFeature({
    required this.name,
    required this.valid,
    required this.contact,
    required this.absoluteTheta,
    required this.absoluteAlpha,
    required this.absoluteBeta,
    required this.relativeTheta,
    required this.relativeAlpha,
    required this.relativeBeta,
    required this.totalPower,
    required this.reasons,
  });

  final String name;
  final bool valid;
  final int contact;
  final double absoluteTheta;
  final double absoluteAlpha;
  final double absoluteBeta;
  final double relativeTheta;
  final double relativeAlpha;
  final double relativeBeta;
  final double totalPower;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
    'name': name,
    'valid': valid,
    'contact': contact,
    'absolute_theta': absoluteTheta,
    'absolute_alpha': absoluteAlpha,
    'absolute_beta': absoluteBeta,
    'relative_theta': relativeTheta,
    'relative_alpha': relativeAlpha,
    'relative_beta': relativeBeta,
    'total_power': totalPower,
    'reasons': reasons,
  };

  factory ChannelFeature.fromJson(Map<String, dynamic> json) => ChannelFeature(
    name: json['name'] as String,
    valid: json['valid'] as bool,
    contact: json['contact'] as int,
    absoluteTheta: (json['absolute_theta'] as num).toDouble(),
    absoluteAlpha: (json['absolute_alpha'] as num).toDouble(),
    absoluteBeta: (json['absolute_beta'] as num).toDouble(),
    relativeTheta: (json['relative_theta'] as num).toDouble(),
    relativeAlpha: (json['relative_alpha'] as num).toDouble(),
    relativeBeta: (json['relative_beta'] as num).toDouble(),
    totalPower: (json['total_power'] as num).toDouble(),
    reasons: (json['reasons'] as List<dynamic>).map((e) => '$e').toList(),
  );
}

class FeatureFrame {
  FeatureFrame({
    required this.timeSeconds,
    required this.sampleRateHz,
    required this.channels,
    required this.rejected,
    required this.reasons,
    this.optics = const [],
  });

  final double timeSeconds;
  final double sampleRateHz;
  final List<ChannelFeature> channels;
  final bool rejected;
  final List<String> reasons;
  final List<OpticsFeature> optics;

  bool channelValid(String name) {
    if (rejected) return false;
    final channel = channels.where((item) => item.name == name);
    if (channel.isEmpty) return false;
    return channel.first.valid;
  }

  bool opticsValid(String name) {
    final channel = optics.where((item) => item.name == name);
    if (channel.isEmpty) return false;
    return channel.first.valid;
  }

  FeatureFrame withOptics(List<OpticsFeature> optics) {
    return FeatureFrame(
      timeSeconds: timeSeconds,
      sampleRateHz: sampleRateHz,
      channels: channels,
      rejected: rejected,
      reasons: reasons,
      optics: optics,
    );
  }

  Map<String, dynamic> toJson() => {
    'time_seconds': timeSeconds,
    'sample_rate_hz': sampleRateHz,
    'channels': channels.map((channel) => channel.toJson()).toList(),
    'rejected': rejected,
    'reasons': reasons,
    'optics': optics.map((channel) => channel.toJson()).toList(),
  };

  factory FeatureFrame.fromJson(Map<String, dynamic> json) => FeatureFrame(
    timeSeconds: (json['time_seconds'] as num).toDouble(),
    sampleRateHz: (json['sample_rate_hz'] as num).toDouble(),
    channels: [
      for (final channel in json['channels'] as List<dynamic>)
        ChannelFeature.fromJson(channel as Map<String, dynamic>),
    ],
    rejected: json['rejected'] as bool,
    reasons: (json['reasons'] as List<dynamic>).map((e) => '$e').toList(),
    optics: [
      for (final channel in json['optics'] as List<dynamic>? ?? const [])
        OpticsFeature.fromJson(channel as Map<String, dynamic>),
    ],
  );
}

class DecisionEvent {
  DecisionEvent({
    required this.sessionId,
    required this.blockIndex,
    required this.attemptIndex,
    required this.action,
    required this.selectionProbability,
    required this.reward,
    required this.meanAbsoluteTheta,
    this.meanOuterNir,
    required this.validFraction,
    required this.updatedBandit,
    required this.experimentVersion,
    required this.policyVersion,
    required this.qualityVersion,
    required this.startedAtSeconds,
    required this.endedAtSeconds,
    required this.aborted,
    this.abortReason,
  });

  final String sessionId;
  final int blockIndex;
  final int attemptIndex;
  final String action;
  final double selectionProbability;
  final double? reward;
  final double? meanAbsoluteTheta;

  /// Mean raw outer-NIR intensity, in microamps, over the reward window.
  final double? meanOuterNir;
  final double validFraction;
  final bool updatedBandit;
  final String experimentVersion;
  final String policyVersion;
  final String qualityVersion;
  final double startedAtSeconds;
  final double endedAtSeconds;
  final bool aborted;
  final String? abortReason;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'block_index': blockIndex,
    'attempt_index': attemptIndex,
    'action': action,
    'selection_probability': selectionProbability,
    'reward': reward,
    'mean_absolute_theta': meanAbsoluteTheta,
    'mean_outer_nir': meanOuterNir,
    'valid_fraction': validFraction,
    'updated_bandit': updatedBandit,
    'experiment_version': experimentVersion,
    'policy_version': policyVersion,
    'quality_version': qualityVersion,
    'started_at_seconds': startedAtSeconds,
    'ended_at_seconds': endedAtSeconds,
    'aborted': aborted,
    'abort_reason': abortReason,
  };

  factory DecisionEvent.fromJson(Map<String, dynamic> json) => DecisionEvent(
    sessionId: json['session_id'] as String,
    blockIndex: json['block_index'] as int,
    attemptIndex: json['attempt_index'] as int,
    action: json['action'] as String,
    selectionProbability: (json['selection_probability'] as num).toDouble(),
    reward: (json['reward'] as num?)?.toDouble(),
    meanAbsoluteTheta: (json['mean_absolute_theta'] as num?)?.toDouble(),
    meanOuterNir: (json['mean_outer_nir'] as num?)?.toDouble(),
    validFraction: (json['valid_fraction'] as num).toDouble(),
    updatedBandit: json['updated_bandit'] as bool,
    experimentVersion: json['experiment_version'] as String,
    policyVersion: json['policy_version'] as String,
    qualityVersion: json['quality_version'] as String,
    startedAtSeconds: (json['started_at_seconds'] as num).toDouble(),
    endedAtSeconds: (json['ended_at_seconds'] as num).toDouble(),
    aborted: json['aborted'] as bool,
    abortReason: json['abort_reason'] as String?,
  );
}

class SessionManifest {
  SessionManifest({
    required this.sessionId,
    required this.userId,
    required this.experimentVersion,
    required this.policyVersion,
    required this.dataOrigin,
    required this.mode,
    required this.eyeState,
    required this.sampleRateHz,
    required this.channelNames,
    required this.selectedChannels,
    required this.startedAtIso,
    required this.durationSeconds,
    required this.audioLatencyMs,
    required this.audioLatencySource,
    required this.timeline,
    required this.seed,
    required this.checksumSha256,
  });

  final String sessionId;
  final String? userId;
  final String experimentVersion;
  final String policyVersion;
  final String dataOrigin;
  final String mode;
  final String eyeState;
  final double sampleRateHz;
  final List<String> channelNames;
  final List<String> selectedChannels;
  final String startedAtIso;
  final double durationSeconds;

  /// Estimated output delay. See [audioLatencySource].
  final double? audioLatencyMs;

  /// How [audioLatencyMs] was estimated, so it is not read as ear-canal latency.
  final String audioLatencySource;
  final String timeline;
  final int seed;
  final String checksumSha256;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'user_id': userId,
    'experiment_version': experimentVersion,
    'policy_version': policyVersion,
    'data_origin': dataOrigin,
    'mode': mode,
    'eye_state': eyeState,
    'sample_rate_hz': sampleRateHz,
    'channel_names': channelNames,
    'selected_channels': selectedChannels,
    'started_at_iso': startedAtIso,
    'duration_seconds': durationSeconds,
    'audio_latency_ms': audioLatencyMs,
    'audio_latency_source': audioLatencySource,
    'timeline': timeline,
    'seed': seed,
    'checksum_sha256': checksumSha256,
  };

  factory SessionManifest.fromJson(Map<String, dynamic> json) =>
      SessionManifest(
        sessionId: json['session_id'] as String,
        userId: json['user_id'] as String?,
        experimentVersion: json['experiment_version'] as String,
        policyVersion: json['policy_version'] as String,
        dataOrigin: json['data_origin'] as String,
        mode: json['mode'] as String,
        eyeState: json['eye_state'] as String,
        sampleRateHz: (json['sample_rate_hz'] as num).toDouble(),
        channelNames: (json['channel_names'] as List<dynamic>)
            .map((e) => '$e')
            .toList(),
        selectedChannels: (json['selected_channels'] as List<dynamic>)
            .map((e) => '$e')
            .toList(),
        startedAtIso: json['started_at_iso'] as String,
        durationSeconds: (json['duration_seconds'] as num).toDouble(),
        audioLatencyMs: (json['audio_latency_ms'] as num?)?.toDouble(),
        audioLatencySource: json['audio_latency_source'] as String,
        timeline: json['timeline'] as String,
        seed: json['seed'] as int,
        checksumSha256: json['checksum_sha256'] as String,
      );
}

class ActionStat {
  const ActionStat(this.n, this.mean);
  final int n;
  final double mean;

  ActionStat observe(double reward) {
    final next = n + 1;
    return ActionStat(next, mean + (reward - mean) / next);
  }

  Map<String, dynamic> toJson() => {'n': n, 'mean': mean};

  factory ActionStat.fromJson(Map<String, dynamic> json) =>
      ActionStat(json['n'] as int, (json['mean'] as num).toDouble());
}

class BanditSnapshot {
  BanditSnapshot({
    required this.policyVersion,
    required this.experimentVersion,
    required this.dataOrigin,
    required this.epsilon,
    required this.actions,
    required this.includedSessionIds,
    required this.createdAtIso,
  });

  final String policyVersion;
  final String experimentVersion;
  final String dataOrigin;
  final double epsilon;
  final Map<StimulusAction, ActionStat> actions;
  final List<String> includedSessionIds;
  final String createdAtIso;

  factory BanditSnapshot.empty({
    required String experimentVersion,
    required DataOrigin origin,
    double epsilon = 0.2,
  }) {
    return BanditSnapshot(
      policyVersion: '0',
      experimentVersion: experimentVersion,
      dataOrigin: origin.name,
      epsilon: epsilon,
      actions: {
        for (final action in StimulusAction.values)
          action: const ActionStat(0, 0),
      },
      includedSessionIds: const [],
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
    );
  }

  BanditSnapshot copyWith({
    Map<StimulusAction, ActionStat>? actions,
    List<String>? includedSessionIds,
    String? policyVersion,
  }) {
    return BanditSnapshot(
      policyVersion: policyVersion ?? this.policyVersion,
      experimentVersion: experimentVersion,
      dataOrigin: dataOrigin,
      epsilon: epsilon,
      actions: actions ?? this.actions,
      includedSessionIds: includedSessionIds ?? this.includedSessionIds,
      createdAtIso: createdAtIso,
    );
  }

  Map<String, dynamic> toJson() => {
    'policy_version': policyVersion,
    'experiment_version': experimentVersion,
    'data_origin': dataOrigin,
    'epsilon': epsilon,
    'actions': {
      for (final entry in actions.entries) entry.key.id: entry.value.toJson(),
    },
    'included_session_ids': includedSessionIds,
    'created_at_iso': createdAtIso,
  };

  factory BanditSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['actions'] as Map<String, dynamic>;
    return BanditSnapshot(
      policyVersion: json['policy_version'] as String,
      experimentVersion: json['experiment_version'] as String,
      dataOrigin: json['data_origin'] as String,
      epsilon: (json['epsilon'] as num).toDouble(),
      actions: {
        for (final entry in raw.entries)
          StimulusAction.byId(entry.key): ActionStat.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
      includedSessionIds: (json['included_session_ids'] as List<dynamic>)
          .map((e) => '$e')
          .toList(),
      createdAtIso: json['created_at_iso'] as String,
    );
  }
}

class LocalReward {
  const LocalReward(this.action, this.reward);
  final StimulusAction action;
  final double reward;
}

class LocalSessionRewards {
  const LocalSessionRewards({
    required this.sessionId,
    required this.origin,
    required this.experimentVersion,
    required this.personal,
    required this.rewards,
  });

  final String sessionId;
  final DataOrigin origin;
  final String experimentVersion;
  final bool personal;
  final List<LocalReward> rewards;
}

/// Applies local rewarded blocks that the server snapshot does not already include.
BanditSnapshot overlayLocalRewards({
  required BanditSnapshot server,
  required List<LocalSessionRewards> local,
}) {
  final stats = {
    for (final entry in server.actions.entries) entry.key: entry.value,
  };
  for (final action in StimulusAction.values) {
    stats.putIfAbsent(action, () => const ActionStat(0, 0));
  }
  final included = server.includedSessionIds.toSet();
  for (final session in local) {
    if (!session.personal) continue;
    if (session.origin.name != server.dataOrigin) continue;
    if (session.experimentVersion != server.experimentVersion) continue;
    if (included.contains(session.sessionId)) continue;
    for (final reward in session.rewards) {
      stats[reward.action] = stats[reward.action]!.observe(reward.reward);
    }
  }
  return server.copyWith(actions: stats);
}

class UploadJob {
  UploadJob({
    required this.sessionId,
    required this.checksum,
    required this.payload,
    this.state = 'pending',
    this.attempts = 0,
    this.lastError,
  });

  final String sessionId;
  final String checksum;
  final List<int> payload;
  String state;
  int attempts;
  String? lastError;
}

class UploadQueue {
  final List<UploadJob> jobs = [];

  void add(UploadJob job) {
    final existing = jobs.where((item) => item.sessionId == job.sessionId);
    if (existing.isEmpty) jobs.add(job);
  }

  List<UploadJob> get pending =>
      jobs.where((job) => job.state != 'done').toList();

  Future<void> flush(Future<int> Function(UploadJob job) send) async {
    for (final job in jobs) {
      if (job.state == 'done' || job.state == 'conflict') continue;
      try {
        final status = await send(job);
        if (status == 200 || status == 201) {
          job.state = 'done';
          job.lastError = null;
        } else if (status == 409) {
          job.state = 'conflict';
          job.lastError = 'checksum';
        } else {
          job.attempts += 1;
          job.state = 'pending';
          job.lastError = 'http $status';
        }
      } catch (error) {
        job.attempts += 1;
        job.state = 'pending';
        job.lastError = '$error';
      }
    }
  }
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String newSessionId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

(double, double) _pair(Object? value) {
  final list = value as List<dynamic>;
  return ((list[0] as num).toDouble(), (list[1] as num).toDouble());
}

List<List<double>> _matrix(Object? value) => [
  for (final row in value as List<dynamic>)
    [for (final item in row as List<dynamic>) (item as num).toDouble()],
];
