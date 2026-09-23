import 'dart:math';
import 'dart:typed_data';

import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  const sampleRate = 48000.0;

  test('binaural 6 Hz, control, fades, and stop', () {
    final config = ExperimentConfig.defaults();
    final synth = BinauralSynth(
      sampleRateHz: sampleRate,
      carrierHz: config.carrierHz,
      amplitude: config.amplitude,
      fadeSeconds: config.fadeMs / 1000,
    );
    synth.setAction(StimulusAction.binaural6);
    final rendered = synth.render(config.samplesFor(config.fadeMs / 1000, sampleRate) + 32768);
    expect(rendered.first.abs(), lessThan(0.01));
    expect(_maxStep(rendered), lessThan(0.05));
    expect(peakHz(rendered, left: true, sampleRateHz: sampleRate), closeTo(217, 2));
    expect(peakHz(rendered, left: false, sampleRateHz: sampleRate), closeTo(223, 2));

    final control = BinauralSynth(
      sampleRateHz: sampleRate,
      carrierHz: config.carrierHz,
      amplitude: config.amplitude,
      fadeSeconds: config.fadeMs / 1000,
    );
    control.setAction(StimulusAction.control);
    final both = control.render(config.samplesFor(config.fadeMs / 1000, sampleRate) + 32768);
    expect(peakHz(both, left: true, sampleRateHz: sampleRate), closeTo(220, 2));
    expect(peakHz(both, left: false, sampleRateHz: sampleRate), closeTo(220, 2));
    final steadyStart = both.length - 2000;
    for (var i = steadyStart; i < both.length; i += 2) {
      expect(both[i], closeTo(both[i + 1], 1e-12));
    }

    control.setAction(null);
    final stopped = control.render(config.samplesFor(config.fadeMs / 1000, sampleRate) + 100);
    expect(stopped.last.abs(), lessThan(1e-9));
    expect(stopped[stopped.length - 2].abs(), lessThan(1e-9));
  });

  test('epsilon-greedy prefers the better action and still explores', () {
    final policy = EpsilonPolicy(epsilon: 0.2, random: Random(3));
    for (var i = 0; i < 30; i++) {
      policy.observe(StimulusAction.binaural10, 1);
      for (final action in StimulusAction.values) {
        if (action != StimulusAction.binaural10) policy.observe(action, 0);
      }
    }
    final picks = [for (var i = 0; i < 200; i++) policy.select()];
    final counts = <StimulusAction, int>{};
    for (final pick in picks) {
      counts[pick.action] = (counts[pick.action] ?? 0) + 1;
    }
    expect(counts[StimulusAction.binaural10], greaterThan(140));
    expect(counts.keys, hasLength(greaterThan(1)));
  });

  test('local rewards are applied once and skipped once the server includes them', () {
    final server = BanditSnapshot.empty(experimentVersion: '2026.1', origin: DataOrigin.simulator);
    const local = LocalSessionRewards(
      sessionId: 'a',
      origin: DataOrigin.simulator,
      experimentVersion: '2026.1',
      personal: true,
      rewards: [LocalReward(StimulusAction.binaural8, 1)],
    );
    final first = overlayLocalRewards(server: server, local: const [local]);
    final second = overlayLocalRewards(server: server, local: const [local]);
    expect(first.actions[StimulusAction.binaural8]!.n, 1);
    expect(second.actions[StimulusAction.binaural8]!.n, 1);

    final included = server.copyWith(
      includedSessionIds: const ['a'],
      actions: {StimulusAction.binaural8: const ActionStat(1, 1)},
    );
    final afterUpload = overlayLocalRewards(
      server: included,
      local: const [
        local,
        LocalSessionRewards(
          sessionId: 'b',
          origin: DataOrigin.simulator,
          experimentVersion: '2026.1',
          personal: true,
          rewards: [LocalReward(StimulusAction.binaural8, 1)],
        ),
      ],
    );
    expect(afterUpload.actions[StimulusAction.binaural8]!.n, 2);
    expect(afterUpload.actions[StimulusAction.binaural8]!.mean, 1);

    final muse = overlayLocalRewards(
      server: BanditSnapshot.empty(experimentVersion: '2026.1', origin: DataOrigin.muse),
      local: const [local],
    );
    expect(muse.actions[StimulusAction.binaural8]!.n, 0);
  });

  test('upload retries do not send a finished job again', () async {
    final queue = UploadQueue();
    queue.add(UploadJob(sessionId: 's', checksum: 'abc', payload: [1, 2, 3]));
    var calls = 0;
    await queue.flush((job) async {
      calls += 1;
      throw Exception('offline');
    });
    expect(queue.pending, hasLength(1));
    await queue.flush((job) async {
      calls += 1;
      return 201;
    });
    await queue.flush((job) async {
      calls += 1;
      return 201;
    });
    expect(calls, 2);
    expect(queue.pending, isEmpty);
    queue.add(UploadJob(sessionId: 's', checksum: 'abc', payload: [1, 2, 3]));
    expect(queue.jobs, hasLength(1));
  });

  test('duplicate checksum conflict is not retried', () async {
    final queue = UploadQueue();
    queue.add(UploadJob(sessionId: 's', checksum: 'abc', payload: [1]));
    var calls = 0;
    await queue.flush((job) async {
      calls += 1;
      return 409;
    });
    await queue.flush((job) async {
      calls += 1;
      return 200;
    });
    expect(calls, 1);
    expect(queue.jobs.single.state, 'conflict');
  });
}

double _maxStep(Float64List samples) {
  var peak = 0.0;
  for (var i = 2; i < samples.length; i++) {
    peak = max(peak, (samples[i] - samples[i - 2]).abs());
  }
  return peak;
}
