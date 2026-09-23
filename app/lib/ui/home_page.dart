import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.experimentVersion,
    required this.policyVersion,
    required this.hardwareApproved,
    required this.offline,
    required this.eyeState,
    required this.mode,
    required this.onEyeState,
    required this.onMode,
    required this.onStartSimulator,
    required this.onMuse,
    required this.onHistory,
    required this.onLogout,
  });

  final String experimentVersion;
  final String policyVersion;
  final bool hardwareApproved;
  final bool offline;
  final EyeState eyeState;
  final SessionMode mode;
  final ValueChanged<EyeState> onEyeState;
  final ValueChanged<SessionMode> onMode;
  final VoidCallback onStartSimulator;
  final VoidCallback onMuse;
  final VoidCallback onHistory;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('neuroTune'),
        actions: [TextButton(onPressed: onLogout, child: const Text('Logga ut'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(offline ? 'Offline. Cachad konfiguration och policy används.' : 'Ansluten till servern.'),
          Text('Experiment $experimentVersion'),
          Text('Policy $policyVersion'),
          const SizedBox(height: 16),
          const Text('Ögonläge under hela sessionen'),
          SegmentedButton<EyeState>(
            segments: const [
              ButtonSegment(value: EyeState.open, label: Text('Ögon öppna')),
              ButtonSegment(value: EyeState.closed, label: Text('Ögon stängda')),
            ],
            selected: {eyeState},
            onSelectionChanged: (value) => onEyeState(value.single),
          ),
          const SizedBox(height: 16),
          const Text('Läge'),
          SegmentedButton<SessionMode>(
            segments: const [
              ButtonSegment(value: SessionMode.personal, label: Text('Personlig')),
              ButtonSegment(value: SessionMode.comparison, label: Text('Jämförelse')),
            ],
            selected: {mode},
            onSelectionChanged: (value) => onMode(value.single),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onStartSimulator, child: const Text('Simulator')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onMuse, child: const Text('Muse')),
          if (!hardwareApproved)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Hårdvaruläget är inte verifierat. Fysisk Muse S Athena och SDK krävs.'),
            ),
          const SizedBox(height: 16),
          TextButton(onPressed: onHistory, child: const Text('Sessionshistorik')),
        ],
      ),
    );
  }
}
