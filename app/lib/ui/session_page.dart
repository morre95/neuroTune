import 'package:flutter/material.dart';

class SessionView {
  const SessionView({
    required this.message,
    required this.phase,
    required this.blockLabel,
    required this.actionLabel,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.quality,
    required this.canContinue,
  });

  final String message;
  final String phase;
  final String blockLabel;
  final String actionLabel;
  final String theta;
  final String alpha;
  final String beta;
  final String quality;
  final bool canContinue;
}

class SessionPage extends StatelessWidget {
  const SessionPage({super.key, required this.view, required this.onStop, required this.onContinue, required this.onFinish});

  final SessionView view;
  final VoidCallback onStop;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(view.phase, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(view.message),
          const SizedBox(height: 16),
          Text('Block ${view.blockLabel}'),
          Text('Åtgärd: ${view.actionLabel}'),
          const SizedBox(height: 16),
          Text('Theta ${view.theta}'),
          Text('Alpha ${view.alpha}'),
          Text('Beta ${view.beta}'),
          Text('Signalkvalitet ${view.quality}'),
          const SizedBox(height: 16),
          const Text('Spektrala mått. Inte ett mått på avslappning, fokus eller behandling.'),
          const SizedBox(height: 24),
          if (view.canContinue) FilledButton(onPressed: onContinue, child: const Text('Fortsätt')),
          OutlinedButton(onPressed: onStop, child: const Text('Stoppa')),
          TextButton(onPressed: onFinish, child: const Text('Avsluta session')),
        ],
      ),
    );
  }
}

String actionLabel(String? action) {
  return switch (action) {
    'binaural_6' => 'Binauralt 6 Hz',
    'binaural_8' => 'Binauralt 8 Hz',
    'binaural_10' => 'Binauralt 10 Hz',
    'binaural_12' => 'Binauralt 12 Hz',
    'control' => 'Kontroll',
    _ => 'Tystnad',
  };
}
