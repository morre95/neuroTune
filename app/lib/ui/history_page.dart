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
                    title: Text(session.manifest.startedAtIso),
                    subtitle: Text(
                      '${session.origin} · ${session.mode} · ${session.decisions.length} block',
                    ),
                    onTap: () => onOpen(session),
                  ),
                TextButton(onPressed: onBack, child: const Text('Tillbaka')),
              ],
            ),
    );
  }
}
