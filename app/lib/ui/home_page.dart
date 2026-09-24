import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

String modeDescription(SessionMode mode) => switch (mode) {
  SessionMode.personal =>
    'Personlig tränar din policy. Efter ett varv med alla fem stimuli väljer '
        'banditen oftare det som gett bäst respons, och varje block uppdaterar '
        'modellen.',
  SessionMode.comparison =>
    'Jämförelse mäter utan att träna. Alla fem stimuli spelas lika många '
        'gånger i slumpad ordning och resultatet sparas, men policyn lämnas '
        'oförändrad.',
};

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
    required this.connectingMuse,
    required this.onHistory,
    required this.onLogout,
    this.message,
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
  final bool connectingMuse;
  final VoidCallback onHistory;
  final VoidCallback onLogout;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('neuroTune'),
        actions: [
          TextButton(onPressed: onLogout, child: const Text('Logga ut')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            offline
                ? 'Offline. Cachad konfiguration och policy används.'
                : 'Ansluten till servern.',
          ),
          if (message != null) Text(message!),
          Text('Experiment $experimentVersion'),
          Text('Policy $policyVersion'),
          const SizedBox(height: 16),
          const Text('Ögonläge under hela sessionen'),
          SegmentedButton<EyeState>(
            segments: const [
              ButtonSegment(value: EyeState.open, label: Text('Ögon öppna')),
              ButtonSegment(
                value: EyeState.closed,
                label: Text('Ögon stängda'),
              ),
            ],
            selected: {eyeState},
            onSelectionChanged: (value) => onEyeState(value.single),
          ),
          const SizedBox(height: 16),
          const Text('Läge'),
          SegmentedButton<SessionMode>(
            segments: [
              ButtonSegment(
                value: SessionMode.personal,
                label: const Text('Personlig'),
                tooltip: modeDescription(SessionMode.personal),
              ),
              ButtonSegment(
                value: SessionMode.comparison,
                label: const Text('Jämförelse'),
                tooltip: modeDescription(SessionMode.comparison),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (value) => onMode(value.single),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(modeDescription(mode)),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onStartSimulator,
            child: const Text('Simulator'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: connectingMuse ? null : onMuse,
            child: Text(connectingMuse ? 'Ansluter…' : 'Muse'),
          ),
          if (!hardwareApproved)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Hårdvaruläget är inte verifierat. Fysisk Muse S Athena och SDK krävs.',
              ),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onHistory,
            child: const Text('Sessionshistorik'),
          ),
        ],
      ),
    );
  }
}
