import 'dart:convert';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  test('sample gaps and invalid channel values are counted separately', () {
    final tracker = DataLossTracker();
    List<SessionDiagnostic> add(double time, List<List<double>> samples) =>
        tracker.add(
          stream: 'eeg',
          timeSeconds: time,
          sampleRateHz: 4,
          channelNames: ['EEG1', 'EEG2'],
          samples: samples,
        );
    expect(
      add(0, [
        [1, 2],
        [3, 4],
      ]),
      isEmpty,
    );
    final events = add(1.0, [
      [double.nan, 2],
      [double.infinity, 4],
    ]);
    expect(events.first.values['duration_seconds'], 0.5);
    expect(events.first.values['missing_sample_slots'], 2);
    expect(events.last.values['channel_counts'], {'EEG1': 1, 'EEG2': 1});
    expect(
      add(1.5, [
        [1, 2],
        [3, 4],
      ]),
      isEmpty,
    );
  });

  test('non-finite raw values round-trip as missing samples in JSON', () {
    final source = SimulatorSource(
      config: ExperimentConfig.defaults(),
      sampleRateHz: 256,
      seed: 1,
    );
    final batch = source.pull();
    batch.eeg[0][5] = double.nan;
    batch.accel[0][0] = double.infinity;
    final decoded =
        jsonDecode(utf8.decode(encodeSessionRaw([batch], [])))
            as Map<String, dynamic>;
    final restored = EegBatch.fromJson(
      Map<String, dynamic>.from(decoded['eeg'][0] as Map),
    );
    expect(restored.eeg[0][5].isNaN, isTrue);
    expect(restored.accel[0][0].isNaN, isTrue);
    expect(restored.eeg[0][6], batch.eeg[0][6]);
  });

  test('EEG processing rejects NaN windows and recovers after they pass', () {
    final config = ExperimentConfig.defaults();
    final source = SimulatorSource(config: config, sampleRateHz: 256, seed: 1);
    final dsp = DspPipeline(
      config: config,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
    );
    final frames = <FeatureFrame>[];
    for (var index = 0; index < 24; index++) {
      final batch = source.pull();
      if (index == 8) batch.eeg[0][5] = double.nan;
      frames.addAll(dsp.addBatch(batch));
    }
    expect(
      frames.any(
        (frame) => frame.channels.first.reasons.contains('missing_samples'),
      ),
      isTrue,
    );
    expect(frames.last.channels.first.valid, isTrue);
    expect(
      frames.every((frame) => frame.channels.first.totalPower.isFinite),
      isTrue,
    );
    expect(
      () => jsonEncode(frames.map((e) => e.toJson()).toList()),
      returnsNormally,
    );
    final summary = summarizeChannelQuality(frames);
    expect(summary.first.validFraction, lessThan(1));
    expect(summary.first.reasons['missing_samples'], greaterThan(0));
  });

  test('old manifests remain readable without new diagnostics', () {
    final config = ExperimentConfig.defaults();
    final engine = SessionEngine(
      config: config,
      snapshot: BanditSnapshot.empty(
        experimentVersion: config.version,
        origin: DataOrigin.muse,
      ),
      sessionId: 'old',
      origin: DataOrigin.muse,
      mode: SessionMode.personal,
      eyeState: EyeState.open,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 1,
      startedAt: DateTime.utc(2026),
    );
    final json = engine.manifest().toJson()
      ..remove('diagnostics')
      ..remove('diagnostics_version');
    final restored = SessionManifest.fromJson(json);
    expect(restored.diagnostics, isEmpty);
    expect(restored.diagnosticsVersion, 0);
  });
}
