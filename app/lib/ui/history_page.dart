import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

import '../data/repository.dart';
import 'session_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.sessions,
    required this.onOpen,
    required this.onBack,
    this.onDelete,
    this.message,
  });

  final List<SavedSession> sessions;
  final ValueChanged<SavedSession> onOpen;
  final VoidCallback onBack;
  final Future<void> Function(List<String>)? onDelete;
  final String? message;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _deleting = false;
  String? _error;

  void _toggle(String id) {
    setState(() {
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Radera ${ids.length} sessioner?'),
        content: const Text(
          'Sessionerna och deras rådata raderas från mobilen och ditt konto. Om backenden inte nås köas raderingen tills anslutningen återkommer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Radera'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete!(ids);
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Raderingen kunde inte genomföras: $error');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} valda' : 'Historik'),
        actions: [
          if (widget.onDelete != null && sessions.isNotEmpty)
            if (!_selecting)
              TextButton(
                onPressed: _deleting
                    ? null
                    : () => setState(() => _selecting = true),
                child: const Text('Välj'),
              )
            else ...[
              TextButton(
                onPressed: _deleting
                    ? null
                    : () => setState(() {
                        if (_selected.length == sessions.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(
                            sessions.map((session) => session.id),
                          );
                        }
                      }),
                child: Text(
                  _selected.length == sessions.length
                      ? 'Avmarkera'
                      : 'Välj alla',
                ),
              ),
              IconButton(
                tooltip: 'Avsluta val',
                onPressed: _deleting
                    ? null
                    : () => setState(() {
                        _selecting = false;
                        _selected.clear();
                      }),
                icon: const Icon(Icons.close),
              ),
            ],
        ],
      ),
      body: ListView(
        children: [
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.message!),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Inga sessioner ännu.'),
            ),
          if (_selecting)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _deleting
                    ? null
                    : _deleteSelected,
                icon: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text(
                  _deleting ? 'Raderar…' : 'Radera valda (${_selected.length})',
                ),
              ),
            ),
          for (final session in sessions)
            ListTile(
              key: ValueKey(session.id),
              selected: _selected.contains(session.id),
              leading: _selecting
                  ? Checkbox(
                      value: _selected.contains(session.id),
                      onChanged: _deleting ? null : (_) => _toggle(session.id),
                    )
                  : null,
              isThreeLine: true,
              title: Text(session.manifest.startedAtIso),
              subtitle: Text(
                '${session.origin} · ${session.manifest.meditation == null ? session.mode : 'Meditation'} · '
                '${session.manifest.meditation == null ? '${session.decisions.length} block' : meditationActionLabel(session.manifest)} · '
                '${_duration(session.manifest.durationSeconds)}\n'
                '${_outcome(session)}',
              ),
              onTap: _deleting
                  ? null
                  : () => _selecting
                        ? _toggle(session.id)
                        : widget.onOpen(session),
              onLongPress: widget.onDelete == null || _deleting
                  ? null
                  : () => setState(() {
                      _selecting = true;
                      _selected.add(session.id);
                    }),
            ),
          TextButton(
            onPressed: _deleting ? null : widget.onBack,
            child: const Text('Tillbaka'),
          ),
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
  if (manifest.meditation != null) {
    return session.status == 'completed'
        ? 'Slutförd${_losses(manifest)}'
        : 'Stoppad${_losses(manifest)}';
  }
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
    'processingFailed' => 'signalbehandlingen slutade fungera',
    _ => reason,
  };
}
