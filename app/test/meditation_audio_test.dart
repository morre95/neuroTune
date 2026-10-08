import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/audio/meditation_renderer.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata;

void main() {
  test(
    'five-second glide integrates frequency and replays the same absolute phase',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-glide');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = wave();
      final json = metadata(bytes)..['background_gain'] = 0;
      final file = await File('${dir.path}/silence.wav').writeAsBytes(bytes);
      final r = await MeditationRenderer.open(
        file,
        AudioProfileVersion.fromJson(json),
        StimulusAction.binaural6,
      );
      addTearDown(r.close);
      const start = 60 * 48000;
      await r.scheduleAction(start, StimulusAction.binaural12);
      // Literal integral: 540.625 / 559.375 cycles after 2.5s.
      // Initial 60s at 217/223Hz contributes integral cycles.
      final pcm = ByteData.sublistView(await r.render(start + 120000, 1));
      expect(pcm.getInt16(0, Endian.little), closeTo(-4634, 1));
      expect(pcm.getInt16(2, Endian.little), closeTo(4634, 1));
      final whole = await r.render(start + 119950, 100);
      final a = await r.render(start + 119950, 50);
      final b = await r.render(start + 120000, 50);
      expect([...a, ...b], whole);
      await r.scheduleAction(120 * 48000, StimulusAction.control);
      expect(await r.render(start + 119950, 100), whole);
      final end = ByteData.sublistView(await r.render(start + 240000, 1));
      expect(end.getInt16(0, Endian.little), closeTo(0, 1));
      expect(end.getInt16(2, Endian.little), closeTo(0, 1));
    },
  );
  test(
    'offline rendered stereo keeps each background channel and fixed headroom',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-pcm');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = wave();
      final data = ByteData.sublistView(bytes);
      for (var f = 0; f < 30 * 48000; f++) {
        data.setInt16(44 + f * 4, 16384, Endian.little);
        data.setInt16(46 + f * 4, -8192, Endian.little);
      }
      final json = metadata(bytes)..['tone_gain'] = 0;
      final profile = AudioProfileVersion.fromJson(json);
      final file = await File('${dir.path}/background.wav').writeAsBytes(bytes);
      final renderer = await MeditationRenderer.open(
        file,
        profile,
        StimulusAction.control,
      );
      addTearDown(renderer.close);
      final pcm = ByteData.sublistView(await renderer.render(48000, 100));
      expect(pcm.getInt16(0, Endian.little), closeTo(9830, 1));
      expect(pcm.getInt16(2, Endian.little), closeTo(-4915, 1));
      final first = ByteData.sublistView(await renderer.render(0, 1));
      expect(first.getInt16(0, Endian.little), 0);
      final last = ByteData.sublistView(
        await renderer.render(600 * 48000 - 1, 1),
      );
      expect(last.getInt16(0, Endian.little).abs(), lessThanOrEqualTo(2));
      await expectLater(renderer.render(0, 9601), throwsRangeError);
    },
  );
  test(
    'loop overlap is linear for 500 ms and continues after the opening segment',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-loop');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = wave();
      final data = ByteData.sublistView(bytes);
      const end = 30 * 48000;
      for (var f = 0; f < end; f++) {
        final left = f < 24000
            ? 2000
            : f >= end - 24000
            ? -8000
            : 8000;
        data.setInt16(44 + f * 4, left, Endian.little);
        data.setInt16(46 + f * 4, -left, Endian.little);
      }
      final json = metadata(bytes)..['tone_gain'] = 0;
      final file = await File('${dir.path}/loop.wav').writeAsBytes(bytes);
      final r = await MeditationRenderer.open(
        file,
        AudioProfileVersion.fromJson(json),
        StimulusAction.control,
      );
      addTearDown(r.close);
      Future<int> left(int frame) async => ByteData.sublistView(
        await r.render(frame, 1),
      ).getInt16(0, Endian.little);
      expect(await left(end - 24000), closeTo(-4800, 1));
      expect(await left(end - 12000), closeTo(-1800, 1));
      expect(await left(end - 1), closeTo(1200, 1));
      expect(await left(end), closeTo(4800, 1));
      expect(await left(end + (end - 24000)), closeTo(4800, 1));
      json['loop'] = false;
      final once = await MeditationRenderer.open(
        file,
        AudioProfileVersion.fromJson(json),
        StimulusAction.control,
      );
      addTearDown(once.close);
      expect(
        ByteData.sublistView(
          await once.render(end, 1),
        ).getInt16(0, Endian.little),
        0,
      );
    },
  );

  test(
    'all five actions render carrier-centered separated tones and identical control',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-tones');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = wave();
      final json = metadata(bytes)..['background_gain'] = 0;
      final file = await File('${dir.path}/silence.wav').writeAsBytes(bytes);
      // Independently evaluated samples at 1.00125 seconds for a 220 Hz carrier.
      const expected = {
        0: [6473, 6473],
        6: [6495, 6447],
        8: [6502, 6437],
        10: [6508, 6427],
        12: [6514, 6417],
      };
      for (final a in StimulusAction.values) {
        final r = await MeditationRenderer.open(
          file,
          AudioProfileVersion.fromJson(json),
          a,
        );
        final pcm = ByteData.sublistView(await r.render(48060, 1));
        expect(
          pcm.getInt16(0, Endian.little),
          closeTo(expected[a.beatHz.toInt()]![0], 1),
        );
        expect(
          pcm.getInt16(2, Endian.little),
          closeTo(expected[a.beatHz.toInt()]![1], 1),
        );
        await r.close();
      }
    },
  );
  test(
    'duplicated mono stays identical and the digital sum retains headroom',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-headroom');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = wave();
      final data = ByteData.sublistView(bytes);
      for (var f = 0; f < 30 * 48000; f++) {
        data.setInt16(44 + f * 4, 32767, Endian.little);
        data.setInt16(46 + f * 4, 32767, Endian.little);
      }
      final json = metadata(bytes)..['tone_gain'] = .35;
      final file = await File('${dir.path}/mono.wav').writeAsBytes(bytes);
      final r = await MeditationRenderer.open(
        file,
        AudioProfileVersion.fromJson(json),
        StimulusAction.control,
      );
      addTearDown(r.close);
      final pcm = ByteData.sublistView(await r.render(48000, 9600));
      for (var f = 0; f < 9600; f++) {
        final left = pcm.getInt16(f * 4, Endian.little);
        expect(left, pcm.getInt16(f * 4 + 2, Endian.little));
        expect(left.abs(), lessThanOrEqualTo(31128));
      }
      final ramp = ByteData.sublistView(
        await r.render(48000, 7200, stopping: true),
      );
      expect(ramp.getInt16(0, Endian.little), closeTo(19660, 1));
      expect(ramp.getInt16((7200 - 1) * 4, Endian.little), 0);
    },
  );
}
