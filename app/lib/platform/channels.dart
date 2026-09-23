import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' hide Uint8List;
import 'package:neurotune_core/neurotune_core.dart';

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
  Future<void> write(Uint8List pcm16) =>
      _methods.invokeMethod<void>('write', pcm16);

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Stream<bool> get stereoConnected =>
      _events.receiveBroadcastStream().map((event) => event == true);
}

class MuseChannel {
  static const _methods = MethodChannel('dev.neurotune/muse');
  static const _eegEvents = EventChannel('dev.neurotune/muse_eeg');
  static const _opticsEvents = EventChannel('dev.neurotune/muse_optics');

  final _eeg = StreamController<EegBatch>.broadcast();
  final _optics = StreamController<OpticsBatch>.broadcast();
  final _lost = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _eegPlatform;
  StreamSubscription<dynamic>? _opticsPlatform;

  Stream<EegBatch> get eeg => _eeg.stream;
  Stream<OpticsBatch> get optics => _optics.stream;
  Stream<void> get disconnected => _lost.stream;

  Future<void> start() async {
    _eegPlatform ??= _eegEvents.receiveBroadcastStream().listen(
      (event) => _eeg.add(
        EegBatch.fromJson(Map<String, dynamic>.from(event as Map)),
      ),
      onError: (_) => _lost.add(null),
    );
    _opticsPlatform ??= _opticsEvents.receiveBroadcastStream().listen(
      (event) => _optics.add(
        OpticsBatch.fromJson(Map<String, dynamic>.from(event as Map)),
      ),
      onError: (_) => _lost.add(null),
    );
    await _methods.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _methods.invokeMethod<void>('stop');
    await _eegPlatform?.cancel();
    await _opticsPlatform?.cancel();
    _eegPlatform = null;
    _opticsPlatform = null;
  }
}
