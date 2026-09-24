import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' hide Uint8List;
import 'package:neurotune_core/neurotune_core.dart';
import 'package:path_provider/path_provider.dart';

const _audioMethods = MethodChannel('dev.neurotune/audio');

/// Plays stereo PCM for a session.
abstract class PcmOutput {
  Future<double?> start(int sampleRate);
  Future<void> write(Uint8List pcm16);
  Future<void> stop();
}

class AndroidPcmOutput implements PcmOutput {
  @override
  Future<double?> start(int sampleRate) async {
    await _audioMethods.invokeMethod<void>('start', {'sampleRate': sampleRate});
    final latency = await _audioMethods.invokeMethod<num>('latencyMs');
    return latency?.toDouble();
  }

  @override
  Future<void> write(Uint8List pcm16) =>
      _audioMethods.invokeMethod<void>('write', pcm16);

  @override
  Future<void> stop() => _audioMethods.invokeMethod<void>('stop');
}

class StereoTestPlayer {
  Future<void> start() async {
    final data = await rootBundle.load('assets/audio/stereo_test.wav');
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/stereo_test.wav');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    await _audioMethods.invokeMethod<void>('startTest', {'path': file.path});
  }

  Future<void> stop() => _audioMethods.invokeMethod<void>('stopTest');
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
      (event) =>
          _eeg.add(EegBatch.fromJson(Map<String, dynamic>.from(event as Map))),
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
