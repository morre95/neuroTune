import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Position of canonical stereo PCM frames; permits harmless RIFF metadata chunks.
class CanonicalWave {
  const CanonicalWave({required this.dataOffset, required this.frameCount});
  final int dataOffset;
  final int frameCount;
  static Future<CanonicalWave> verify(
    File file,
    String checksum,
    int seconds,
  ) => Isolate.run(() async {
    if ((await sha256.bind(file.openRead()).first).toString() != checksum) {
      throw const FormatException('Audio checksum mismatch');
    }
    return inspect(file, seconds: seconds);
  });
  static Future<CanonicalWave> inspect(
    File file, {
    required int seconds,
  }) async {
    final length = await file.length();
    if (length < 44 || length > seconds * 192000 + 1048576) {
      throw const FormatException('Invalid WAV length');
    }
    final input = await file.open();
    try {
      Future<ByteData> read(int count) async {
        final bytes = await input.read(count);
        if (bytes.length != count) throw const FormatException('Truncated WAV');
        return ByteData.sublistView(bytes);
      }

      String tag(ByteData b, int offset) =>
          ascii.decode(b.buffer.asUint8List(b.offsetInBytes + offset, 4));
      final header = await read(12);
      if (tag(header, 0) != 'RIFF' ||
          tag(header, 8) != 'WAVE' ||
          header.getUint32(4, Endian.little) + 8 != length) {
        throw const FormatException('Invalid WAV container');
      }
      var formatted = false;
      CanonicalWave? result;
      while (await input.position() < length) {
        final chunk = await read(8);
        final size = chunk.getUint32(4, Endian.little);
        final start = await input.position();
        if (start + size + (size % 2) > length) {
          throw const FormatException('Invalid WAV chunk');
        }
        switch (tag(chunk, 0)) {
          case 'fmt ':
            if (formatted || size < 16 || size > 4096) {
              throw const FormatException('Invalid WAV format');
            }
            final fmt = await read(16);
            if (fmt.getUint16(0, Endian.little) != 1 ||
                fmt.getUint16(2, Endian.little) != 2 ||
                fmt.getUint32(4, Endian.little) != 48000 ||
                fmt.getUint32(8, Endian.little) != 192000 ||
                fmt.getUint16(12, Endian.little) != 4 ||
                fmt.getUint16(14, Endian.little) != 16) {
              throw const FormatException('Expected stereo 48 kHz PCM16');
            }
            formatted = true;
          case 'data':
            if (!formatted || result != null || size != seconds * 192000) {
              throw const FormatException('Invalid PCM duration');
            }
            result = CanonicalWave(dataOffset: start, frameCount: size ~/ 4);
        }
        await input.setPosition(start + size + (size % 2));
      }
      if (result == null) throw const FormatException('Missing PCM');
      return result;
    } finally {
      await input.close();
    }
  }
}
