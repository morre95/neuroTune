import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/repository.dart';
import 'session_page.dart';
import 'session_diagnostics.dart';

class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key, required this.session, required this.onBack});

  final SavedSession session;
  final VoidCallback onBack;

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final frames = widget.session.frames;
    final frame = frames.isEmpty
        ? null
        : frames[_index.clamp(0, frames.length - 1)];
    final decision = _decisionAt(frame?.timeSeconds ?? 0);
    final valid = frame == null
        ? 0
        : frame.channels
              .where((channel) => channel.valid && !frame.rejected)
              .length;
    final total = frame?.channels.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Uppspelning')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Tid ${frame?.timeSeconds.toStringAsFixed(0) ?? '-'} s'),
          Text(
            'Åtgärd: ${widget.session.manifest.meditation == null ? actionLabel(decision?.action) : meditationActionLabel(widget.session.manifest)}',
          ),
          Text('Theta ${_mean(frame, (channel) => channel.relativeTheta)}'),
          Text('Alpha ${_mean(frame, (channel) => channel.relativeAlpha)}'),
          Text('Beta ${_mean(frame, (channel) => channel.relativeBeta)}'),
          if (widget.session.manifest.meditation == null)
            Text('Yttre NIR ${_outerNir(frame)} µA'),
          Text('Signalkvalitet $valid/$total kanaler'),
          if (frame != null)
            for (final channel in frame.channels)
              Text(
                '${channel.name}: ${channel.valid && !frame.rejected ? 'godkänd' : {...channel.reasons, ...frame.reasons}.map(qualityReasonLabel).join(', ')}',
              ),
          if (frame != null && frame.optics.isNotEmpty)
            ExpansionTile(
              title: const Text('Optiska kanaler'),
              children: [
                for (final channel in frame.optics)
                  ListTile(
                    title: Text(
                      '${channel.name}: ${channel.intensity.toStringAsFixed(3)} µA',
                    ),
                    subtitle: Text(
                      channel.valid
                          ? 'Godkänd'
                          : channel.reasons.map(qualityReasonLabel).join(', '),
                    ),
                  ),
              ],
            ),
          if (decision?.reward != null)
            Text('Belöning ${decision!.reward!.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: frame == null || _index >= frames.length - 1
                ? null
                : () => setState(() => _index += 1),
            child: const Text('Nästa sekund'),
          ),
          TextButton(onPressed: widget.onBack, child: const Text('Tillbaka')),
          const SizedBox(height: 24),
          SessionDiagnostics(manifest: widget.session.manifest, frames: frames),
        ],
      ),
    );
  }

  DecisionEvent? _decisionAt(double time) {
    DecisionEvent? current;
    for (final decision in widget.session.decisions) {
      if (decision.startedAtSeconds <= time) current = decision;
    }
    return current;
  }

  String _outerNir(FeatureFrame? frame) {
    final selected = widget.session.manifest.selectedChannels;
    final names = selected.isEmpty ? const ['OPTICS3', 'OPTICS4'] : selected;
    final valid =
        frame?.optics
            .where((item) => item.valid && names.contains(item.name))
            .toList() ??
        [];
    if (valid.isEmpty) return '-';
    final value =
        valid.map((item) => item.intensity).reduce((a, b) => a + b) /
        valid.length;
    return value.toStringAsFixed(3);
  }

  String _mean(
    FeatureFrame? frame,
    double Function(ChannelFeature channel) read,
  ) {
    if (frame == null || frame.channels.isEmpty) return '-';
    final value =
        frame.channels.map(read).reduce((a, b) => a + b) /
        frame.channels.length;
    return value.toStringAsFixed(3);
  }
}
