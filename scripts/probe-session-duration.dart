// Isolated A2 experiment, not an app renderer or a public profile contract.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../app/lib/data/canonical_wave.dart';

Future<bool> legacyAccepts(File file, int seconds) async {
  try {
    await CanonicalWave.inspect(file, seconds: seconds);
    return true;
  } on FormatException {
    return false;
  }
}

// Keep Linux's mapping high-water alongside the portable runtime counter.
// Platform-dependent accounting can differ; do not subtract unrelated counters.
int peakRss() {
  if (!Platform.isLinux) return ProcessInfo.maxRss;
  final status = File('/proc/self/status').readAsStringSync();
  return int.parse(RegExp(r'VmHWM:\s+(\d+) kB').firstMatch(status)![1]!) * 1024;
}

class SessionBudget {
  SessionBudget(this.sourceFrames, {int? selectedSeconds})
    : targetFrames = selectedSeconds == null
          ? sourceFrames
          : selectedSeconds * 48000 {
    if (sourceFrames < 1 ||
        sourceFrames > 3600 * 48000 ||
        (selectedSeconds != null &&
            (selectedSeconds < 60 ||
                selectedSeconds > 3600 ||
                selectedSeconds % 60 != 0))) {
      throw RangeError('Source or selected duration');
    }
  }
  final int sourceFrames;
  final int targetFrames;
  int submittedFrames = 0;
  int playedFrames = 0;
  int get nextPacket => min(9600, targetFrames - submittedFrames);
  bool get completed => playedFrames == targetFrames;

  void submit(int count) {
    if (count < 1 || count > nextPacket) throw RangeError('Packet budget');
    submittedFrames += count;
  }

  // Simulated native playback head. Padding and wall-clock time never advance
  // active time. Pausing means no confirmed progress, not a fresh budget.
  void confirmPlayed(int frames) {
    if (frames < playedFrames || frames > submittedFrames) {
      throw RangeError('Playback head');
    }
    playedFrames = frames;
  }

  int sourceFrame(int sessionFrame) => sessionFrame % sourceFrames;
  double gain(int sessionFrame) =>
      min(1.0, max(0.0, (targetFrames - 1 - sessionFrame) / 240000));
}

int fixtureSample(int frame) => frame % 9600 - 4800 + (frame ~/ 96000) * 2;

/// Writes real PCM in bounded reusable blocks, never a sparse/truncated fixture.
Future<void> writeFixture(File file, int frames) async {
  final header = Uint8List(44);
  final h = ByteData.sublistView(header);
  header.setRange(0, 4, ascii.encode('RIFF'));
  h.setUint32(4, frames * 4 + 36, Endian.little);
  header.setRange(8, 16, ascii.encode('WAVEfmt '));
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 2, Endian.little);
  h.setUint32(24, 48000, Endian.little);
  h.setUint32(28, 192000, Endian.little);
  h.setUint16(32, 4, Endian.little);
  h.setUint16(34, 16, Endian.little);
  header.setRange(36, 40, ascii.encode('data'));
  h.setUint32(40, frames * 4, Endian.little);
  final block = Uint8List(96000 * 4);
  final pcm = ByteData.sublistView(block);
  final output = await file.open(mode: FileMode.write);
  try {
    await output.writeFrom(header);
    for (var f = 0; f < frames; f += 96000) {
      for (var i = 0; i < min(96000, frames - f); i++) {
        pcm.setInt16(i * 4, fixtureSample(f + i), Endian.little);
        pcm.setInt16(i * 4 + 2, -fixtureSample(f + i), Endian.little);
      }
      await output.writeFrom(block, 0, min(96000, frames - f) * 4);
    }
  } finally {
    await output.close();
  }
}

/// Deliberately only accepts our 44-byte fixture format. Production E1 must
/// retain CanonicalWave's RIFF metadata support and streaming checksum check.
class ProbeWave {
  ProbeWave._(this.input, this.frames);
  final RandomAccessFile input;
  final int frames;

  static Future<ProbeWave> open(File file, int frames) async {
    final input = await file.open();
    try {
      final bytes = await input.read(44);
      if (bytes.length != 44) throw const FormatException('Truncated header');
      final h = ByteData.sublistView(bytes);
      if (ascii.decode(bytes.sublist(0, 4)) != 'RIFF' ||
          ascii.decode(bytes.sublist(8, 16)) != 'WAVEfmt ' ||
          ascii.decode(bytes.sublist(36, 40)) != 'data' ||
          h.getUint32(16, Endian.little) != 16 ||
          h.getUint16(20, Endian.little) != 1 ||
          h.getUint16(22, Endian.little) != 2 ||
          h.getUint32(24, Endian.little) != 48000 ||
          h.getUint32(28, Endian.little) != 192000 ||
          h.getUint16(32, Endian.little) != 4 ||
          h.getUint16(34, Endian.little) != 16 ||
          h.getUint32(40, Endian.little) != frames * 4 ||
          h.getUint32(4, Endian.little) != frames * 4 + 36 ||
          await input.length() != frames * 4 + 44) {
        throw const FormatException('Fixture format/frame mismatch');
      }
      return ProbeWave._(input, frames);
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  Future<Uint8List> packet(int start, int count, SessionBudget budget) async {
    if (start < 0 ||
        count < 1 ||
        count > 9600 ||
        start + count > budget.targetFrames ||
        budget.sourceFrames != frames) {
      throw RangeError('PCM window');
    }
    final result = Uint8List(count * 4);
    var copied = 0;
    while (copied < count) {
      final source = budget.sourceFrame(start + copied);
      final take = min(count - copied, frames - source);
      await input.setPosition(44 + source * 4);
      final bytes = await input.read(take * 4);
      if (bytes.length != take * 4)
        throw const FormatException('Truncated PCM');
      result.setRange(copied * 4, (copied + take) * 4, bytes);
      copied += take;
    }
    final pcm = ByteData.sublistView(result);
    for (var f = max(0, budget.targetFrames - 240001 - start); f < count; f++) {
      final gain = budget.gain(start + f);
      for (var channel = 0; channel < 2; channel++) {
        final offset = f * 4 + channel * 2;
        pcm.setInt16(
          offset,
          (pcm.getInt16(offset, Endian.little) * gain).round(),
          Endian.little,
        );
      }
    }
    return result;
  }

  Future<void> close() => input.close();
}

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'neurotune-duration-',
  );
  try {
    final file = File('${directory.path}/hour.wav');
    await writeFixture(file, 3600 * 48000);
    if (!await legacyAccepts(file, 3600)) {
      throw StateError('Existing WAV reader rejected the integer-hour fixture');
    }
    final wave = await ProbeWave.open(file, 3600 * 48000);
    final budget = SessionBudget(wave.frames);
    final baseline = ProcessInfo.currentRss;
    final peakBefore = peakRss();
    final timer = Stopwatch()..start();
    var largest = 0, packets = 0, sampledPeak = baseline;
    try {
      while (budget.nextPacket > 0) {
        final start = budget.submittedFrames, count = budget.nextPacket;
        final bytes = await wave.packet(start, count, budget);
        final pcm = ByteData.sublistView(bytes);
        for (final f in [0, count - 1]) {
          final expected = (fixtureSample(start + f) * budget.gain(start + f))
              .round();
          if (pcm.getInt16(f * 4, Endian.little) != expected ||
              pcm.getInt16(f * 4 + 2, Endian.little) != -expected) {
            throw StateError('Sample mismatch at ${start + f}');
          }
        }
        largest = max(largest, bytes.length);
        sampledPeak = max(sampledPeak, ProcessInfo.currentRss);
        budget.submit(count);
        if (budget.completed) throw StateError('Completed before final drain');
        budget.confirmPlayed(budget.submittedFrames);
        packets++;
      }
    } finally {
      await wave.close();
    }
    timer.stop();
    if (!budget.completed ||
        largest > 38400 ||
        sampledPeak - baseline > 128 * 1024 * 1024 ||
        peakRss() - peakBefore > 128 * 1024 * 1024) {
      throw StateError('Playback/resource budget exceeded');
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'dart': Platform.version,
        'file_bytes': await file.length(),
        'source_frames': wave.frames,
        'target_frames': budget.targetFrames,
        'confirmed_frames': budget.playedFrames,
        'packets': packets,
        'largest_packet_bytes': largest,
        'elapsed_ms': timer.elapsedMilliseconds,
        'rss_baseline_bytes': baseline,
        'rss_sampled_peak_bytes': sampledPeak,
        'process_peak_before_bytes': peakBefore,
        'process_peak_after_bytes': peakRss(),
        'runtime_max_rss_bytes': ProcessInfo.maxRss,
        'rss_growth_limit_bytes': 128 * 1024 * 1024,
        'completed': budget.completed,
      }),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
