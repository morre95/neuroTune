import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/repository.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.sessions,
    required this.onOpen,
    required this.onBack,
  });

  final List<SavedSession> sessions;
  final ValueChanged<SavedSession> onOpen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historik')),
      body: sessions.isEmpty
          ? const Center(child: Text('Inga sessioner ännu.'))
          : ListView(
              children: [
                for (final session in sessions)
                  ListTile(
                    isThreeLine: true,
                    title: Text(session.manifest.startedAtIso),
                    subtitle: Text(
                      '${session.origin} · ${session.mode} · '
                      '${session.decisions.length} block · '
                      '${_duration(session.manifest.durationSeconds)}\n'
                      '${_outcome(session)}',
                    ),
                    onTap: () => onOpen(session),
                  ),
                TextButton(onPressed: onBack, child: const Text('Tillbaka')),
              ],
            ),
    );
  }
}

String _duration(double seconds) {
  // Round to whole seconds first: truncating the minutes while rounding the
  // remainder renders 1799.7 s as "29m 60s".
  final total = seconds.round();
  final minutes = total ~/ 60;
  final rest = total % 60;
  return minutes == 0 ? '${rest}s' : '${minutes}m ${rest}s';
}

/// A session with no blocks is only meaningful together with why it ended,
/// whether the baseline ever accepted any optics channels, and whether it was
/// still waiting for a stable signal when it was saved.
String _outcome(SavedSession session) {
  final manifest = session.manifest;
  final reason = manifest.stopReason;
  if (reason != null) {
    return 'Avbröts: ${stopReasonLabel(reason)}${_losses(manifest)}';
  }
  if (manifest.selectedChannels.isEmpty) {
    return 'Stoppad innan baslinjen godkändes${_losses(manifest)}';
  }
  if (manifest.endedInPhase == 'waitingStable') {
    return 'Fastnade i väntan på stabil signal${_losses(manifest)}';
  }
  if (session.status == 'completed') return 'Slutförd${_losses(manifest)}';
  return 'Stoppad · kanaler ${manifest.selectedChannels.join(', ')}'
      '${_losses(manifest)}';
}

String _losses(SessionManifest manifest) {
  if (manifest.interruptions == 0) return '';
  final last = manifest.lastInterruptReason;
  final cause = last == null ? '' : ' (${stopReasonLabel(last)})';
  return ' · ${manifest.interruptions} avbrott$cause';
}

String stopReasonLabel(String reason) {
  return switch (reason) {
    'manual' => 'stoppad av dig',
    'audioLost' => 'ljudet försvann',
    'background' => 'appen lämnades',
    'sourceDisconnected' => 'Muse kopplades från',
    'baselineFailed' => 'baslinjen underkändes',
    'attemptLimit' => 'för många avbrutna block',
    _ => reason,
  };
}
