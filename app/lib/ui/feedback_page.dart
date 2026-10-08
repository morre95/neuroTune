import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

/// Only shown for a saved, full session. Each selected integer saves a draft.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    required this.sessionId,
    required this.feedback,
    required this.onSave,
    required this.onLater,
    this.message,
  });
  final String sessionId;
  final String? message;
  final MeditationFeedback? feedback;
  final Future<void> Function(int? mentalBusyness, int? relaxation) onSave;
  final VoidCallback onLater;
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int? _busyness, _relaxation;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _busyness = widget.feedback?.mentalBusyness;
    _relaxation = widget.feedback?.relaxation;
  }

  Future<void> _save(int? busy, int? relaxed) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(busy, relaxed);
      if (mounted) {
        setState(() {
          _busyness = busy ?? _busyness;
          _relaxation = relaxed ?? _relaxation;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Återkopplingen kunde inte sparas: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_saving) widget.onLater();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Efter meditationen')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Hur upplevde du sessionen? Skattningarna sparas på mobilen och kan slutföras senare utan nätverk.',
          ),
          if (widget.message != null) Text(widget.message!),
          if (_error != null) Text(_error!),
          const SizedBox(height: 20),
          _rating(
            'Mental upptagenhet',
            '0 · ingen',
            '10 · extrem',
            _busyness,
            (value) => _save(value, null),
          ),
          const SizedBox(height: 20),
          _rating(
            'Avslappning',
            '0 · ingen',
            '10 · fullständig',
            _relaxation,
            (value) => _save(null, value),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _busyness == null || _relaxation == null
                ? null
                : widget.onLater,
            child: const Text('Klar'),
          ),
          TextButton(
            onPressed: _saving ? null : widget.onLater,
            child: const Text('Slutför senare'),
          ),
        ],
      ),
    ),
  );
  Widget _rating(
    String label,
    String low,
    String high,
    int? value,
    ValueChanged<int> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(value == null ? 'Inte skattad ännu' : '$value / 10'),
      Wrap(
        spacing: 4,
        children: [
          for (var n = 0; n <= 10; n++)
            ChoiceChip(
              label: Text('$n'),
              selected: value == n,
              onSelected: _saving ? null : (_) => change(n),
            ),
        ],
      ),
      Text('$low — $high'),
    ],
  );
}
