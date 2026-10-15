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
    this.revealedPlans = const {},
    this.onDelete,
    this.message,
    this.syncStatus,
    this.loading = false,
    this.hasMore = false,
    this.onLoadMore,
    this.onRetry,
    this.onSelectAll,
    this.validSelectionIds,
  });

  final List<SessionSummary> sessions;
  final ValueChanged<SessionSummary> onOpen;
  final VoidCallback onBack;
  final Set<String> revealedPlans;
  final Future<void> Function(List<String>)? onDelete;
  final Widget? syncStatus;
  final String? message;
  final bool loading, hasMore;
  final VoidCallback? onLoadMore, onRetry;
  final Future<List<String>> Function()? onSelectAll;
  final Set<String>? validSelectionIds;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _allSelected = false;
  bool _selectingAll = false;
  bool _deleting = false;
  String? _error;

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.validSelectionIds != null) {
      _selected.retainAll(widget.validSelectionIds!);
    }
  }

  Future<void> _selectAll() async {
    if (_selectingAll) return;
    setState(() => _selectingAll = true);
    try {
      final ids = widget.onSelectAll == null
          ? widget.sessions.map((s) => s.id).toList()
          : await widget.onSelectAll!();
      if (!mounted) return;
      setState(() {
        if (_selected.length == ids.length && _selected.containsAll(ids)) {
          _selected.clear();
          _allSelected = false;
        } else {
          _selected
            ..clear()
            ..addAll(ids);
          _allSelected = true;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Urvalet kunde inte läsas: $error');
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      _allSelected = false;
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
    final headers = <Widget>[
      if (widget.loading) const LinearProgressIndicator(),
      if (widget.onRetry != null)
        TextButton(
          onPressed: widget.loading ? null : widget.onRetry,
          child: const Text('Försök igen'),
        ),

      if (widget.syncStatus != null) widget.syncStatus!,
      if (widget.message != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.message!),
        ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      if (sessions.isEmpty && !widget.loading && widget.onRetry == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Inga sessioner ännu.'),
        ),
      if (_selecting)
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _selected.isEmpty || _deleting ? null : _deleteSelected,
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
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} valda' : 'Historik'),
        leading: BackButton(onPressed: _deleting ? null : widget.onBack),
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
                onPressed: _deleting || _selectingAll ? null : _selectAll,
                child: Text(_allSelected ? 'Avmarkera' : 'Välj alla'),
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
      body: ListView.builder(
        itemCount: headers.length + sessions.length + 1,
        itemBuilder: (context, index) {
          if (index < headers.length) return headers[index];
          final sessionIndex = index - headers.length;
          if (sessionIndex < sessions.length) {
            return _sessionTile(sessions[sessionIndex]);
          }
          return Column(
            children: [
              if (widget.hasMore)
                TextButton(
                  onPressed: widget.loading ? null : widget.onLoadMore,
                  child: const Text('Visa fler'),
                ),
              TextButton(
                onPressed: _deleting ? null : widget.onBack,
                child: const Text('Tillbaka'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sessionTile(SessionSummary session) => ListTile(
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
      '${session.manifest.meditation == null ? '${session.decisionCount} block' : meditationActionLabel(session.manifest, revealedPlans: widget.revealedPlans)} · '
      '${_duration(session.manifest.durationSeconds)}\n'
      '${_outcome(session)}',
    ),
    onTap: _deleting
        ? null
        : () => _selecting ? _toggle(session.id) : widget.onOpen(session),
    onLongPress: widget.onDelete == null || _deleting
        ? null
        : () => setState(() {
            _selecting = true;
            _selected.add(session.id);
          }),
  );
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
String _outcome(SessionSummary session) {
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
