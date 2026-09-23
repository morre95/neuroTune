import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({
    super.key,
    required this.batch,
    required this.onStart,
    required this.onBack,
  });

  final EegBatch? batch;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final names = batch?.channelNames ?? simulatorChannels;
    return Scaffold(
      appBar: AppBar(title: const Text('Kontakt')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Kontrollera att signalen är stabil innan baslinjen. Samma ögonläge gäller hela sessionen.',
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < names.length; index++)
            ListTile(
              title: Text(names[index]),
              subtitle: Text(_contactLabel(batch, index)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: batch == null ? null : onStart,
            child: const Text('Starta baslinje'),
          ),
          TextButton(onPressed: onBack, child: const Text('Tillbaka')),
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
