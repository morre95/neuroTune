import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:neurotune_core/neurotune_core.dart';
import '../platform/channels.dart';
import 'api_client.dart';
import 'canonical_wave.dart';
import 'database.dart';

class LocalAudioProfile {
  const LocalAudioProfile(this.profile, this.downloaded);
  final AudioProfileVersion profile;
  final bool downloaded;
}

class DownloadProgress {
  const DownloadProgress(this.received, this.total);
  final int received;
  final int total;
  double get fraction => (received / total).clamp(0, 1);
}

class _Transfer {
  final abort = Completer<void>();
  bool get cancelled => abort.isCompleted;
  void cancel() {
    if (!cancelled) abort.complete();
  }
}

/// Account-scoped mobile library. Readiness is published only after verification.
class ProfileLibrary extends ChangeNotifier {
  ProfileLibrary({
    required this.database,
    required this.api,
    required this.directory,
    required this.ownerAccountId,
    this.audio,
    this.audioBusy,
  }) : _generation = api.authGeneration {
    if (!isAccountUuid(ownerAccountId) ||
        (api.accountId != null && api.accountId != ownerAccountId)) {
      throw ArgumentError('Invalid account');
    }
  }
  final AppDatabase database;
  final ApiClient api;
  final Directory directory;
  final String ownerAccountId;
  final PcmOutput? audio;
  final bool Function()? audioBusy;
  final int _generation;
  var _closed = false;
  var _offline = false;
  String? _error;
  List<LocalAudioProfile> _profiles = [];
  final Map<String, _Transfer> _transfers = {};
  final Map<String, DownloadProgress> _progress = {};
  final Set<Future<void>> _jobs = {};
  _Transfer? _preview;
  Future<void>? _previewJob;
  String? _previewId;
  bool _previewStarted = false;
  bool get offline => _offline;
  String? get error => _error;
  String? get previewId => _previewId;
  bool get previewing => _preview != null;
  List<LocalAudioProfile> get profiles => List.unmodifiable(_profiles);
  Map<String, DownloadProgress> get progress => Map.unmodifiable(_progress);
  bool get _current => !_closed && api.authGeneration == _generation;
  void _check([_Transfer? transfer]) {
    if (!_current || (transfer?.cancelled ?? false)) {
      throw StateError('Transfer cancelled or account changed');
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Directory get _ownerDirectory =>
      Directory('${directory.path}/audio_profiles/$ownerAccountId');
  File _file(String id) {
    if (!isAccountUuid(id)) throw ArgumentError('Invalid version');
    return File('${_ownerDirectory.path}/$id.wav');
  }

  Future<List<CachedAudioProfile>> _rows() => (database.select(
    database.cachedAudioProfiles,
  )..where((t) => t.ownerAccountId.equals(ownerAccountId))).get();
  Future<void> _load() async {
    final rows = await _rows();
    final next = <LocalAudioProfile>[];
    for (final row in rows) {
      final p = AudioProfileVersion.fromJson(
        jsonDecode(row.metadataJson) as Map<String, dynamic>,
      );
      if (p.ownerAccountId != ownerAccountId || p.id != row.versionId) continue;
      var ready = false;
      if (row.readyPath != null) {
        try {
          await CanonicalWave.verify(
            _file(p.id),
            p.checksumSha256,
            p.durationSeconds,
          );
          ready = true;
        } catch (_) {
          await _clearReady(p.id);
          if (await _file(p.id).exists()) await _file(p.id).delete();
        }
      }
      next.add(LocalAudioProfile(p, ready));
    }
    _check();
    _profiles = next
      ..sort((a, b) => b.profile.version.compareTo(a.profile.version));
    _notify();
  }

  bool _networkSuspended = false;
  Future<void> loadCached() async {
    _check();
    await _ownerDirectory.create(recursive: true);
    await _load();
  }

  /// Join all HTTP work before a local session acquires audio. Cancellation
  /// releases streaming downloads; an already-issued metadata read is joined.
  Future<void> suspendNetwork() async {
    _networkSuspended = true;
    for (final transfer in _transfers.values) {
      transfer.cancel();
    }
    await stopPreview();
    for (final job in List<Future<void>>.of(_jobs)) {
      try {
        await job;
      } catch (_) {}
    }
  }

  void resumeNetwork() => _networkSuspended = false;
  Future<void> refresh() {
    if (_networkSuspended) return loadCached();
    final job = _refresh();
    _jobs.add(job);
    return job.whenComplete(() => _jobs.remove(job));
  }

  Future<void> _refresh() async {
    _check();
    await _ownerDirectory.create(recursive: true);
    // Orphaned temporary files after a process death can never be selected.
    if (_transfers.isEmpty && _preview == null) {
      await for (final item in _ownerDirectory.list()) {
        if (item is File && item.path.endsWith('.tmp')) await item.delete();
      }
    }
    await _load();
    try {
      final remote = await api.audioProfiles();
      _check();
      if (remote.any((p) => p.ownerAccountId != ownerAccountId)) {
        throw const FormatException('Profile account mismatch');
      }
      await database.transaction(() async {
        for (final p in remote) {
          _check();
          final existing =
              await (database.select(database.cachedAudioProfiles)..where(
                    (t) =>
                        t.ownerAccountId.equals(ownerAccountId) &
                        t.versionId.equals(p.id),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            if (existing.metadataJson != jsonEncode(p.toJson())) {
              throw const FormatException('Immutable profile changed');
            }
          } else {
            await database
                .into(database.cachedAudioProfiles)
                .insert(
                  CachedAudioProfilesCompanion.insert(
                    ownerAccountId: ownerAccountId,
                    versionId: p.id,
                    metadataJson: jsonEncode(p.toJson()),
                  ),
                );
          }
        }
        _check();
      });
      _offline = false;
      _error = null;
      await _load();
    } catch (e) {
      if (!_current) rethrow;
      _offline = true;
      _error = e.toString();
      _notify();
    }
  }

  AudioProfileVersion _profile(String id) =>
      _profiles.firstWhere((p) => p.profile.id == id).profile;
  Future<void> _clearReady(String id) =>
      (database.update(database.cachedAudioProfiles)..where(
            (t) =>
                t.ownerAccountId.equals(ownerAccountId) &
                t.versionId.equals(id),
          ))
          .write(const CachedAudioProfilesCompanion(readyPath: Value(null)))
          .then((_) {});
  Future<File?> playableFile(String id) async {
    _check();
    final item = _profiles
        .where((p) => p.profile.id == id && p.downloaded)
        .firstOrNull;
    if (item == null) return null;
    try {
      await CanonicalWave.verify(
        _file(id),
        item.profile.checksumSha256,
        item.profile.durationSeconds,
      );
      _check();
      return _file(id);
    } catch (_) {
      await _clearReady(id);
      if (_current) await _load();
      return null;
    }
  }

  Future<void> _fetch(
    AudioProfileVersion p,
    File temp,
    _Transfer transfer, {
    bool preview = false,
  }) async {
    final seconds = preview ? 30 : p.durationSeconds;
    final maximum = seconds * 192000 + 1048576;
    final response = await Future.any([
      api.audioProfileStream(
        p.id,
        preview: preview,
        abortTrigger: transfer.abort.future,
      ),
      transfer.abort.future.then<Never>(
        (_) => throw StateError('Transfer cancelled'),
      ),
    ]);
    _check(transfer);
    if (response.contentLength != null && response.contentLength! > maximum) {
      throw const FormatException('Oversized audio');
    }
    final output = await temp.open(mode: FileMode.write);
    var received = 0;
    final chunks = StreamIterator(response.stream.timeout(api.requestTimeout));
    try {
      while (await Future.any([
        chunks.moveNext(),
        transfer.abort.future.then<Never>(
          (_) => throw StateError('Transfer cancelled'),
        ),
      ])) {
        final bytes = chunks.current;
        _check(transfer);
        received += bytes.length;
        if (received > maximum) throw const FormatException('Oversized audio');
        await output.writeFrom(bytes);
        if (!preview) {
          _progress[p.id] = DownloadProgress(
            received,
            response.contentLength ?? seconds * 192000 + 44,
          );
          _notify();
        }
      }
      await output.flush();
    } finally {
      await chunks.cancel();
      await output.close();
    }
    _check(transfer);
    await CanonicalWave.verify(
      temp,
      preview ? p.previewChecksumSha256 : p.checksumSha256,
      seconds,
    );
    _check(transfer);
  }

  Future<void> download(String id) {
    if (_networkSuspended) throw StateError('Session is active');
    _check();
    if (_transfers.containsKey(id) ||
        _profiles.any((p) => p.profile.id == id && p.downloaded)) {
      throw StateError('Already downloaded or downloading');
    }
    final transfer = _Transfer();
    _transfers[id] = transfer;
    final job = _download(id, transfer);
    _jobs.add(job);
    job.then(
      (_) => _jobs.remove(job),
      onError: (Object e, StackTrace s) => _jobs.remove(job),
    );
    return job;
  }

  Future<void> _download(String id, _Transfer transfer) async {
    final p = _profile(id);
    final temp = File('${_file(id).path}.download.tmp');
    _progress[id] = const DownloadProgress(0, 1);
    _notify();
    try {
      await _ownerDirectory.create(recursive: true);
      await _fetch(p, temp, transfer);
      // The rename and row update are both guarded; a crash between them leaves an
      // unselectable orphan rather than a partial ready file.
      _check(transfer);
      await temp.rename(_file(id).path);
      _check(transfer);
      await (database.update(database.cachedAudioProfiles)..where(
            (t) =>
                t.ownerAccountId.equals(ownerAccountId) &
                t.versionId.equals(id),
          ))
          .write(
            CachedAudioProfilesCompanion(readyPath: Value(_file(id).path)),
          );
      _check(transfer);
      await _load();
      _check(transfer);
      _error = null;
    } catch (e) {
      await _clearReady(id);
      if (await _file(id).exists()) await _file(id).delete();
      if (_current) await _load();
      if (_current && !transfer.cancelled) _error = e.toString();
      rethrow;
    } finally {
      transfer.cancel();
      if (await temp.exists()) await temp.delete();
      _transfers.remove(id);
      _progress.remove(id);
      _notify();
    }
  }

  void cancelDownload(String id) {
    _transfers[id]?.cancel();
  }

  Future<void> removeLocal(String id) async {
    _check();
    if ((audioBusy?.call() ?? false) ||
        _transfers.containsKey(id) ||
        _previewId == id) {
      throw StateError('Audio is in use');
    }
    await _clearReady(id);
    final file = _file(id);
    if (await file.exists()) await file.delete();
    await _load();
  }

  Future<void> preview(String id) {
    if (_networkSuspended) throw StateError('Session is active');
    _check();
    if (audio == null || previewing || (audioBusy?.call() ?? false)) {
      throw StateError('Audio is busy');
    }
    final transfer = _Transfer();
    _preview = transfer;
    _previewId = id;
    _notify();
    final job = _playPreview(id, transfer);
    _previewJob = job;
    return job;
  }

  Future<void> _playPreview(String id, _Transfer transfer) async {
    final p = _profile(id);
    final temp = File('${_file(id).path}.preview.tmp');
    RandomAccessFile? input;
    try {
      await _ownerDirectory.create(recursive: true);
      final cached = await playableFile(id);
      final File source;
      if (cached != null) {
        source = cached;
      } else {
        await _fetch(p, temp, transfer, preview: true);
        source = temp;
      }
      final wave = await CanonicalWave.inspect(
        source,
        seconds: cached != null ? p.durationSeconds : 30,
      );
      _check(transfer);
      if (audioBusy?.call() ?? false) throw StateError('Audio is busy');
      _previewStarted = true;
      await audio!.start(48000);
      _check(transfer);
      input = await source.open();
      await input.setPosition(wave.dataOffset);
      final clock = Stopwatch()..start();
      var frames = 0;
      while (frames < 48000 * 30) {
        _check(transfer);
        final packet = await input.read(3840);
        if (packet.isEmpty) throw const FormatException('Truncated preview');
        await audio!.write(packet).timeout(const Duration(seconds: 2));
        frames += packet.length ~/ 4;
        final wait = frames * 1000000 ~/ 48000 - clock.elapsedMicroseconds;
        if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait));
      }
    } catch (e) {
      if (_current && !transfer.cancelled) {
        _error = e.toString();
        _notify();
      }
      rethrow;
    } finally {
      try {
        if (_previewStarted) await audio?.stop();
      } finally {
        _previewStarted = false;
        try {
          await input?.close();
          if (await temp.exists()) await temp.delete();
        } finally {
          transfer.cancel();
          _preview = null;
          _previewId = null;
          _notify();
        }
      }
    }
  }

  Future<void> stopPreview() async {
    _preview?.cancel();
    try {
      if (_previewStarted) await audio?.stop();
    } finally {
      try {
        await _previewJob;
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final transfer in _transfers.values) {
      transfer.cancel();
    }
    await stopPreview();
    await Future.wait([
      for (final job in _jobs.toList()) job.catchError((Object _) {}),
    ]);
    super.dispose();
  }
}
