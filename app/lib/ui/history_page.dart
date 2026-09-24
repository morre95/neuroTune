import 'package:flutter/material.dart';

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
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).round();
  return minutes == 0 ? '${rest}s' : '${minutes}m ${rest}s';
}

/// A session with no blocks is only meaningful together with why it ended and
/// whether the baseline ever accepted any optics channels.
String _outcome(SavedSession session) {
  final reason = session.manifest.stopReason;
  if (reason != null) return 'Avbröts: ${stopReasonLabel(reason)}';
  if (session.status == 'completed') return 'Slutförd';
  return session.manifest.selectedChannels.isEmpty
      ? 'Stoppad innan baslinjen godkändes'
      : 'Stoppad · kanaler ${session.manifest.selectedChannels.join(', ')}';
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
