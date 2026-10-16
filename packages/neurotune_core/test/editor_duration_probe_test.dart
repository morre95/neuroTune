import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../scripts/probe-session-duration.dart' as probe;

void main() {
  test(
    'fixed length preserves a fractional second and drains the last frame',
    () {
      final budget = probe.SessionBudget(30 * 48000 + 1);
      while (budget.nextPacket > 0) {
        budget.submit(budget.nextPacket);
      }
      expect(budget.submittedFrames, 1440001);
      expect(budget.completed, isFalse);
      budget.confirmPlayed(1440000);
      expect(budget.completed, isFalse);
      budget.confirmPlayed(1440001);
      expect(budget.completed, isTrue);
      expect(() => budget.confirmPlayed(1440000), throwsRangeError);
      expect(() => budget.confirmPlayed(1440002), throwsRangeError);
    },
  );

  test('selected time is immutable and independent of the source duration', () {
    final budget = probe.SessionBudget(20 * 60 * 48000, selectedSeconds: 2400);
    expect(budget.targetFrames, 115200000);
    expect(budget.sourceFrame(20 * 60 * 48000), 0);
    expect(budget.sourceFrame(budget.targetFrames - 1), 57599999);
    expect(() => budget.confirmPlayed(1), throwsRangeError);
    expect(() => budget.submit(9601), throwsRangeError);
    for (final seconds in [0, 59, 61, 3601]) {
      expect(
        () => probe.SessionBudget(48000, selectedSeconds: seconds),
        throwsRangeError,
      );
    }
    for (final frames in [0, -1, 3600 * 48000 + 1]) {
      expect(() => probe.SessionBudget(frames), throwsRangeError);
    }
  });

  test('final fade follows the session clock across a loop seam', () {
    final budget = probe.SessionBudget(599 * 48000, selectedSeconds: 600);
    final seam = 599 * 48000;
    expect(budget.sourceFrame(seam), 0);
    expect(budget.gain(seam - 1), greaterThan(budget.gain(seam)));
    expect(budget.gain(seam), closeTo(.2, .00001));
    expect(budget.gain(budget.targetFrames - 1), 0);
    expect(budget.gain(budget.targetFrames - 240001), 1);
  });

  test(
    'bounded PCM preserves late stereo samples and fractional tail',
    () async {
      final dir = await Directory.systemTemp.createTemp('duration-probe-test-');
      addTearDown(() => dir.delete(recursive: true));
      const frames = 601 * 48000 + 1;
      final file = File('${dir.path}/fractional.wav');
      await probe.writeFixture(file, frames);
      // Characterize the existing verifier: exact frames need E1, not a rounded
      // number of seconds passed to the schema-1 verifier.
      expect(await probe.legacyAccepts(file, 602), isFalse);
      final wave = await probe.ProbeWave.open(file, frames);
      addTearDown(wave.close);
      final looped = probe.SessionBudget(frames, selectedSeconds: 1200);
      final seam = ByteData.sublistView(
        await wave.packet(frames - 1, 3, looped),
      );
      expect(seam.getInt16(0, Endian.little), probe.fixtureSample(frames - 1));
      expect(seam.getInt16(4, Endian.little), -4800);
      expect(seam.getInt16(8, Endian.little), -4799);
      final budget = probe.SessionBudget(frames);
      final late = await wave.packet(600 * 48000 + 17, 3, budget);
      final pcm = ByteData.sublistView(late);
      // This position is in the final second: both channels share the fade.
      final gain = budget.gain(600 * 48000 + 17);
      expect(
        pcm.getInt16(0, Endian.little),
        (probe.fixtureSample(600 * 48000 + 17) * gain).round(),
      );
      expect(pcm.getInt16(2, Endian.little), -pcm.getInt16(0, Endian.little));
      expect(await wave.packet(frames - 1, 1, budget), [0, 0, 0, 0]);
      await expectLater(wave.packet(frames - 1, 2, budget), throwsRangeError);
      await expectLater(wave.packet(0, 9601, budget), throwsRangeError);
      await expectLater(
        probe.ProbeWave.open(file, frames - 1),
        throwsFormatException,
      );
      // The isolated reader detects a truncated file, including after open.
      final writer = await file.open(mode: FileMode.append);
      await writer.truncate(44 + (frames - 1) * 4);
      await writer.close();
      await expectLater(
        wave.packet(frames - 1, 1, budget),
        throwsFormatException,
      );
    },
  );
}
