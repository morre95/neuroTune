import 'data/meditation_action_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

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
import 'data/calibration_repository.dart';
import 'data/meditation_preference_repository.dart';
import 'data/personal_eeg_repository.dart';
import 'ui/personal_model_status.dart';
import 'ui/meditation_preference_page.dart';
import 'ui/calibration_page.dart';
import 'ui/feedback_page.dart';
import 'ui/meditation_sync_status.dart';
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

enum _Screen {
  auth,
  home,
  contact,
  session,
  finishing,
  history,
  playback,
  profiles,
  calibration,
  feedback,
  preference,
}

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
  late final CalibrationRepository _calibration = CalibrationRepository(
    widget.database,
    _repository,
  );
  late final MeditationPreferenceRepository _preferences =
      MeditationPreferenceRepository(widget.database, _calibration);
  late final PersonalEegRepository _personalModels = PersonalEegRepository(
    widget.database,
    _repository,
    _calibration,
    widget.api,
  );
  Map<DataOrigin, PersonalEegModel?> _cachedModels = {};
  Future<void>? _modelRefresh;
  String? _modelMessage;
  AudioProfileVersion? get _modelProfile {
    final profiles = _profileLibrary?.profiles.where(
      (p) => p.profile.id == _selectedProfileId,
    );
    return profiles == null || profiles.isEmpty ? null : profiles.first.profile;
  }

  Future<void> _refreshModel(DataOrigin origin) async {
    if (_modelRefresh != null ||
        _networkQuiet ||
        _auth == null ||
        _screen != _Screen.home) {
      return;
    }
    final owner = widget.api.accountId;
    if (owner == null) return;
    final email = _auth!.email;
    final generation = widget.api.authGeneration,
        navigation = _experimentNavigationGeneration;
    bool current() =>
        mounted &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == generation &&
        _experimentNavigationGeneration == navigation &&
        _screen == _Screen.home &&
        !_networkQuiet &&
        _session == null &&
        !_startingSession;
    final task = () async {
      try {
        await _uploadSync.flush(email);
        if (!current()) return;
        await _personalModels.refresh(owner, origin, isCurrent: current);
        if (!current()) return;
        final model = await _personalModels.load(owner, origin);
        if (current()) {
          setState(() {
            _cachedModels[origin] = model;
            _modelMessage = null;
          });
        }
      } catch (_) {
        if (current()) {
          setState(
            () => _modelMessage =
                'Modellen kunde inte uppdateras. En giltig cache fungerar offline.',
          );
        }
      }
    }();
    _modelRefresh = task;
    setState(() => _modelMessage = null);
    try {
      await task;
    } finally {
      if (identical(_modelRefresh, task)) _modelRefresh = null;
      if (mounted) setState(() {});
    }
  }

  FixedMeditationChoice? _preferenceChoice;
  List<CalibrationSlotResult> _preferenceResults = [];
  bool _manualFixedAction = false;
  List<CalibrationProgress> _calibrationProgress = [];
  List<SavedSession> _pendingMeditationFeedback = [];
  Set<String> _revealedPlans = {};
  CalibrationPlan? _activePlan;
  SavedSession? _feedbackSession;
  MeditationFeedback? _feedbackDraft;
  bool _calibrationBusy = false;
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
    final email = _auth?.email;
    if (email == null) return;
    final owner = widget.api.accountId;
    final authentication = widget.api.authGeneration;
    final learningNavigation = _experimentNavigationGeneration;
    final reconcileLearning =
        widget.meditationEnabled && _screen != _Screen.auth && !_inExperiments;
    bool authenticated() =>
        mounted &&
        _auth?.email == email &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == authentication;
    bool learningCurrent() =>
        authenticated() &&
        _experimentNavigationGeneration == learningNavigation &&
        !_networkQuiet &&
        !_startingSession &&
        _session == null;
    await _uploadSync.flush(
      email,
      reconcileLearning: reconcileLearning,
      canReconcileLearning: learningCurrent,
    );
    if (reconcileLearning && learningCurrent()) {
      await _loadCalibration(stillCurrent: learningCurrent);
      if (learningCurrent()) setState(() {});
    }
    if (!authenticated() || _screen != _Screen.history) return;
    final navigation = _experimentNavigationGeneration;
    bool current() =>
        authenticated() &&
        _screen == _Screen.history &&
        _experimentNavigationGeneration == navigation;
    // A server tombstone may have retired evidence while this page was open.
    await _loadCalibration(stillCurrent: current);
    if (!current()) return;
    final history = await _repository.listOwnedSessions(email);
    if (!current()) return;
    final pending = await _repository.pendingDeletions(
      email,
      ownerAccountId: owner,
    );
    if (!current()) return;
    setState(() {
      _history = history;
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
        final owner = widget.api.accountId;
        if (owner != null) {
          await _calibration.recoverInterruptedAttempts(owner);
          await _loadCalibration();
        }
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
    _activePlan = null;
    _calibrationProgress = [];
    _pendingMeditationFeedback = [];
    _revealedPlans = {};
    _feedbackSession = null;
    _feedbackDraft = null;
    _cachedModels = {};
    _modelMessage = null;
    _preferenceChoice = null;
    _preferenceResults = [];
    _manualFixedAction = false;
    _fixedAction = StimulusAction.control;
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

  Future<void> _loadCalibration({bool Function()? stillCurrent}) async {
    final owner = widget.api.accountId;
    if (owner == null) return;
    final generation = widget.api.authGeneration;
    bool current() =>
        mounted &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == generation &&
        (stillCurrent?.call() ?? true);
    final progress = await _calibration.allProgress(owner);
    if (!current()) return;
    final pending = await _calibration.pendingFeedback(owner);
    if (!current()) return;
    final models = <DataOrigin, PersonalEegModel?>{};
    for (final origin in [DataOrigin.simulator, DataOrigin.muse]) {
      models[origin] = await _personalModels.load(owner, origin);
      if (!current()) return;
    }
    _cachedModels = models;
    _calibrationProgress = progress;
    _pendingMeditationFeedback = pending;
    _revealedPlans = {
      for (final p in progress)
        if (p.complete) p.plan.id,
    };
  }

  Future<void> _openCalibration() async {
    final owner = widget.api.accountId;
    if (owner == null) return;
    final generation = widget.api.authGeneration;
    final navigation = ++_experimentNavigationGeneration;
    bool current() =>
        mounted &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == generation &&
        _experimentNavigationGeneration == navigation &&
        _screen == _Screen.home &&
        !_networkQuiet &&
        !_startingSession &&
        _session == null;
    try {
      await _loadCalibration(stillCurrent: current);
      if (current()) {
        setState(() {
          _error = null;
          _screen = _Screen.calibration;
        });
      }
    } catch (error) {
      if (current()) {
        setState(() => _error = 'Kalibreringen kunde inte läsas: $error');
      }
    }
  }

  Future<void> _openCurrentPreference(DataOrigin origin) async {
    final profile = _readyProfile;
    if (profile == null) return;
    await _openPreference(
      MeditationSetupContext(profile: profile, eyeState: _eyes, origin: origin),
    );
  }

  Future<void> _openResults(CalibrationPlan plan) => _openPreference(
    MeditationSetupContext(
      profile: plan.profile,
      eyeState: plan.eyeState,
      origin: plan.origin,
    ),
    planId: plan.id,
  );

  Future<void> _openPreference(
    MeditationSetupContext setup, {
    String? planId,
  }) async {
    final owner = widget.api.accountId;
    final auth = widget.api.authGeneration;
    final navigation = ++_experimentNavigationGeneration;
    bool current() =>
        mounted &&
        owner != null &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == auth &&
        _experimentNavigationGeneration == navigation &&
        _screen == _Screen.calibration;
    if (!current()) return;
    try {
      final choice = await _preferences.resolve(owner!, setup);
      if (!current()) return;
      final results = planId == null
          ? <CalibrationSlotResult>[]
          : await _preferences.revealedResults(owner, planId);
      if (!current() || (planId != null && results.isEmpty)) return;
      setState(() {
        _preferenceChoice = choice;
        _preferenceResults = results;
        _screen = _Screen.preference;
      });
    } catch (e) {
      if (current()) setState(() => _error = 'Resultaten kunde inte läsas: $e');
    }
  }

  Future<void> _choosePreference(StimulusAction action) async {
    final setup = _preferenceChoice!.setup;
    final owner = widget.api.accountId!;
    final auth = widget.api.authGeneration;
    await _preferences.choose(owner, setup, action);
    final choice = await _preferences.resolve(owner, setup);
    if (!mounted ||
        widget.api.accountId != owner ||
        widget.api.authGeneration != auth ||
        _screen != _Screen.preference ||
        _preferenceChoice?.setup.key != setup.key) {
      return;
    }
    setState(() {
      _preferenceChoice = choice;
      _manualFixedAction = false;
      _fixedAction = choice.action;
    });
  }

  Future<void> _additionalSeries() async {
    final setup = _preferenceChoice!.setup;
    final owner = widget.api.accountId!;
    final auth = widget.api.authGeneration;
    final plan = await _calibration.createPlan(
      ownerAccountId: owner,
      profile: setup.profile,
      eyeState: setup.eyeState,
      origin: setup.origin,
    );
    if (!mounted ||
        widget.api.accountId != owner ||
        widget.api.authGeneration != auth ||
        _screen != _Screen.preference) {
      return;
    }
    await _loadCalibration();
    if (!mounted ||
        widget.api.accountId != owner ||
        widget.api.authGeneration != auth ||
        _screen != _Screen.preference) {
      return;
    }
    setState(() => _screen = _Screen.calibration);
    await _startCalibration(plan);
  }

  AudioProfileVersion? get _readyProfile => _profileLibrary?.profiles
      .where((p) => p.profile.id == _selectedProfileId && p.downloaded)
      .firstOrNull
      ?.profile;

  Future<void> _newCalibration(DataOrigin origin) async {
    if (_calibrationBusy) return;
    final owner = widget.api.accountId;
    final profile = _readyProfile;
    if (owner == null || profile == null) return;
    setState(() => _calibrationBusy = true);
    try {
      final plan = await _calibration.createPlan(
        ownerAccountId: owner,
        profile: profile,
        eyeState: _eyes,
        origin: origin,
      );
      if (!mounted || widget.api.accountId != owner) return;
      await _loadCalibration();
      await _launchCalibration(plan);
    } catch (error) {
      if (mounted && widget.api.accountId == owner) {
        setState(() => _error = 'Serien kunde inte starta: $error');
      }
    } finally {
      if (mounted) setState(() => _calibrationBusy = false);
    }
  }

  Future<void> _startCalibration(CalibrationPlan plan) async {
    if (_calibrationBusy) return;
    setState(() => _calibrationBusy = true);
    try {
      await _launchCalibration(plan);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Serien kunde inte fortsätta: $error');
      }
    } finally {
      if (mounted) setState(() => _calibrationBusy = false);
    }
  }

  Future<void> _launchCalibration(CalibrationPlan plan) async {
    final owner = widget.api.accountId;
    if (owner != plan.ownerAccountId) return;
    final progress = await _calibration.progress(owner!, plan.id);
    if (!mounted || widget.api.accountId != owner) return;
    if (progress.awaitingFeedback.isNotEmpty) {
      await _openFeedback(progress.awaitingFeedback.first);
      return;
    }
    if (progress.complete) return;
    final file = await _profileLibrary?.playableFile(plan.profile.id);
    if (!mounted ||
        widget.api.accountId != owner ||
        _screen != _Screen.calibration) {
      return;
    }
    if (file == null) {
      setState(
        () => _error =
            'Ladda ned seriens låsta profilversion i ljudbiblioteket innan du fortsätter.',
      );
      return;
    }
    if (plan.origin == DataOrigin.muse) {
      await _muse(calibrationPlan: plan);
    } else {
      _openContact(calibrationPlan: plan);
    }
  }

  Future<void> _openFeedback(SavedSession session) async {
    final owner = widget.api.accountId;
    if (owner == null) return;
    final pending = await _calibration.pendingFeedback(owner);
    if (!pending.any((s) => s.id == session.id)) return;
    final draft = await _calibration.feedback(owner, session.id);
    if (!mounted || widget.api.accountId != owner) return;
    setState(() {
      _feedbackSession = session;
      _feedbackDraft = draft;
      _screen = _Screen.feedback;
    });
  }

  Widget? get _syncStatus {
    final owner = widget.api.accountId;
    final email = _auth?.email;
    return owner == null || email == null
        ? null
        : MeditationSyncStatusView(
            key: ValueKey('sync:$owner'),
            status: _uploadSync.meditation.watchStatus(owner, email),
          );
  }

  Future<void> _saveFeedback(int? busy, int? relaxed) async {
    final owner = widget.api.accountId;
    final id = _feedbackSession?.id;
    if (owner == null || id == null) throw StateError('Kontot ändrades.');
    await _calibration.saveFeedback(
      owner,
      id,
      mentalBusyness: busy,
      relaxation: relaxed,
    );
    await _loadCalibration();
    if (widget.api.accountId == owner) _retryUploads();
  }

  Future<void> _leaveFeedback() async {
    await _loadCalibration();
    if (mounted) {
      setState(() {
        _feedbackSession = null;
        _feedbackDraft = null;
        _screen = _Screen.calibration;
      });
    }
  }

  void _openContact({CalibrationPlan? calibrationPlan}) {
    _activePlan = calibrationPlan;
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
    String? reservedId;
    Future<void> Function(String)? beforeAcquire;
    if (_meditating) {
      // A prior navigation may still own an HTTP request (including refresh).
      // Join it before audio, and suppress every follow-up request in its chain.
      await _experimentNavigation;
      await _modelRefresh;
      if (!mounted || attempt != _startAttempt) return;
      _uploadSync.cancel();
      try {
        await _uploadSync.waitForIdle();
      } catch (_) {}
      await _profileLibrary!.suspendNetwork();
      if (attempt != _startAttempt) return;
      final plan = _activePlan;
      final id = plan?.profile.id ?? _selectedProfileId;
      if (id == null) throw StateError('Välj en nedladdad profil');
      final file = await _profileLibrary!.playableFile(id);
      if (file == null) throw StateError('Profilen är inte verifierad lokalt');
      final profile =
          plan?.profile ??
          _profileLibrary!.profiles
              .firstWhere((p) => p.profile.id == id)
              .profile;
      CalibrationProgress? progress;
      if (plan != null) {
        if (plan.ownerAccountId != widget.api.accountId ||
            plan.origin != origin) {
          throw StateError('Seriens konto eller datakälla ändrades.');
        }
        progress = await _calibration.progress(plan.ownerAccountId, plan.id);
        if (progress.nextSlot == null || progress.awaitingFeedback.isNotEmpty) {
          throw StateError('Slutför återkopplingen innan nästa session.');
        }
        reservedId = newSessionId(Random.secure());
        final slot = progress.nextSlot!;
        beforeAcquire = (id) async {
          final reservedSlot = await _calibration.reserveAttempt(
            plan.ownerAccountId,
            plan.id,
            id,
          );
          if (reservedSlot != slot) {
            throw StateError('Kalibreringssessionen ändrades.');
          }
        };
      }
      var fixedAction = _fixedAction;
      if (plan == null) {
        final owner = widget.api.accountId!;
        final generation = widget.api.authGeneration;
        final setup = MeditationSetupContext(
          profile: profile,
          eyeState: _eyes,
          origin: origin,
        );
        if (_manualFixedAction) {
          await _preferences.choose(owner, setup, _fixedAction);
        }
        final choice = await _preferences.resolve(owner, setup);
        if (!mounted ||
            attempt != _startAttempt ||
            widget.api.accountId != owner ||
            widget.api.authGeneration != generation) {
          return;
        }
        fixedAction = choice.action;
        _fixedAction = fixedAction;
        _manualFixedAction = false;
      }
      PersonalEegModel? frozenModel;
      MeditationActionStatistics? statistics;
      Future<void> Function(MeditationActionStatistics)? saveStatistics;
      if (plan == null) {
        final owner = widget.api.accountId!;
        final generation = widget.api.authGeneration;
        final scope = MeditationSetupContext(
          profile: profile,
          eyeState: _eyes,
          origin: origin,
        );
        final model = await _personalModels.load(owner, origin);
        if (model?.unsupportedReason(
                  backgroundAssetId: profile.backgroundAssetId,
                  eyeState: _eyes.name,
                  carrierHz: profile.carrierHz,
                  toneGain: profile.toneGain,
                  backgroundGain: profile.backgroundGain,
                  eegConfig: _config,
                ) ==
                null &&
            model != null) {
          final actions = MeditationActionRepository(
            widget.database,
            _repository,
          );
          statistics = await actions.load(owner, scope, model);
          frozenModel = model;
          saveStatistics = (stats) async {
            await actions.save(
              stats,
              isCurrent: () =>
                  mounted &&
                  widget.api.accountId == owner &&
                  widget.api.authGeneration == generation,
            );
          };
        }
        if (!mounted ||
            attempt != _startAttempt ||
            widget.api.accountId != owner ||
            widget.api.authGeneration != generation) {
          return;
        }
      }
      meditation = MeditationSetup(
        profile: profile,
        file: file,
        action: plan == null ? fixedAction : plan.schedule[progress!.nextSlot!],
        model: frozenModel,
        statistics: statistics,
        saveStatistics: saveStatistics,
        metadata: plan == null
            ? {'owner_account_id': widget.api.accountId}
            : plan.sessionMetadata(progress!.nextSlot!),
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
      reservedSessionId: reservedId,
      beforeAcquire: beforeAcquire,
      ownerEmail: _auth!.email,
      audio: widget.audio,
      keepAlive: widget.keepAlive,
      config: _config,
      snapshot: _snapshot!,
      mode: _mode,
      eyeState: _activePlan?.eyeState ?? _eyes,
      origin: origin,
    );
    final started = await controller.start(
      muse: _usingMuse ? widget.muse : null,
    );
    if (!started) {
      controller.dispose();
      if (_activePlan != null && reservedId != null) {
        await _calibration.interruptAttempt(
          _activePlan!.ownerAccountId,
          reservedId,
        );
        await _loadCalibration();
      }
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

  Future<void> _muse({CalibrationPlan? calibrationPlan}) async {
    _activePlan = calibrationPlan;
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
    if (!mounted) return;
    final wasMeditation = controller.isMeditation;
    final feedbackOwner = widget.api.accountId;
    final calibrationPlan = _activePlan;
    final sessionId = controller.engine?.sessionId;
    // A sync/listener rebuild may run while feedback is loaded. Leave the
    // session route atomically before releasing the controller it requires.
    setState(() {
      _screen = _Screen.finishing;
      _session = null;
      _activePlan = null;
      _usingMuse = false;
      _networkQuiet = false;
      _error = failure;
    });
    controller.dispose();
    _profileLibrary?.resumeNetwork();
    _retryUploads();
    if (wasMeditation && feedbackOwner != null) {
      try {
        if (sessionId != null && calibrationPlan != null) {
          await _calibration.interruptAttempt(
            calibrationPlan.ownerAccountId,
            sessionId,
          );
        }
        await _loadCalibration();
        final pending = await _calibration.pendingFeedback(feedbackOwner);
        final session = pending.where((s) => s.id == sessionId).firstOrNull;
        if (session != null) {
          _error = failure;
          await _openFeedback(session);
          if (!mounted) return;
          if (_screen == _Screen.feedback) {
            setState(() => _endingSession = false);
            return;
          }
        }
      } catch (error) {
        failure ??= 'Kalibreringsresultatet kunde inte läsas: $error';
      }
    }
    if (mounted) {
      setState(() {
        _error = failure;
        _endingSession = false;
        _screen = calibrationPlan == null ? _Screen.home : _Screen.calibration;
      });
    }
  }

  Future<void> _openHistory() async {
    _experimentNavigationGeneration++;
    await _loadCalibration();
    _history = await _repository.listOwnedSessions(_auth!.email);
    final pending = await _repository.pendingDeletions(_auth!.email);
    _historyMessage = pending.isEmpty
        ? null
        : '${pending.length} raderingar väntar på synk med backenden.';
    setState(() => _screen = _Screen.history);
  }

  Future<void> _deleteSessions(List<String> ids) async {
    final email = _auth?.email, owner = widget.api.accountId;
    if (_deletingSessions || email == null) return;
    final authentication = widget.api.authGeneration;
    final navigation = _experimentNavigationGeneration;
    bool current() =>
        mounted &&
        _auth?.email == email &&
        widget.api.accountId == owner &&
        widget.api.authGeneration == authentication &&
        _experimentNavigationGeneration == navigation &&
        _screen == _Screen.history;
    _deletingSessions = true;
    try {
      // Join uploads before changing their durable jobs, then guard the queued
      // database transaction against an account or navigation change.
      _uploadSync.cancel();
      await _uploadSync.waitForIdle();
      if (!current()) return;
      await _repository.deleteSessions(
        ids,
        email,
        ownerAccountId: owner,
        isCurrent: current,
      );
      if (!current()) return;
      _snapshot = null;
      await _loadCalibration(stillCurrent: current);
      if (!current()) return;
      final history = await _repository.listOwnedSessions(email);
      if (!current()) return;
      setState(() {
        _history = history;
        _preferenceChoice = null;
        _preferenceResults = [];
        _historyMessage =
            'Sessionerna är raderade på mobilen. Raderingen synkas med backenden.';
      });
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
        canPop: _screen != _Screen.profiles && _screen != _Screen.finishing,
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
                  manualAction: _manualFixedAction,
                  eyeState: _eyes,
                  onProfile: (id) => setState(() {
                    _selectedProfileId = id;
                    _manualFixedAction = false;
                    _fixedAction = StimulusAction.control;
                  }),
                  onAction: (a) => setState(() {
                    _fixedAction = a;
                    _manualFixedAction = true;
                  }),
                  onEyeState: (e) => setState(() {
                    _eyes = e;
                    _manualFixedAction = false;
                    _fixedAction = StimulusAction.control;
                  }),
                  onCalibration: _openCalibration,
                  pendingFeedback: _pendingMeditationFeedback.length,
                  modelStatus: Column(
                    children: [
                      for (final origin in [
                        DataOrigin.simulator,
                        DataOrigin.muse,
                      ])
                        PersonalModelStatus(
                          model: _cachedModels[origin],
                          eegConfig: _config,
                          profile: _modelProfile,
                          eyeState: _eyes,
                          origin: origin,
                          busy: _modelRefresh != null,
                          onRefresh: () => unawaited(_refreshModel(origin)),
                          message: _modelMessage,
                        ),
                    ],
                  ),
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
                onProfiles: widget.meditationEnabled ? _openProfiles : null,
                onLogout: _logout,
                message: _error,
              ),
      _Screen.contact => ContactPage(
        requireSignal: !_meditating,
        startLabel: _activePlan != null
            ? 'Starta kalibrering'
            : _meditating
            ? 'Starta meditation'
            : 'Starta baslinje',
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
        view: _activePlan == null
            ? _session!.view
            : _session!.view.withActionLabel(
                meditationActionLabel(
                  _session!.engine!.manifest(),
                  revealedPlans: _revealedPlans,
                ),
              ),
        onStop: () => _session?.interrupt(StopReason.manual),
        onContinue: () => _session?.continueSession(),
        onFinish: _endingSession ? null : _finishSession,
      ),
      _Screen.finishing => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Slutför sessionen…'),
            ],
          ),
        ),
      ),
      _Screen.history => HistoryPage(
        sessions: _history,
        revealedPlans: _revealedPlans,
        onDelete: _deleteSessions,
        message: _historyMessage,
        syncStatus: _syncStatus,
        onOpen: (session) => setState(() {
          _playback = session;
          _screen = _Screen.playback;
        }),
        onBack: () => setState(() => _screen = _Screen.home),
      ),
      _Screen.calibration => CalibrationPage(
        progress: _calibrationProgress,
        pendingFeedback: _pendingMeditationFeedback,
        profile: _readyProfile,
        eyeState: _eyes,
        onNewSeries: _newCalibration,
        onResume: _startCalibration,
        onFeedback: _openFeedback,
        onResults: _openResults,
        onPreference: _openCurrentPreference,
        busy: _calibrationBusy,
        message: _error,
        syncStatus: _syncStatus,
        onBack: () => setState(() => _screen = _Screen.home),
      ),
      _Screen.feedback => FeedbackPage(
        key: ValueKey(_feedbackSession!.id),
        sessionId: _feedbackSession!.id,
        feedback: _feedbackDraft,
        onSave: _saveFeedback,
        message: _error,
        syncStatus: _syncStatus,
        onLater: _leaveFeedback,
      ),
      _Screen.preference => MeditationPreferencePage(
        choice: _preferenceChoice!,
        results: _preferenceResults,
        onChoose: _choosePreference,
        onAdditionalSeries: _additionalSeries,
        onBack: () => setState(() => _screen = _Screen.calibration),
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
        revealedPlans: _revealedPlans,
        onBack: () => setState(() => _screen = _Screen.history),
      ),
    };
  }
}
