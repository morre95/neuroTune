import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'data/api_client.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'platform/channels.dart';
import 'session/session_controller.dart';
import 'ui/auth_page.dart';
import 'ui/contact_page.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/playback_page.dart';
import 'ui/session_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );
  runApp(
    NeuroTuneApp(
      database: AppDatabase(),
      api: ApiClient(baseUrl: baseUrl),
      audio: AndroidPcmOutput(),
      muse: MuseChannel(),
    ),
  );
}

enum _Screen { auth, home, contact, session, history, playback }

class NeuroTuneApp extends StatefulWidget {
  const NeuroTuneApp({
    super.key,
    required this.database,
    required this.api,
    required this.audio,
    required this.muse,
  });

  final AppDatabase database;
  final ApiClient api;
  final PcmOutput audio;
  final MuseChannel muse;

  @override
  State<NeuroTuneApp> createState() => _NeuroTuneAppState();
}

class _NeuroTuneAppState extends State<NeuroTuneApp> {
  late final SessionRepository _repository = SessionRepository(widget.database);
  _Screen _screen = _Screen.auth;
  ExperimentConfig _config = ExperimentConfig.defaults();
  BanditSnapshot? _snapshot;
  AuthTokens? _auth;
  String? _error;
  var _offline = false;
  var _ready = false;
  EyeState _eyes = EyeState.open;
  SessionMode _mode = SessionMode.personal;
  EegBatch? _contactBatch;
  SimulatorSource? _preview;
  StreamSubscription<EegBatch>? _previewSub;
  StreamSubscription<EegBatch>? _musePreview;
  var _usingMuse = false;
  var _connectingMuse = false;
  final StereoTestPlayer _stereoTest = StereoTestPlayer();
  var _stereoTestPlaying = false;
  var _stereoTestBusy = false;
  Future<void>? _stereoTestStart;
  SessionController? _session;
  List<SavedSession> _history = [];
  SavedSession? _playback;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _config = await _repository.loadConfig();
    final saved = await _repository.loadAuth();
    if (saved != null && saved.contains('access_token')) {
      _auth = AuthTokens.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      widget.api.accessToken = _auth!.accessToken;
      widget.api.refreshToken = _auth!.refreshToken;
      await _refreshRemote();
      if (mounted) setState(() => _screen = _Screen.home);
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _refreshRemote() async {
    try {
      _config = await widget.api.activeExperiment();
      await _repository.saveConfig(_config);
      _snapshot = await widget.api.latestBandit(
        origin: DataOrigin.simulator.name,
        experimentVersion: _config.version,
      );
      await _repository.saveBandit(_snapshot!);
      _offline = false;
    } catch (_) {
      _snapshot =
          await _repository.loadBandit(DataOrigin.simulator.name) ??
          BanditSnapshot.empty(
            experimentVersion: _config.version,
            origin: DataOrigin.simulator,
            epsilon: _config.epsilon,
          );
      _offline = true;
    }
    final local = await _repository.localRewards(
      DataOrigin.simulator.name,
      _config.version,
    );
    _snapshot = overlayLocalRewards(server: _snapshot!, local: local);
  }

  Future<void> _submitAuth(String email, String password, bool register) async {
    try {
      final tokens = register
          ? await widget.api.register(email, password)
          : await widget.api.login(email, password);
      await _repository.saveAuth(jsonEncode(tokens.toJson()));
      _auth = tokens;
      await _refreshRemote();
      setState(() {
        _error = null;
        _screen = _Screen.home;
      });
    } on ApiException catch (error) {
      final message = switch (error.status) {
        401 => 'Fel e-post eller lösenord. Registrera kontot först.',
        409 => 'E-postadressen är redan registrerad. Logga in i stället.',
        422 => 'Lösenordet måste vara minst 8 tecken.',
        _ => 'Servern svarade inte som väntat (${error.status}).',
      };
      setState(() => _error = message);
    } catch (_) {
      setState(
        () => _error =
            'Servern nås inte. API:t ska köra på http://10.0.2.2:8000 från emulatorn.',
      );
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    await _repository.saveAuth('{}');
    _auth = null;
    widget.api.accessToken = null;
    setState(() => _screen = _Screen.auth);
  }

  void _openContact() {
    _usingMuse = false;
    _preview?.stop();
    _previewSub?.cancel();
    _preview = SimulatorSource(config: _config, sampleRateHz: 256, seed: 1);
    _previewSub = _preview!.batches.listen((batch) {
      if (mounted) setState(() => _contactBatch = batch);
    });
    _preview!.start();
    setState(() => _screen = _Screen.contact);
  }

  Future<void> _toggleStereoTest() async {
    if (_stereoTestBusy) return;
    setState(() => _stereoTestBusy = true);
    try {
      if (_stereoTestPlaying) {
        await _stopStereoTest();
      } else {
        final start = _stereoTest.start();
        _stereoTestStart = start;
        await start;
        if (mounted) setState(() => _stereoTestPlaying = true);
      }
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Hörlurstestet misslyckades: $error');
      }
    } finally {
      _stereoTestStart = null;
      if (mounted) setState(() => _stereoTestBusy = false);
    }
  }

  Future<void> _stopStereoTest() async {
    try {
      await _stereoTestStart;
    } catch (_) {
      return;
    }
    if (!_stereoTestPlaying) return;
    await _stereoTest.stop();
    if (mounted) setState(() => _stereoTestPlaying = false);
  }

  Future<void> _startSession() async {
    await _stopStereoTest();
    if (_usingMuse) {
      await _musePreview?.cancel();
      _musePreview = null;
    } else {
      await _preview?.stop();
      await _previewSub?.cancel();
    }
    await _refreshRemote();
    final controller = SessionController(
      repository: _repository,
      api: widget.api,
      audio: widget.audio,
      config: _config,
      snapshot: _snapshot!,
      mode: _mode,
      eyeState: _eyes,
      origin: _usingMuse ? DataOrigin.muse : DataOrigin.simulator,
    );
    final started = await controller.start(
      muse: _usingMuse ? widget.muse : null,
    );
    if (!started) {
      if (_usingMuse) _listenToMuse();
      setState(() => _error = controller.error);
      controller.dispose();
      return;
    }
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _session = controller;
      _error = null;
      _screen = _Screen.session;
    });
  }

  void _listenToMuse() {
    _musePreview = widget.muse.eeg.listen((batch) {
      if (mounted) setState(() => _contactBatch = batch);
    });
  }

  Future<void> _muse() async {
    if (_connectingMuse) return;
    _usingMuse = true;
    await _preview?.stop();
    await _previewSub?.cancel();
    setState(() {
      _connectingMuse = true;
      _error = 'Söker efter Muse S Athena.';
    });
    try {
      await _musePreview?.cancel();
      _listenToMuse();
      await widget.muse.start();
      if (!mounted) return;
      setState(() {
        _error = null;
        _contactBatch = null;
        _screen = _Screen.contact;
      });
    } on PlatformException catch (error) {
      _usingMuse = false;
      setState(() => _error = error.message ?? 'Muse är inte tillgänglig.');
    } catch (error) {
      _usingMuse = false;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _connectingMuse = false);
    }
  }

  Future<void> _openHistory() async {
    _history = await _repository.listSessions();
    setState(() => _screen = _Screen.history);
  }

  @override
  void dispose() {
    unawaited(_stereoTest.stop());
    _previewSub?.cancel();
    _preview?.stop();
    _session?.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'neuroTune',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F6A)),
        useMaterial3: true,
      ),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _page(),
    );
  }

  Widget _page() {
    return switch (_screen) {
      _Screen.auth => AuthPage(onSubmit: _submitAuth, error: _error),
      _Screen.home => HomePage(
        experimentVersion: _config.version,
        policyVersion: _snapshot?.policyVersion ?? '0',
        hardwareApproved: _config.hardwareApproved,
        offline: _offline,
        eyeState: _eyes,
        mode: _mode,
        onEyeState: (value) => setState(() => _eyes = value),
        onMode: (value) => setState(() => _mode = value),
        onStartSimulator: _openContact,
        onMuse: _muse,
        connectingMuse: _connectingMuse,
        onHistory: _openHistory,
        onLogout: _logout,
        message: _error,
      ),
      _Screen.contact => ContactPage(
        batch: _contactBatch,
        onStereoTest: _toggleStereoTest,
        stereoTestPlaying: _stereoTestPlaying,
        stereoTestBusy: _stereoTestBusy,
        note: _usingMuse
            ? 'Kvalitetsgränserna är inte verifierade mot en inspelning från Athena.'
            : null,
        error: _error,
        onStart: _startSession,
        onBack: () async {
          await _stopStereoTest();
          if (_usingMuse) {
            _musePreview?.cancel();
            widget.muse.stop();
            _usingMuse = false;
          } else {
            _preview?.stop();
          }
          setState(() {
            _error = null;
            _screen = _Screen.home;
          });
        },
      ),
      _Screen.session => SessionPage(
        view: _session!.view,
        onStop: () => _session?.interrupt(StopReason.manual),
        onContinue: () => _session?.continueSession(),
        onFinish: () async {
          final controller = _session;
          await controller?.finish();
          controller?.dispose();
          _session = null;
          _usingMuse = false;
          if (mounted) setState(() => _screen = _Screen.home);
        },
      ),
      _Screen.history => HistoryPage(
        sessions: _history,
        onOpen: (session) => setState(() {
          _playback = session;
          _screen = _Screen.playback;
        }),
        onBack: () => setState(() => _screen = _Screen.home),
      ),
      _Screen.playback => PlaybackPage(
        session: _playback!,
        onBack: () => setState(() => _screen = _Screen.history),
      ),
    };
  }
}
