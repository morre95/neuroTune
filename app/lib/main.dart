import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'data/api_client.dart';
import 'data/auth_store.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'data/upload_sync.dart';
import 'data/profile_library.dart';
import 'ui/profiles_page.dart';
import 'platform/channels.dart';
import 'session/session_controller.dart';
import 'ui/auth_page.dart';
import 'ui/contact_page.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/meditation_home_page.dart';
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

enum _Screen { auth, home, contact, session, history, playback, profiles }

typedef _Remote = ({
  ExperimentConfig config,
  BanditSnapshot snapshot,
  bool offline,
});

class NeuroTuneApp extends StatefulWidget {
  const NeuroTuneApp({
    super.key,
    required this.database,
    required this.authStore,
    required this.api,
    required this.audio,
    required this.keepAlive,
    required this.muse,
    this.meditationEnabled = const bool.fromEnvironment(
      'MEDITATION_ENABLED',
      defaultValue: false,
    ),
  });

  final AppDatabase database;
  final AuthStore authStore;
  final ApiClient api;
  final PcmOutput audio;
  final SessionKeepAlive keepAlive;
  final MuseChannel muse;
  final bool meditationEnabled;

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
  EyeState _eyes = EyeState.closed;
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
  ProfileLibrary? _profileLibrary;
  final _emptyLibrary = ChangeNotifier();
  var _endingSession = false;
  var _inExperiments = false;
  var _networkQuiet = false;
  int _experimentNavigationGeneration = 0;
  Future<void>? _experimentNavigation;
  String? _selectedProfileId;
  StimulusAction _fixedAction = StimulusAction.control;
  bool get _meditating => widget.meditationEnabled && !_inExperiments;

  /// Starting waits on the network, the DSP isolate and the foreground
  /// service. A second tap meanwhile would start a second session on the same
  /// audio output and headband, so starting is locked until it ends.
  var _startingSession = false;

  /// Set once the controller acquires the output, the service and the
  /// headband. Leaving then would race its cleanup against the next start, so
  /// the back button is locked too; until then leaving cancels the start.
  var _openingSession = false;

  /// Moves on when the user leaves the contact page, so a start still waiting
  /// on the network sees that it was cancelled.
  var _startAttempt = 0;
  List<SavedSession> _history = [];
  bool _deletingSessions = false;
  String? _historyMessage;
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
    if (_auth == null || _deletingSessions || _networkQuiet) return;
    unawaited(_syncSessions().catchError((Object _) {}));
  }

  Future<void> _syncSessions() async {
    final owner = _auth!.email;
    await _uploadSync.flush(owner);
    if (!mounted || _auth?.email != owner || _screen != _Screen.history) return;
    final pending = await _repository.pendingDeletions(owner);
    if (!mounted) return;
    setState(() {
      if (pending.isNotEmpty) {
        _historyMessage =
            '${pending.length} raderingar väntar på synk med backenden.';
      } else if (_historyMessage != null) {
        _historyMessage = 'Raderingen är synkroniserad med backenden.';
      }
    });
  }

  /// Unreadable saved state must not leave the app on the loading spinner.
  /// Logging in again overwrites the saved login, and the server replaces a
  /// broken cached config.
  Future<void> _bootstrap() async {
    try {
      await _restoreLogin();
    } catch (failure, stack) {
      log('Saved login could not be read', error: failure, stackTrace: stack);
      _auth = null;
      widget.api.accessToken = null;
      widget.api.refreshToken = null;
      _error = 'Sparad data kunde inte läsas. Logga in igen.';
    }
    if (_auth != null) await _enterHome();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _restoreLogin() async {
    _config = await _repository.loadConfig();
    await _moveLegacyAuth();
    _auth = await widget.authStore.load();
    widget.api.accessToken = _auth?.accessToken;
    widget.api.refreshToken = _auth?.refreshToken;
  }

  /// [_loadRemote] already falls back to the cache when the server is
  /// unreachable, so a failure here is local data that logging in again cannot
  /// repair. The user stays on the login page with the cause.
  Future<void> _enterHome() async {
    try {
      await _repository.claimLegacyUploads(_auth!.email);
      if (widget.meditationEnabled) {
        _snapshot = BanditSnapshot.empty(
          experimentVersion: _config.version,
          origin: DataOrigin.simulator,
        );
        await _ensureProfileLibrary();
        await _profileLibrary?.loadCached();
        _chooseReadyProfile();
      } else {
        _applyRemote(await _loadRemote(DataOrigin.simulator));
      }
    } catch (failure, stack) {
      log('Local data could not be read', error: failure, stackTrace: stack);
      if (mounted) {
        setState(
          () => _error = 'Lokala data på telefonen kunde inte läsas: $failure',
        );
      }
      return;
    }
    _startUploadRetry();
    if (mounted) {
      setState(() {
        _error = null;
        _screen = _Screen.home;
      });
    }
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

  /// Fetches the active experiment and the policy for [origin], falling back
  /// to the cache offline. It returns them instead of storing them, so a start
  /// the user has left cannot overwrite what a newer one loaded.
  Future<_Remote> _loadRemote(
    DataOrigin origin, {
    bool Function()? stillCurrent,
  }) async {
    void checkCurrent() {
      if (stillCurrent?.call() == false) {
        throw StateError('Remote navigation cancelled');
      }
    }

    var config = _config;
    BanditSnapshot snapshot;
    var offline = false;
    try {
      checkCurrent();
      config = await widget.api.activeExperiment();
      checkCurrent();
      await _repository.saveConfig(config);
      checkCurrent();
      snapshot = await widget.api.latestBandit(
        origin: origin.name,
        experimentVersion: config.version,
      );
      checkCurrent();
      await _repository.saveBandit(snapshot);
    } catch (_) {
      snapshot =
          await _repository.loadBandit(origin.name) ??
          BanditSnapshot.empty(
            experimentVersion: config.version,
            origin: origin,
            epsilon: config.epsilon,
          );
      offline = true;
    }
    final local = await _repository.localRewards(origin.name, config.version);
    return (
      config: config,
      snapshot: overlayLocalRewards(server: snapshot, local: local),
      offline: offline,
    );
  }

  void _applyRemote(_Remote remote) {
    _config = remote.config;
    _snapshot = remote.snapshot;
    _offline = remote.offline;
  }

  Future<void> _submitAuth(String email, String password, bool register) async {
    final AuthTokens tokens;
    try {
      tokens = register
          ? await widget.api.register(email, password)
          : await widget.api.login(email, password);
    } on ApiException catch (error) {
      final message = switch (error.status) {
        401 => 'Fel e-post eller lösenord. Försök igen.',
        409 => 'E-postadressen är redan registrerad. Logga in i stället.',
        422 => 'Lösenordet måste vara minst 8 tecken.',
        _ => 'Servern svarade inte som väntat (${error.status}).',
      };
      setState(() => _error = message);
      return;
    } on TimeoutException {
      setState(
        () => _error =
            'Inloggningen tog för lång tid. Kontrollera att telefonen når ${widget.api.baseUrl}.',
      );
      return;
    } on http.ClientException {
      setState(
        () => _error =
            'Servern nås inte via ${widget.api.baseUrl}. Kontrollera API_BASE på en fysisk telefon.',
      );
      return;
    } on TlsException catch (failure, stack) {
      // IOClient only wraps socket and HTTP errors in ClientException, so a
      // rejected certificate arrives here as it is.
      log('TLS handshake failed', error: failure, stackTrace: stack);
      setState(
        () => _error =
            'Säker anslutning till ${widget.api.baseUrl} misslyckades. Kontrollera serverns certifikat.',
      );
      return;
    } catch (failure, stack) {
      log('Login response was malformed', error: failure, stackTrace: stack);
      setState(() => _error = 'Servern svarade inte som väntat.');
      return;
    }
    try {
      await widget.authStore.save(tokens);
    } catch (failure, stack) {
      log('Login could not be saved', error: failure, stackTrace: stack);
      setState(
        () => _error = 'Inloggningen kunde inte sparas på telefonen: $failure',
      );
      return;
    }
    _auth = tokens;
    await _enterHome();
  }

  Future<void> _logout() async {
    _experimentNavigationGeneration++;
    await _profileLibrary?.close();
    _profileLibrary = null;
    _selectedProfileId = null;
    _networkQuiet = false;
    _inExperiments = false;
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

  Future<void> _ensureProfileLibrary() async {
    final owner = widget.api.accountId;
    if (owner == null) {
      throw StateError('Kontot kunde inte identifieras. Logga in igen.');
    }
    final generation = widget.api.authGeneration;
    final dir = await getApplicationSupportDirectory();
    if (!mounted || generation != widget.api.authGeneration) return;
    _profileLibrary ??= ProfileLibrary(
      database: widget.database,
      api: widget.api,
      directory: dir,
      ownerAccountId: owner,
      audio: widget.audio,
      audioBusy: () =>
          _session != null ||
          _startingSession ||
          _stereoTestPlaying ||
          _stereoTestBusy,
    );
  }

  void _chooseReadyProfile() {
    final ready =
        _profileLibrary?.profiles.where((p) => p.downloaded).toList() ?? [];
    if (!ready.any((p) => p.profile.id == _selectedProfileId)) {
      _selectedProfileId = ready.isEmpty ? null : ready.first.profile.id;
    }
  }

  Future<void> _openExperiments() => _experimentNavigation ??=
      _enterExperiments().whenComplete(() => _experimentNavigation = null);

  Future<void> _enterExperiments() async {
    final owner = _auth?.email;
    final generation = widget.api.authGeneration;
    final navigation = _experimentNavigationGeneration;
    bool current() =>
        mounted &&
        _auth?.email == owner &&
        widget.api.authGeneration == generation &&
        _experimentNavigationGeneration == navigation &&
        !_networkQuiet &&
        _screen == _Screen.home &&
        !_startingSession &&
        _session == null;
    final remote = await _loadRemote(
      DataOrigin.simulator,
      stillCurrent: current,
    );
    if (!current()) return;
    _applyRemote(remote);
    setState(() => _inExperiments = true);
  }

  Future<void> _openProfiles() async {
    _experimentNavigationGeneration++;
    await _stopStereoTest();
    try {
      await _ensureProfileLibrary();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    if (!mounted || _screen != _Screen.home || _profileLibrary == null) return;
    setState(() => _screen = _Screen.profiles);
    await _profileLibrary!.refresh();
  }

  Future<void> _leaveProfiles() async {
    await _profileLibrary?.stopPreview();
    _chooseReadyProfile();
    if (mounted) setState(() => _screen = _Screen.home);
  }

  void _openContact() {
    _experimentNavigationGeneration++;
    _usingMuse = false;
    _startSimulatorPreview();
    setState(() => _screen = _Screen.contact);
  }

  void _startSimulatorPreview() {
    _preview?.stop();
    _previewSub?.cancel();
    _preview = SimulatorSource(config: _config, sampleRateHz: 256, seed: 1);
    _previewSub = _preview!.batches.listen((batch) {
      if (mounted) setState(() => _contactBatch = batch);
    });
    _preview!.start();
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
    if (_startingSession) return;
    final attempt = ++_startAttempt;
    setState(() => _startingSession = true);
    if (_meditating) {
      _networkQuiet = true;
      _experimentNavigationGeneration++;
    }
    try {
      await _openSession(attempt);
    } catch (failure, stack) {
      log('Session could not start', error: failure, stackTrace: stack);
      if (attempt == _startAttempt) {
        _showStartFailure('Sessionen kunde inte starta: $failure');
      }
    } finally {
      if (attempt == _startAttempt && mounted) {
        setState(() {
          _startingSession = false;
          _openingSession = false;
          if (_session == null && _networkQuiet) {
            _networkQuiet = false;
            _profileLibrary?.resumeNetwork();
            _retryUploads();
          }
        });
      }
    }
  }

  Future<void> _openSession(int attempt) async {
    final origin = _usingMuse ? DataOrigin.muse : DataOrigin.simulator;
    await _stopStereoTest();
    if (_usingMuse) {
      await _musePreview?.cancel();
      _musePreview = null;
    } else {
      await _preview?.stop();
      await _previewSub?.cancel();
    }
    MeditationSetup? meditation;
    if (_meditating) {
      // A prior navigation may still own an HTTP request (including refresh).
      // Join it before audio, and suppress every follow-up request in its chain.
      await _experimentNavigation;
      if (!mounted || attempt != _startAttempt) return;
      _uploadSync.cancel();
      try {
        await _uploadSync.waitForIdle();
      } catch (_) {}
      await _profileLibrary!.suspendNetwork();
      if (attempt != _startAttempt) return;
      final id = _selectedProfileId;
      if (id == null) throw StateError('Välj en nedladdad profil');
      final file = await _profileLibrary!.playableFile(id);
      if (file == null) throw StateError('Profilen är inte verifierad lokalt');
      final profile = _profileLibrary!.profiles
          .firstWhere((p) => p.profile.id == id)
          .profile;
      meditation = MeditationSetup(
        profile: profile,
        file: file,
        action: _fixedAction,
      );
      _snapshot = BanditSnapshot.empty(
        experimentVersion: _config.version,
        origin: origin,
      );
    } else {
      final remote = await _loadRemote(origin);
      if (attempt != _startAttempt) return;
      _applyRemote(remote);
    }
    if (!mounted || attempt != _startAttempt) return;
    setState(() => _openingSession = true);
    final controller = SessionController(
      repository: _repository,
      meditation: meditation,
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
      controller.dispose();
      _showStartFailure(controller.error);
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

  /// The start tore the contact preview down, so it is brought back for the
  /// user to retry from the contact page.
  void _showStartFailure(String? message) {
    if (_usingMuse) {
      _listenToMuse();
    } else {
      _startSimulatorPreview();
    }
    setState(() => _error = message);
  }

  /// Leaving while a start waits on the network cancels it.
  Future<void> _leaveContact() async {
    _startAttempt += 1;
    _networkQuiet = false;
    _profileLibrary?.resumeNetwork();
    _retryUploads();
    setState(() => _startingSession = false);
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
  }

  void _listenToMuse() {
    _musePreview?.cancel();
    _musePreview = widget.muse.eeg.listen((batch) {
      if (mounted) setState(() => _contactBatch = batch);
    });
  }

  Future<void> _muse() async {
    _experimentNavigationGeneration++;
    if (_connectingMuse) return;
    _usingMuse = true;
    await _preview?.stop();
    await _previewSub?.cancel();
    setState(() {
      _connectingMuse = true;
      _error = 'Söker efter Muse S Athena.';
    });
    try {
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
      failure = controller.saved
          ? 'Sessionen är sparad, men resurserna kunde inte stängas: $error'
          : 'Sessionen kunde inte sparas: $error';
    }
    controller.dispose();
    _session = null;
    _usingMuse = false;
    _endingSession = false;
    _networkQuiet = false;
    _profileLibrary?.resumeNetwork();
    _retryUploads();
    if (mounted) {
      setState(() {
        _error = failure;
        _screen = _Screen.home;
      });
    }
  }

  Future<void> _openHistory() async {
    _experimentNavigationGeneration++;
    _history = await _repository.listOwnedSessions(_auth!.email);
    final pending = await _repository.pendingDeletions(_auth!.email);
    _historyMessage = pending.isEmpty
        ? null
        : '${pending.length} raderingar väntar på synk med backenden.';
    setState(() => _screen = _Screen.history);
  }

  Future<void> _deleteSessions(List<String> ids) async {
    if (_deletingSessions) return;
    _deletingSessions = true;
    try {
      // Let any in-flight upload finish before changing its persistent job.
      _uploadSync.cancel();
      await _uploadSync.waitForIdle();
      await _repository.deleteSessions(ids, _auth!.email);
      _snapshot = null;
      _history = await _repository.listOwnedSessions(_auth!.email);
      if (mounted) {
        setState(
          () => _historyMessage =
              'Sessionerna är raderade på mobilen. Raderingen synkas med backenden.',
        );
      }
      await _syncSessions();
    } finally {
      _deletingSessions = false;
      _retryUploads();
    }
  }

  @override
  void dispose() {
    _experimentNavigationGeneration++;
    _emptyLibrary.dispose();
    _uploadRetryTimer?.cancel();
    _uploadSync.cancel();
    widget.api.onTokensRefreshed = null;
    unawaited(_stereoTest.stop());
    unawaited(() async {
      await _profileLibrary?.close();
      await widget.database.close();
    }());
    _previewSub?.cancel();
    _preview?.stop();
    _session?.dispose();
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
      home: PopScope(
        canPop: _screen != _Screen.profiles,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _screen == _Screen.profiles) {
            unawaited(_leaveProfiles());
          }
        },
        child: !_ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _page(),
      ),
    );
  }

  Widget _page() {
    return switch (_screen) {
      _Screen.auth => AuthPage(onSubmit: _submitAuth, error: _error),
      _Screen.home =>
        _meditating
            ? ListenableBuilder(
                listenable: _profileLibrary ?? _emptyLibrary,
                builder: (context, _) => MeditationHomePage(
                  profiles: _profileLibrary?.profiles ?? [],
                  selectedProfileId: _selectedProfileId,
                  action: _fixedAction,
                  eyeState: _eyes,
                  onProfile: (id) => setState(() => _selectedProfileId = id),
                  onAction: (a) => setState(() => _fixedAction = a),
                  onEyeState: (e) => setState(() => _eyes = e),
                  onSimulator: _openContact,
                  onMuse: _muse,
                  connectingMuse: _connectingMuse,
                  onProfiles: _openProfiles,
                  onExperiments: _openExperiments,
                  onHistory: _openHistory,
                  onLogout: _logout,
                  message: _error,
                ),
              )
            : HomePage(
                onBack: widget.meditationEnabled
                    ? () => setState(() => _inExperiments = false)
                    : null,
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
                onProfiles: _openProfiles,
                onLogout: _logout,
                message: _error,
              ),
      _Screen.contact => ContactPage(
        requireSignal: !_meditating,
        startLabel: _meditating ? 'Starta meditation' : 'Starta baslinje',
        batteryPercent: _usingMuse ? widget.muse.batteryPercent : null,
        batch: _contactBatch,
        onStereoTest: _toggleStereoTest,
        stereoTestPlaying: _stereoTestPlaying,
        stereoTestBusy: _stereoTestBusy,
        startingSession: _startingSession,
        openingSession: _openingSession,
        note: _usingMuse
            ? 'Kvalitetsgränserna är inte verifierade mot en inspelning från Athena.'
            : null,
        error: _error,
        onStart: _startSession,
        onBack: _leaveContact,
      ),
      _Screen.session => SessionPage(
        batteryPercent: _usingMuse ? widget.muse.batteryPercent : null,
        view: _session!.view,
        onStop: () => _session?.interrupt(StopReason.manual),
        onContinue: () => _session?.continueSession(),
        onFinish: _endingSession ? null : _finishSession,
      ),
      _Screen.history => HistoryPage(
        sessions: _history,
        onDelete: _deleteSessions,
        message: _historyMessage,
        onOpen: (session) => setState(() {
          _playback = session;
          _screen = _Screen.playback;
        }),
        onBack: () => setState(() => _screen = _Screen.home),
      ),
      _Screen.profiles => ProfilesPage(
        library: _profileLibrary!,
        onBack: _leaveProfiles,
        audioBusy:
            _session != null ||
            _startingSession ||
            _stereoTestPlaying ||
            _stereoTestBusy,
      ),
      _Screen.playback => PlaybackPage(
        session: _playback!,
        onBack: () => setState(() => _screen = _Screen.history),
      ),
    };
  }
}
