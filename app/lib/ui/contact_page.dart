import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'muse_battery_indicator.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({
    super.key,
    required this.batch,
    required this.onStart,
    this.startLabel = 'Starta baslinje',
    this.requireSignal = true,
    required this.onBack,
    required this.onStereoTest,
    required this.stereoTestPlaying,
    required this.stereoTestBusy,
    required this.startingSession,
    required this.openingSession,
    this.note,
    this.error,
    this.batteryPercent,
  });

  final EegBatch? batch;
  final VoidCallback onStart;
  final String startLabel;
  final bool requireSignal;
  final VoidCallback onBack;
  final VoidCallback onStereoTest;
  final bool stereoTestPlaying;
  final bool stereoTestBusy;

  /// Locks starting while a session starts, so it cannot start twice.
  final bool startingSession;

  /// Locks leaving once the session holds the output and the headband.
  /// Before that, leaving cancels the start.
  final bool openingSession;
  final String? note;
  final String? error;
  final ValueListenable<int?>? batteryPercent;

  @override
  Widget build(BuildContext context) {
    final names = batch?.channelNames ?? simulatorChannels;
    final locked = stereoTestBusy || startingSession;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontakt'),
        actions: [
          if (batteryPercent != null)
            MuseBatteryIndicator(batteryPercent: batteryPercent!),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            requireSignal
                ? 'Kontrollera att signalen är stabil innan baslinjen. Samma ögonläge gäller hela sessionen.'
                : 'Samma ögonläge gäller hela meditationen. Dålig eller saknad EEG stoppar inte ljudet.',
          ),
          if (note != null) ...[const SizedBox(height: 12), Text(note!)],
          if (error != null) ...[const SizedBox(height: 12), Text(error!)],
          const SizedBox(height: 16),
          for (var index = 0; index < names.length; index++)
            ListTile(
              title: Text(names[index]),
              subtitle: Text(_contactLabel(batch, index)),
            ),
          const SizedBox(height: 16),
          const Text('Testa att vänster och höger kanal hörs i dina hörlurar.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: locked ? null : onStereoTest,
            child: Text(
              stereoTestPlaying ? 'Stoppa hörlurstest' : 'Testa hörlurar',
            ),
          ),
          if (stereoTestPlaying)
            const Text('Testljudet upprepas tills du stoppar det.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                (requireSignal && batch == null) || locked || stereoTestPlaying
                ? null
                : onStart,
            child: Text(startingSession ? 'Startar…' : startLabel),
          ),
          TextButton(
            onPressed: stereoTestBusy || openingSession ? null : onBack,
            child: const Text('Tillbaka'),
          ),
        ],
      ),
    );
  }

  String _contactLabel(EegBatch? batch, int channel) {
    if (batch == null || batch.contact.isEmpty) return 'Väntar på signal';
    final code = batch.contact.last[channel];
    return switch (code) {
      1 => 'Bra kontakt',
      2 => 'Godkänd kontakt',
      _ => 'Dålig kontakt',
    };
  }
}
