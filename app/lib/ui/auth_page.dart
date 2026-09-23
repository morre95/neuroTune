import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onSubmit, this.error});

  final Future<void> Function(String email, String password, bool register)
  onSubmit;
  final String? error;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send(bool register) async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_email.text.trim(), _password.text, register);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('neuroTune')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Spektrala EEG-mått under binauralt ljud. Inte ett mått på avslappning, fokus eller behandling.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'E-post'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Lösenord'),
            obscureText: true,
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : () => _send(false),
            child: const Text('Logga in'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _send(true),
            child: const Text('Registrera'),
          ),
        ],
      ),
    );
  }
}
