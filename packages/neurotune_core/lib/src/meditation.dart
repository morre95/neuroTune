import 'audio_profile.dart';
import 'meditation_adaptation.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'session_protocol.dart';

/// Independent EEG-only protocol. Only confirmed played PCM advances its clock.
class MeditationProtocol implements SessionProtocol {
  MeditationProtocol({
    required this.context,
    required this.profile,
    required this.action,
    this.metadata = const {},
    this.adaptation,
  });
  static const protocolVersion = 'meditation-1';
  static const sampleRate = 48000;
  static const totalFrames = 600 * sampleRate;
  final MeditationAdaptation? adaptation;
  final SessionContext context;
  final AudioProfileVersion profile;
  final StimulusAction action;
  final Map<String, dynamic> metadata;
  int playedFrames = 0;
  final List<Map<String, dynamic>> playbackTimeline = [];
  double? sourceObservedOffset;
  @override
  String get sessionId => context.sessionId;
  @override
  SessionPhase phase = SessionPhase.sound;
  @override
  bool get terminal =>
      phase == SessionPhase.completed || phase == SessionPhase.stopped;
  @override
  bool get waitingForResume => phase == SessionPhase.waitingStable;
  @override
  String get message => waitingForResume
      ? 'Ljudet är pausat.'
      : terminal
      ? 'Meditationen är sparad.'
      : 'Meditation · tio aktiva minuter.';
  @override
  StimulusAction get currentAction => adaptation?.action ?? action;
  @override
  StopReason? stopReason;
  @override
  int interruptions = 0;
  StopReason? _lastInterruption;
  @override
  final List<FeatureFrame> frames = [];
  final List<FeatureFrame> _queued = [];
  @override
  List<DecisionEvent> get decisions => const [];
  @override
  void queueFrame(FeatureFrame frame) => _queued.add(frame);
  @override
  void queueOptics(OpticsBatch batch) {}
  @override
  List<FeatureFrame> takeReadyFrames() {
    final result = List<FeatureFrame>.of(_queued);
    _queued.clear();
    return result;
  }

  @override
  void onFrame(FeatureFrame frame) {
    if (phase != SessionPhase.stopped) frames.add(frame);
  }

  void playback(int frames, double observedSeconds, {bool active = true}) {
    // Failure cleanup can recover frames played from a pending packet. Keep
    // that final checkpoint truthful without converting a stopped attempt into
    // a completed session.
    if (phase == SessionPhase.completed) return;
    playedFrames = frames.clamp(playedFrames, totalFrames);
    playbackTimeline.add({
      'observed_seconds': observedSeconds,
      'played_frames': playedFrames,
      'playback_active': active,
    });
    if (!terminal && playedFrames == totalFrames) {
      phase = SessionPhase.completed;
    }
  }

  void sourceAnchor(double sourceSeconds, double observedSeconds) {
    sourceObservedOffset ??= observedSeconds - sourceSeconds;
  }

  /// A window needs confirmed continuous playback coverage, using historical
  /// checkpoints rather than the controller state when delayed DSP arrives.
  FeatureFrame mapFrame(FeatureFrame frame, double windowSeconds) {
    final offset = sourceObservedOffset;
    if (offset == null) return frame.withPlayback(null, false);
    final start = frame.timeSeconds - windowSeconds + offset;
    final end = frame.timeSeconds + offset;
    // Checkpoints are monotonic. Binary search bounds so live minute scoring
    // does not repeatedly scan a ten-minute playback history on the UI isolate.
    int lowerBound(double time) {
      var low = 0, high = playbackTimeline.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if ((playbackTimeline[middle]['observed_seconds'] as double) < time) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    var beforeIndex = lowerBound(start);
    while (beforeIndex < playbackTimeline.length &&
        (playbackTimeline[beforeIndex]['observed_seconds'] as double) <=
            start) {
      beforeIndex++;
    }
    beforeIndex--;
    final afterIndex = lowerBound(end);
    if (beforeIndex < 0 || afterIndex >= playbackTimeline.length) {
      return frame.withPlayback(null, false);
    }
    final before = playbackTimeline[beforeIndex];
    final after = playbackTimeline[afterIndex];
    for (var i = beforeIndex + 1; i <= afterIndex; i++) {
      final a = playbackTimeline[i - 1];
      final b = playbackTimeline[i];
      final elapsed =
          (b['observed_seconds'] as double) - (a['observed_seconds'] as double);
      final played =
          ((b['played_frames'] as int) - (a['played_frames'] as int)) /
          sampleRate;
      if (a['playback_active'] != true ||
          b['playback_active'] != true ||
          elapsed <= 0 ||
          (elapsed - played).abs() > .075) {
        return frame.withPlayback(null, false);
      }
    }
    final aTime = before['observed_seconds'] as double;
    final bTime = after['observed_seconds'] as double;
    final seconds =
        ((before['played_frames'] as int) +
            ((after['played_frames'] as int) -
                    (before['played_frames'] as int)) *
                (end - aTime) /
                (bTime - aTime)) /
        sampleRate;
    return frame.withPlayback(seconds, true);
  }

  @override
  void interrupt(StopReason reason) {
    if (terminal) return;
    interruptions++;
    _lastInterruption = reason;
    phase = SessionPhase.waitingStable;
  }

  @override
  void resume() {
    if (waitingForResume) phase = SessionPhase.sound;
  }

  @override
  void abort(StopReason reason, String text) {
    if (!terminal) {
      stopReason = reason;
      phase = SessionPhase.stopped;
    }
  }

  @override
  void finish() {
    if (!terminal) {
      stopReason = StopReason.manual;
      phase = SessionPhase.stopped;
    }
  }

  @override
  SessionManifest manifest({
    double? audioLatencyMs,
    String checksum = '',
    List<SessionDiagnostic> diagnostics = const [],
    int diagnosticsVersion = 0,
  }) => SessionManifest(
    userId: null,
    sessionId: sessionId,
    experimentVersion: protocolVersion,
    policyVersion: adaptation == null ? 'fixed' : 'meditation-epsilon-0.1-v1',
    dataOrigin: context.origin.name,
    mode: 'meditation',
    eyeState: context.eyeState.name,
    sampleRateHz: context.sampleRateHz,
    channelNames: context.channelNames,
    selectedChannels: const [],
    startedAtIso: context.startedAt.toIso8601String(),
    durationSeconds: playedFrames / sampleRate,
    audioLatencyMs: audioLatencyMs,
    audioLatencySource: 'audiotrack_buffer_frames',
    timeline: 'monotonic_session_seconds',
    seed: context.seed,
    checksumSha256: checksum,
    stopReason: stopReason?.name,
    endedInPhase: phase.name,
    interruptions: interruptions,
    lastInterruptReason: _lastInterruption?.name,
    diagnostics: diagnostics,
    diagnosticsVersion: diagnosticsVersion,
    meditation: {
      ...metadata,
      'schema_version': 1,
      'protocol_version': protocolVersion,
      'mode': adaptation == null ? (metadata['mode'] ?? 'fixed') : 'adaptive',
      if (adaptation != null) ...{
        'model_version': adaptation!.statistics.model.modelVersion,
        'model_id': adaptation!.statistics.model.id,
        'preprocessing_version': 'meditation-eeg-1',
        'adaptive_decisions': adaptation!.decisions,
        'statistics_setup_key': adaptation!.statistics.setup.key,
      },
      'profile_version_id': profile.id,
      'profile': profile.toJson(),
      'fixed_action': action.id,
      'eye_state': context.eyeState.name,
      'origin': context.origin.name,
      'played_frames': playedFrames,
      'playback_timeline_version': 1,
      'source_observed_offset_seconds': sourceObservedOffset,
      'source_clock_mapping': 'first_batch_receipt_minus_batch_duration',
      'playback_timeline': playbackTimeline,
    },
  );
}
