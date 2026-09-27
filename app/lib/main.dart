import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'data/api_client.dart';
import 'data/auth_store.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'data/upload_sync.dart';
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
      authStore: AuthStore(),
      api: ApiClient(baseUrl: baseUrl),
      audio: AndroidPcmOutput(),
      keepAlive: AndroidSessionKeepAlive(),
      muse: MuseChannel(),
    ),
  );
}

enum _Screen { auth, home, contact, session, history, playback }

class NeuroTuneApp extends StatefulWidget {
  const NeuroTuneApp({
    super.key,
    required this.database,
    required this.authStore,
    required this.api,
    required this.audio,
    required this.keepAlive,
    required this.muse,
  });

  final AppDatabase database;
  final AuthStore authStore;
  final ApiClient api;
  final PcmOutput audio;
  final SessionKeepAlive keepAlive;
  final MuseChannel muse;

  @override
  State<NeuroTuneApp> createState() => _NeuroTuneAppState();
}

class _NeuroTuneAppState extends State<NeuroTuneApp> {
  late final SessionRepository _repository = SessionRepository(widget.database);
  late final UploadSync _uploadSync = UploadSync(
    repository: _repository,
    api: widget.api,
  );
  Timer? _uploadRetryTimer;
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
  var _endingSession = false;
  List<SavedSession> _history = [];
  SavedSession? _playback;

  @override
  void initState() {
    super.initState();
    widget.api.onTokensRefreshed = (access, refresh) async {
      final current = _auth;
      if (current == null) return;
      _auth = AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        email: current.email,
      );
      await widget.authStore.save(_auth!);
    };
    _bootstrap();
  }

  void _startUploadRetry() {
    _uploadRetryTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _retryUploads(),
    );
    _retryUploads();
  }

  void _retryUploads() {
    if (_auth == null) return;
    unawaited(_uploadSync.flush(_auth!.email).catchError((Object _) {}));
  }

  /// Unreadable saved state must not leave the app on the loading spinner.
  /// The user logs in again, which overwrites the saved login, and the server
  /// replaces a broken cached config.
  Future<void> _bootstrap() async {
    try {
      await _restore();
    } catch (failure, stack) {
      log(
        'Saved state could not be restored',
        error: failure,
        stackTrace: stack,
      );
      _auth = null;
      widget.api.accessToken = null;
      widget.api.refreshToken = null;
      _screen = _Screen.auth;
      _error = 'Sparad data kunde inte läsas. Logga in igen.';
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _restore() async {
    _config = await _repository.loadConfig();
    await _moveLegacyAuth();
    _auth = await widget.authStore.load();
    if (_auth == null) return;
    widget.api.accessToken = _auth!.accessToken;
    widget.api.refreshToken = _auth!.refreshToken;
    await _repository.claimLegacyUploads(_auth!.email);
    await _refreshRemote();
    _startUploadRetry();
    _screen = _Screen.home;
  }

  /// A logged-out legacy row holds '{}'. The row is deleted even when it is
  /// unreadable, or it would fail every start after the user logs in again.
  Future<void> _moveLegacyAuth() async {
    final legacy = await _repository.loadLegacyAuth();
    if (legacy == null) return;
    try {
      if (legacy.contains('access_token')) {
        await widget.authStore.save(
          AuthTokens.fromJson(jsonDecode(legacy) as Map<String, dynamic>),
        );
      }
    } finally {
      await _repository.deleteLegacyAuth();
    }
  }

  Future<void> _refreshRemote({
    DataOrigin origin = DataOrigin.simulator,
  }) async {
    try {
      _config = await widget.api.activeExperiment();
      await _repository.saveConfig(_config);
      _snapshot = await widget.api.latestBandit(
        origin: origin.name,
        experimentVersion: _config.version,
      );
      await _repository.saveBandit(_snapshot!);
      _offline = false;
    } catch (_) {
      _snapshot =
          await _repository.loadBandit(origin.name) ??
          BanditSnapshot.empty(
            experimentVersion: _config.version,
            origin: origin,
            epsilon: _config.epsilon,
          );
      _offline = true;
    }
    final local = await _repository.localRewards(origin.name, _config.version);
    _snapshot = overlayLocalRewards(server: _snapshot!, local: local);
  }

  Future<void> _submitAuth(String email, String password, bool register) async {
    try {
      final tokens = register
          ? await widget.api.register(email, password)
          : await widget.api.login(email, password);
      await widget.authStore.save(tokens);
      _auth = tokens;
      await _refreshRemote();
      _startUploadRetry();
      setState(() {
        _error = null;
        _screen = _Screen.home;
      });
    } on ApiException catch (error) {
      final message = switch (error.status) {
        401 => 'Fel e-post eller lösenord. Försök igen.',
        409 => 'E-postadressen är redan registrerad. Logga in i stället.',
        422 => 'Lösenordet måste vara minst 8 tecken.',
        _ => 'Servern svarade inte som väntat (${error.status}).',
      };
      setState(() => _error = message);
    } on TimeoutException {
      setState(
        () => _error =
            'Inloggningen tog för lång tid. Kontrollera att telefonen når ${widget.api.baseUrl}.',
      );
    } catch (_) {
      setState(
        () => _error =
            'Servern nås inte via ${widget.api.baseUrl}. Kontrollera API_BASE på en fysisk telefon.',
      );
    }
  }

  Future<void> _logout() async {
    _uploadRetryTimer?.cancel();
    _uploadRetryTimer = null;
    _uploadSync.cancel();
    try {
      await _uploadSync.waitForIdle();
    } catch (_) {}
    try {
      await widget.api.logout();
    } catch (_) {}
    await widget.authStore.clear();
    _auth = null;
    widget.api.accessToken = null;
    widget.api.refreshToken = null;
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
    final origin = _usingMuse ? DataOrigin.muse : DataOrigin.simulator;
    await _stopStereoTest();
    if (_usingMuse) {
      await _musePreview?.cancel();
      _musePreview = null;
    } else {
      await _preview?.stop();
      await _previewSub?.cancel();
    }
    await _refreshRemote(origin: origin);
    final controller = SessionController(
      repository: _repository,
      ownerEmail: _auth!.email,
      audio: widget.audio,
      keepAlive: widget.keepAlive,
      config: _config,
      snapshot: _snapshot!,
      mode: _mode,
      eyeState: _eyes,
      origin: origin,
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

  /// The button stays disabled until the save is done, so a second tap cannot
  /// dispose the controller while the first one still waits for it.
  Future<void> _finishSession() async {
    final controller = _session;
    if (controller == null || _endingSession) return;
    setState(() => _endingSession = true);
    String? failure;
    try {
      await controller.finish();
    } catch (error) {
      failure = 'Sessionen kunde inte sparas: $error';
    }
    controller.dispose();
    _session = null;
    _usingMuse = false;
    _endingSession = false;
    _retryUploads();
    if (mounted) {
      setState(() {
        _error = failure;
        _screen = _Screen.home;
      });
    }
  }

  Future<void> _openHistory() async {
    _history = await _repository.listSessions();
    setState(() => _screen = _Screen.history);
  }

  @override
  void dispose() {
    _uploadRetryTimer?.cancel();
    _uploadSync.cancel();
    widget.api.onTokensRefreshed = null;
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
        onFinish: _endingSession ? null : _finishSession,
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
