import 'models.dart';

/// Timestamped session diagnostics; absent data must not be read as zero events.
class SessionDiagnostic {
  const SessionDiagnostic({
    required this.timeSeconds,
    required this.type,
    required this.values,
  });

  final double timeSeconds;
  final String type;
  final Map<String, dynamic> values;

  Map<String, dynamic> toJson() => {
    'time_seconds': timeSeconds,
    'type': type,
    'values': values,
  };

  factory SessionDiagnostic.fromJson(Map<String, dynamic> json) =>
      SessionDiagnostic(
        timeSeconds: (json['time_seconds'] as num).toDouble(),
        type: json['type'] as String,
        values: Map<String, dynamic>.from(json['values'] as Map),
      );
}

/// Measures missing sample slots separately from non-finite channel values.
/// A missing sample slot affects all channels; invalid values are per channel.
class DataLossTracker {
  final Map<String, double> _expected = {};

  List<SessionDiagnostic> add({
    required String stream,
    required double timeSeconds,
    required double sampleRateHz,
    required List<String> channelNames,
    required List<List<double>> samples,
  }) {
    final result = <SessionDiagnostic>[];
    final previous = _expected[stream];
    final gap = previous == null ? 0.0 : timeSeconds - previous;
    // Ignore sub-sample timestamp rounding, but record even a single lost slot.
    if (gap * sampleRateHz >= 0.5) {
      result.add(
        SessionDiagnostic(
          timeSeconds: previous!,
          type: 'data_gap',
          values: {
            'stream': stream,
            'duration_seconds': gap,
            'missing_sample_slots': (gap * sampleRateHz).round(),
          },
        ),
      );
    }
    final invalid = <String, int>{};
    for (var channel = 0; channel < samples.length; channel++) {
      final count = samples[channel].where((value) => !value.isFinite).length;
      if (count > 0) invalid[channelNames[channel]] = count;
    }
    if (invalid.isNotEmpty) {
      result.add(
        SessionDiagnostic(
          timeSeconds: timeSeconds,
          type: 'invalid_samples',
          values: {'stream': stream, 'channel_counts': invalid},
        ),
      );
    }
    _expected[stream] = timeSeconds + samples.first.length / sampleRateHz;
    return result;
  }
}

class ChannelQualitySummary {
  ChannelQualitySummary(this.name);
  final String name;
  int frames = 0;
  int validFrames = 0;
  final Map<String, int> reasons = {};
  double get validFraction => frames == 0 ? 0 : validFrames / frames;
}

List<ChannelQualitySummary> summarizeChannelQuality(List<FeatureFrame> frames) {
  final summaries = <String, ChannelQualitySummary>{};
  for (final frame in frames) {
    for (final channel in frame.channels) {
      final summary = summaries.putIfAbsent(
        channel.name,
        () => ChannelQualitySummary(channel.name),
      );
      summary.frames++;
      if (channel.valid && !frame.rejected) summary.validFrames++;
      for (final reason in {...channel.reasons, ...frame.reasons}) {
        summary.reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
      }
    }
  }
  return summaries.values.toList();
}
