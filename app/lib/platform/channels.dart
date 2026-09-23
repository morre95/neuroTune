import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Plays stereo PCM and reports whether a headphone output is connected.
abstract class PcmOutput {
  Future<bool> hasStereoOutput();
  Future<double?> start(int sampleRate);
  Future<void> write(Uint8List pcm16);
  Future<void> stop();
  Stream<bool> get stereoConnected;
}

class AndroidPcmOutput implements PcmOutput {
  static const _methods = MethodChannel('dev.neurotune/audio');
  static const _events = EventChannel('dev.neurotune/audio_status');

  @override
  Future<bool> hasStereoOutput() async {
    final connected = await _methods.invokeMethod<bool>('hasStereoOutput');
    return connected ?? false;
  }

  @override
  Future<double?> start(int sampleRate) async {
    await _methods.invokeMethod<void>('start', {'sampleRate': sampleRate});
    final latency = await _methods.invokeMethod<num>('latencyMs');
    return latency?.toDouble();
  }

  @override
  Future<void> write(Uint8List pcm16) => _methods.invokeMethod<void>('write', pcm16);

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Stream<bool> get stereoConnected => _events.receiveBroadcastStream().map((event) => event == true);
}

class MuseChannel {
  static const _methods = MethodChannel('dev.neurotune/muse');

  Future<void> start() => _methods.invokeMethod<void>('start');

  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
