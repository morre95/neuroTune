import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'muse_battery_indicator.dart';

class SessionView {
  const SessionView({
    required this.message,
    required this.phase,
    required this.blockLabel,
    required this.actionLabel,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.outerNir,
    required this.nirZ,
    required this.quality,
    required this.canContinue,
    required this.canStop,
  });

  final String message;
  final String phase;
  final String blockLabel;
  final String actionLabel;
  final String theta;
  final String alpha;
  final String beta;
  final String outerNir;
  final String nirZ;
  final String quality;
  final bool canContinue;
  final bool canStop;
}

class SessionPage extends StatelessWidget {
  const SessionPage({
    super.key,
    required this.view,
    required this.onStop,
    required this.onContinue,
    required this.onFinish,
    this.batteryPercent,
  });

  final SessionView view;
  final VoidCallback onStop;
  final VoidCallback onContinue;

  /// Null while the session is being saved.
  final VoidCallback? onFinish;
  final ValueListenable<int?>? batteryPercent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          if (batteryPercent != null)
            MuseBatteryIndicator(batteryPercent: batteryPercent!),
        ],
      ),
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
          Text('Yttre NIR ${view.outerNir} µA'),
          Text('NIR-z ${view.nirZ}'),
          Text('Signalkvalitet ${view.quality}'),
          const SizedBox(height: 16),
          const Text(
            'Belöningen är z-score av rå yttre NIR, 850 nm. Inte syresättning, avslappning, fokus eller behandling.',
          ),
          const Text(
            'Theta, alpha och beta visas som spektrala mått och uppdaterar inte banditen.',
          ),
          const SizedBox(height: 24),
          if (view.canContinue)
            FilledButton(onPressed: onContinue, child: const Text('Fortsätt'))
          else if (view.canStop)
            OutlinedButton(onPressed: onStop, child: const Text('Stoppa')),
          TextButton(
            onPressed: onFinish,
            child: Text(onFinish == null ? 'Sparar…' : 'Avsluta session'),
          ),
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
