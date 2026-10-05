import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

String qualityReasonLabel(String reason) => switch (reason) {
  'contact' => 'dålig kontakt',
  'saturation' => 'mättnad/ogiltigt värde',
  'flatline' => 'platt signal',
  'jump' => 'signalhopp',
  'motion' => 'rörelse',
  'gap' => 'datagap',
  'missing_samples' => 'saknade EEG-värden',
  'missing_motion' => 'saknade rörelsevärden',
  _ => reason,
};

class SessionDiagnostics extends StatelessWidget {
  const SessionDiagnostics({
    super.key,
    required this.manifest,
    required this.frames,
  });
  final SessionManifest manifest;
  final List<FeatureFrame> frames;

  @override
  Widget build(BuildContext context) {
    final events = manifest.diagnostics;
    final battery = events.where((event) => event.type == 'battery').toList();
    final artifacts = events
        .where((event) => event.type == 'artifact')
        .toList();
    final gaps = events.where((event) => event.type == 'data_gap').toList();
    final invalid = events
        .where((event) => event.type == 'invalid_samples')
        .toList();
    var disconnectedSeconds = 0.0;
    double? disconnectedAt;
    for (final event in events) {
      if (event.type == 'connection' &&
          event.values['state'] == 'disconnected') {
        disconnectedAt ??= event.timeSeconds;
      } else if ((event.type == 'connection' &&
              event.values['state'] == 'connected') ||
          event.type == 'recording_end') {
        if (disconnectedAt != null) {
          disconnectedSeconds += event.timeSeconds - disconnectedAt;
          disconnectedAt = null;
        }
      }
    }
    final missingSlots = <String, int>{};
    final invalidValues = <String, int>{};
    for (final event in gaps) {
      final stream = event.values['stream'] as String;
      missingSlots.update(
        stream,
        (count) =>
            count + (event.values['missing_sample_slots'] as num).toInt(),
        ifAbsent: () => (event.values['missing_sample_slots'] as num).toInt(),
      );
    }
    for (final event in invalid) {
      final counts = Map<String, dynamic>.from(
        event.values['channel_counts'] as Map,
      );
      for (final entry in counts.entries) {
        final key = '${event.values['stream']} ${entry.key}';
        invalidValues.update(
          key,
          (count) => count + (entry.value as num).toInt(),
          ifAbsent: () => (entry.value as num).toInt(),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signalkvalitet per kanal',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Andel godkända analysfönster. Perioder utan analys ingår inte.',
        ),
        for (final channel in summarizeChannelQuality(frames))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${channel.name}: ${(channel.validFraction * 100).toStringAsFixed(0)} % godkända',
            ),
            subtitle: Text(
              channel.reasons.isEmpty
                  ? '${channel.frames} analysfönster, inga registrerade fel'
                  : channel.reasons.entries
                        .map(
                          (entry) =>
                              '${qualityReasonLabel(entry.key)}: ${entry.value} fönster',
                        )
                        .join(', '),
            ),
          ),
        if (manifest.dataOrigin == 'muse') ...[
          const SizedBox(height: 16),
          Text(
            'Muse-diagnostik',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (manifest.diagnosticsVersion == 0)
            const Text('Utökad diagnostik saknas i denna äldre inspelning.')
          else ...[
            Text(
              battery.isEmpty
                  ? 'Batteri: inga värden mottagna'
                  : 'Batteri: ${battery.first.values['percent']} % → ${battery.last.values['percent']} %',
            ),
            Text(
              artifacts.isEmpty
                  ? 'Störningsmarkörer: inga paket mottagna från Muse'
                  : 'Blinkmarkeringar: ${artifacts.where((event) => event.values['blink'] == true).length}, käkmarkeringar: ${artifacts.where((event) => event.values['jaw_clench'] == true).length}',
            ),
            if (artifacts.isNotEmpty)
              Text(
                'Band av huvudet: ${artifacts.where((event) => event.values['headband_on'] == false).length} markeringar',
              ),
            Text(
              'Tid frånkopplad: ${disconnectedSeconds.toStringAsFixed(1)} s',
            ),
            Text('Registrerade datagap: ${gaps.length}'),
            for (final entry in missingSlots.entries)
              Text('${entry.key}: ${entry.value} saknade provtillfällen'),
            for (final entry in invalidValues.entries)
              Text('${entry.key}: ${entry.value} ogiltiga värden'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Diagnostik över tid'),
              children: [
                for (final event in events)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${event.timeSeconds.toStringAsFixed(1)} s · ${_eventLabel(event.type)}',
                    ),
                    subtitle: Text(_eventDetails(event)),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  String _eventLabel(String type) => switch (type) {
    'battery' => 'Batteri',
    'artifact' => 'Störningsmarkör',
    'connection' => 'Anslutning',
    'data_gap' => 'Datagap',
    'invalid_samples' => 'Ogiltiga mätvärden',
    'invalid_motion' => 'Ogiltiga rörelsevärden',
    'recording_end' => 'Inspelning avslutad',
    _ => type,
  };

  String _eventDetails(SessionDiagnostic event) => switch (event.type) {
    'battery' => '${event.values['percent']} %',
    'artifact' => [
      if (event.values['blink'] == true) 'Blinkning',
      if (event.values['jaw_clench'] == true) 'Käkspänning',
      if (event.values['headband_on'] == false) 'Band av huvudet',
      if (event.values['headband_on'] == true) 'Band på huvudet',
    ].join(', '),
    'connection' =>
      event.values['state'] == 'connected' ? 'Ansluten' : 'Frånkopplad',
    'data_gap' =>
      '${event.values['stream']}: ${(event.values['duration_seconds'] as num).toStringAsFixed(3)} s, ${event.values['missing_sample_slots']} provtillfällen',
    'invalid_samples' =>
      '${event.values['stream']}: ${event.values['channel_counts']}',
    'invalid_motion' =>
      '${event.values['stream']}: ${event.values['resampled_rows']} rader',
    'recording_end' => 'Sessionen sparas',
    _ => '',
  };
}
