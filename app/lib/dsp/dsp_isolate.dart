import 'dart:async';
import 'dart:isolate';

import 'package:neurotune_core/neurotune_core.dart';

class DspHost {
  DspHost._(this._isolate, this._send, this.frames);

  final Isolate _isolate;
  final SendPort _send;
  final Stream<FeatureFrame> frames;

  static Future<DspHost> start({
    required ExperimentConfig config,
    required double sampleRateHz,
    required List<String> channelNames,
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_dspMain, ready.sendPort);
    final send = await ready.first as SendPort;
    final incoming = ReceivePort();
    send.send({
      'cmd': 'init',
      'config': config.toJson(),
      'fs': sampleRateHz,
      'channels': channelNames,
      'out': incoming.sendPort,
    });
    return DspHost._(isolate, send, incoming.cast<FeatureFrame>());
  }

  void addBatch(EegBatch batch) {
    _send.send({'cmd': 'batch', 'batch': batch.toJson()});
  }

  void close() {
    _send.send({'cmd': 'stop'});
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _dspMain(SendPort host) {
  final inbox = ReceivePort();
  host.send(inbox.sendPort);
  DspPipeline? pipeline;
  SendPort? out;
  inbox.listen((message) {
    final map = Map<Object?, Object?>.from(message as Map);
    switch (map['cmd']) {
      case 'init':
        pipeline = DspPipeline(
          config: ExperimentConfig.fromJson(Map<String, dynamic>.from(map['config']! as Map)),
          sampleRateHz: (map['fs']! as num).toDouble(),
          channelNames: (map['channels']! as List).map((name) => '$name').toList(),
        );
        out = map['out']! as SendPort;
      case 'batch':
        final batch = EegBatch.fromJson(Map<String, dynamic>.from(map['batch']! as Map));
        for (final frame in pipeline!.addBatch(batch)) {
          out!.send(frame);
        }
      case 'stop':
        inbox.close();
    }
  });
}
