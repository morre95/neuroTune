import 'diagnostics.dart';
import 'models.dart';

/// Source identity supplied by the reusable recording lifecycle. A protocol
/// owns its scheduling, scoring and feature readiness, not the data source.
class SessionContext {
  const SessionContext({
    required this.sessionId,
    required this.origin,
    required this.eyeState,
    required this.sampleRateHz,
    required this.channelNames,
    required this.seed,
    required this.startedAt,
  });

  final String sessionId;
  final DataOrigin origin;
  final EyeState eyeState;
  final double sampleRateHz;
  final List<String> channelNames;
  final int seed;
  final DateTime startedAt;
}

typedef SessionProtocolFactory =
    SessionProtocol Function(SessionContext context);

/// Protocol boundary used by recording, output backpressure, interruptions,
/// diagnostics and persistence. Optics-dependent protocols may queue frames;
/// EEG-only protocols can make them immediately ready. No protocol progresses
/// while the shared lifecycle has an unacknowledged PCM write.
abstract interface class SessionProtocol {
  String get sessionId;
  SessionPhase get phase;
  bool get terminal;
  bool get waitingForResume;
  String get message;
  StimulusAction? get currentAction;
  StopReason? get stopReason;
  int get interruptions;
  List<FeatureFrame> get frames;
  List<DecisionEvent> get decisions;

  void queueFrame(FeatureFrame frame);
  void queueOptics(OpticsBatch batch);
  List<FeatureFrame> takeReadyFrames();
  void onFrame(FeatureFrame frame);
  void interrupt(StopReason reason);
  void abort(StopReason reason, String text);
  void resume();
  void finish();

  SessionManifest manifest({
    double? audioLatencyMs,
    String checksum = '',
    List<SessionDiagnostic> diagnostics = const [],
    int diagnosticsVersion = 0,
  });
}
