import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:neurotune_core/neurotune_core.dart';
import '../data/canonical_wave.dart';

/// One bounded request in flight. All WAV reads, conversion and mixing take
/// place in a persistent isolate. Absolute played-frame checkpoints allow an
/// interruption to discard unplayed packets without advancing the background.
class MeditationRenderer {
  MeditationRenderer._(this._commands, this._responses, this._isolate);
  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  Completer<Object?>? _pending;
  bool _closed = false;
  static const sampleRate = 48000;
  static const durationFrames = 600 * sampleRate;
  static const rampFrames = 7200;
  static const overlapFrames = 24000;
  static const maxPacketFrames = 9600;

  static Future<MeditationRenderer> open(
    File file,
    AudioProfileVersion profile,
    StimulusAction action,
  ) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    MeditationRenderer? renderer;
    final isolate = await Isolate.spawn(_worker, (
      responses.sendPort,
      file.path,
      profile.toJson(),
      action.id,
    ));
    responses.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (!ready.isCompleted) {
        ready.completeError(StateError('$message'));
      } else {
        final pending = renderer?._pending;
        renderer?._pending = null;
        if (message is String) {
          pending?.completeError(StateError(message));
        } else {
          pending?.complete(message);
        }
      }
    });
    try {
      renderer = MeditationRenderer._(await ready.future, responses, isolate);
      return renderer;
    } catch (_) {
      responses.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<Uint8List> render(
    int startFrame,
    int frames, {
    bool stopping = false,
  }) async {
    if (_closed) throw StateError('Renderer closed');
    if (_pending != null) throw StateError('Concurrent PCM render');
    if (startFrame < 0 ||
        frames < 1 ||
        frames > maxPacketFrames ||
        startFrame + frames > durationFrames) {
      throw RangeError('PCM packet bounds');
    }
    final pending = _pending = Completer<Object?>();
    _commands.send((startFrame, frames, stopping));
    try {
      return (await pending.future.timeout(const Duration(seconds: 2))
              as TransferableTypedData)
          .materialize()
          .asUint8List();
    } on TimeoutException {
      _closed = true;
      _pending = null;
      _responses.close();
      _isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _pending?.future.timeout(const Duration(seconds: 2));
      final pending = _pending = Completer<Object?>();
      _commands.send(null);
      await pending.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // A failed worker cannot retain session resources indefinitely.
    } finally {
      _responses.close();
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  static Future<void> _worker(
    (SendPort, String, Map<String, dynamic>, String) init,
  ) async {
    final (reply, path, json, actionId) = init;
    RandomAccessFile? input;
    final commands = ReceivePort();
    try {
      final profile = AudioProfileVersion.fromJson(json);
      final file = File(path);
      final wave = await CanonicalWave.inspect(
        file,
        seconds: profile.durationSeconds,
      );
      input = await file.open();
      await input.setPosition(wave.dataOffset);
      final opening = ByteData.sublistView(await input.read(overlapFrames * 4));
      final tones = StimulusAction.byId(actionId).tones(profile.carrierHz);
      var cacheStart = -1;
      var cacheFrames = 0;
      var cache = ByteData(0);
      int positionAt(int frame) => frame < wave.frameCount
          ? frame
          : overlapFrames +
                (frame - wave.frameCount) % (wave.frameCount - overlapFrames);
      Future<void> load(int position) async {
        cacheStart = position ~/ maxPacketFrames * maxPacketFrames;
        cacheFrames = min(maxPacketFrames, wave.frameCount - cacheStart);
        await input!.setPosition(wave.dataOffset + cacheStart * 4);
        final bytes = await input.read(cacheFrames * 4);
        if (bytes.length != cacheFrames * 4) {
          throw const FormatException('Truncated PCM');
        }
        cache = ByteData.sublistView(bytes);
      }

      double background(int frame, int channel) {
        if (!profile.loop && frame >= wave.frameCount) return 0;
        final position = positionAt(frame);
        final value =
            cache.getInt16(
              (position - cacheStart) * 4 + channel * 2,
              Endian.little,
            ) /
            32768;
        if (profile.loop && position >= wave.frameCount - overlapFrames) {
          final index = position - (wave.frameCount - overlapFrames);
          final fraction = index / overlapFrames;
          return value * (1 - fraction) +
              opening.getInt16(index * 4 + channel * 2, Endian.little) /
                  32768 *
                  fraction;
        }
        return value;
      }

      reply.send(commands.sendPort);
      await for (final command in commands) {
        if (command == null) {
          await input?.close();
          input = null;
          reply.send(true);
          break;
        }
        try {
          final (start, count, stopping) = command as (int, int, bool);
          final bytes = Uint8List(count * 4);
          final pcm = ByteData.sublistView(bytes);
          for (var i = 0; i < count; i++) {
            final frame = start + i;
            final position = positionAt(frame);
            if ((profile.loop || frame < wave.frameCount) &&
                (position < cacheStart ||
                    position >= cacheStart + cacheFrames)) {
              await load(position);
            }
            final gain =
                min(
                  1.0,
                  min(
                    frame / rampFrames,
                    (durationFrames - 1 - frame) / rampFrames,
                  ),
                ) *
                (stopping ? (count == 1 ? 0 : max(0, 1 - i / (count - 1))) : 1);
            for (var channel = 0; channel < 2; channel++) {
              final hz = channel == 0 ? tones.$1 : tones.$2;
              final tone = sin(2 * pi * hz * frame / sampleRate);
              final mixed =
                  (background(frame, channel) * profile.backgroundGain +
                      tone * profile.toneGain) *
                  gain;
              pcm.setInt16(
                i * 4 + channel * 2,
                (mixed * 32767).round().clamp(-32768, 32767),
                Endian.little,
              );
            }
          }
          reply.send(TransferableTypedData.fromList([bytes]));
        } catch (error) {
          reply.send('$error');
        }
      }
    } catch (error) {
      reply.send('$error');
    } finally {
      await input?.close();
      commands.close();
    }
  }
}
