import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' hide Uint8List;
import 'package:flutter/foundation.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:path_provider/path_provider.dart';

const _audioMethods = MethodChannel('dev.neurotune/audio');
const _sessionMethods = MethodChannel('dev.neurotune/session');

/// Plays stereo PCM for a session.
abstract class PcmOutput {
  Future<double?> start(int sampleRate);

  /// Completes when the output accepts the packet, providing backpressure.
  /// Only one write may be in flight; stop must release a pending write.
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

/// Holds a foreground service open for the duration of a session so Android
/// does not throttle playback and the Muse stream once the app leaves the
/// foreground or the screen turns off.
abstract class SessionKeepAlive {
  Future<void> start();
  Future<void> stop();
}

class AndroidSessionKeepAlive implements SessionKeepAlive {
  @override
  Future<void> start() => _sessionMethods.invokeMethod<void>('start');

  @override
  Future<void> stop() => _sessionMethods.invokeMethod<void>('stop');
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
  static const _batteryEvents = EventChannel('dev.neurotune/muse_battery');
  static const _diagnosticEvents = EventChannel(
    'dev.neurotune/muse_diagnostics',
  );

  final _batteryPercent = ValueNotifier<int?>(null);
  ValueListenable<int?> get batteryPercent => _batteryPercent;

  final _eeg = StreamController<EegBatch>.broadcast();
  final _optics = StreamController<OpticsBatch>.broadcast();
  final _lost = StreamController<void>.broadcast();
  final _diagnostics = StreamController<SessionDiagnostic>.broadcast();
  StreamSubscription<dynamic>? _diagnosticPlatform;
  StreamSubscription<dynamic>? _eegPlatform;
  StreamSubscription<dynamic>? _opticsPlatform;
  StreamSubscription<dynamic>? _batteryPlatform;

  Stream<EegBatch> get eeg => _eeg.stream;
  Stream<OpticsBatch> get optics => _optics.stream;
  Stream<void> get disconnected => _lost.stream;
  Stream<SessionDiagnostic> get diagnostics => _diagnostics.stream;

  Future<void> start() async {
    _diagnosticPlatform ??= _diagnosticEvents.receiveBroadcastStream().listen(
      (event) => _diagnostics.add(
        SessionDiagnostic.fromJson(Map<String, dynamic>.from(event as Map)),
      ),
      onError: (_) {},
    );
    _batteryPercent.value = null;
    _batteryPlatform ??= _batteryEvents.receiveBroadcastStream().listen((
      event,
    ) {
      _batteryPercent.value =
          event is num && event.isFinite && event >= 0 && event <= 100
          ? event.round()
          : null;
    }, onError: (_) => _batteryPercent.value = null);
    _eegPlatform ??= _eegEvents.receiveBroadcastStream().listen(
      (event) =>
          _eeg.add(EegBatch.fromJson(Map<String, dynamic>.from(event as Map))),
      onError: (_) => _disconnected(),
    );
    _opticsPlatform ??= _opticsEvents.receiveBroadcastStream().listen(
      (event) => _optics.add(
        OpticsBatch.fromJson(Map<String, dynamic>.from(event as Map)),
      ),
      onError: (_) => _disconnected(),
    );
    try {
      await _methods.invokeMethod<void>('start');
    } catch (_) {
      _batteryPercent.value = null;
      rethrow;
    }
  }

  void _disconnected() {
    _batteryPercent.value = null;
    _lost.add(null);
  }

  Future<void> stop() async {
    _batteryPercent.value = null;
    await _methods.invokeMethod<void>('stop');
    await _eegPlatform?.cancel();
    await _opticsPlatform?.cancel();
    await _batteryPlatform?.cancel();
    await _diagnosticPlatform?.cancel();
    _eegPlatform = null;
    _opticsPlatform = null;
    _batteryPlatform = null;
    _diagnosticPlatform = null;
  }
}
