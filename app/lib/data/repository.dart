import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:neurotune_core/neurotune_core.dart' hide UploadJob;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

class PendingUpload {
  PendingUpload({
    required this.sessionId,
    required this.ownerEmail,
    required this.checksum,
    required this.payloadPath,
    required this.attempts,
  });
  final String sessionId;
  final String? ownerEmail;
  final String checksum;
  final String payloadPath;
  final int attempts;
}

class SavedSession {
  SavedSession({
    required this.id,
    required this.origin,
    required this.mode,
    required this.manifest,
    required this.decisions,
    required this.frames,
    required this.status,
    required this.checksum,
    required this.createdAt,
  });

  final String id;
  final String origin;
  final String mode;
  final SessionManifest manifest;
  final List<DecisionEvent> decisions;
  final List<FeatureFrame> frames;
  final String status;
  final String checksum;
  final DateTime createdAt;
}

class SessionRepository {
  SessionRepository(this.db);
  final AppDatabase db;

  Future<void> saveConfig(ExperimentConfig config) =>
      db.putKv('config', jsonEncode(config.toJson()));

  Future<ExperimentConfig> loadConfig() async {
    final raw = await db.getKv('config');
    if (raw == null) return ExperimentConfig.defaults();
    return ExperimentConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Logins were kept in the database before they moved to encrypted storage.
  Future<String?> loadLegacyAuth() => db.getKv('auth');

  Future<void> deleteLegacyAuth() => db.deleteKv('auth');

  Future<void> saveBandit(BanditSnapshot snapshot) =>
      db.putKv('bandit:${snapshot.dataOrigin}', jsonEncode(snapshot.toJson()));

  Future<BanditSnapshot?> loadBandit(String origin) async {
    final raw = await db.getKv('bandit:$origin');
    if (raw == null) return null;
    return BanditSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> saveSession({
    required SessionManifest manifest,
    required List<DecisionEvent> decisions,
    required List<FeatureFrame> frames,
    required List<int> raw,
    required String checksum,
    required String status,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(directory.path, 'sessions'));
    await folder.create(recursive: true);
    final rawPath = p.join(folder.path, '${manifest.sessionId}.bin');
    await File(rawPath).writeAsBytes(raw);
    await db
        .into(db.storedSessions)
        .insertOnConflictUpdate(
          StoredSessionsCompanion.insert(
            id: manifest.sessionId,
            origin: manifest.dataOrigin,
            mode: manifest.mode,
            manifestJson: jsonEncode(manifest.toJson()),
            decisionsJson: jsonEncode([
              for (final decision in decisions) decision.toJson(),
            ]),
            framesJson: jsonEncode([
              for (final frame in frames) frame.toJson(),
            ]),
            status: status,
            checksum: checksum,
            rawPath: rawPath,
            createdAt: DateTime.now().toUtc(),
          ),
        );
    return rawPath;
  }

  Future<List<SavedSession>> listSessions() async {
    final rows = await (db.select(
      db.storedSessions,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();
    return rows.map(_saved).toList();
  }

  /// Only the account which owns the upload may request remote deletion.
  Future<List<SavedSession>> listOwnedSessions(String ownerEmail) async {
    final jobs = await (db.select(
      db.uploadJobs,
    )..where((row) => row.ownerEmail.equals(ownerEmail.toLowerCase()))).get();
    final ids = jobs.map((job) => job.sessionId).toSet();
    return (await listSessions())
        .where((session) => ids.contains(session.id))
        .toList();
  }

  /// Queue remote deletion in the same transaction that hides local sessions.
  /// Retain the raw path until cleanup succeeds, including across app restarts.
  Future<void> deleteSessions(
    List<String> sessionIds,
    String ownerEmail,
  ) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return;
    final owner = ownerEmail.toLowerCase();
    await db.transaction(() async {
      final jobs = await (db.select(
        db.uploadJobs,
      )..where((row) => row.sessionId.isIn(ids))).get();
      if (jobs.length != ids.length ||
          jobs.any((job) => job.ownerEmail != owner)) {
        throw StateError(
          'Du kan bara radera sessioner som tillhör ditt konto.',
        );
      }
      await (db.update(
        db.uploadJobs,
      )..where((row) => row.sessionId.isIn(ids))).write(
        const UploadJobsCompanion(
          state: Value('delete_pending'),
          attempts: Value(0),
          lastError: Value(null),
        ),
      );
      await (db.delete(
        db.storedSessions,
      )..where((row) => row.id.isIn(ids))).go();
      // Cached aggregates may still contain rewards from a deleted session.
      await (db.delete(
        db.kvStore,
      )..where((row) => row.key.like('bandit:%'))).go();
    });
    for (final job in await pendingDeletions(owner)) {
      if (ids.contains(job.sessionId)) {
        try {
          await _deleteRawFile(job.payloadPath);
        } on FileSystemException {
          // Keep the path in the persistent queue for the next cleanup attempt.
        }
      }
    }
  }

  Future<List<PendingUpload>> pendingDeletions(String ownerEmail) async {
    final rows =
        await (db.select(db.uploadJobs)..where(
              (row) =>
                  row.state.equals('delete_pending') &
                  row.ownerEmail.equals(ownerEmail.toLowerCase()),
            ))
            .get();
    return [
      for (final row in rows)
        PendingUpload(
          sessionId: row.sessionId,
          ownerEmail: row.ownerEmail,
          checksum: row.checksum,
          payloadPath: row.payloadPath,
          attempts: row.attempts,
        ),
    ];
  }

  Future<void> completeDeletion(PendingUpload job) async {
    await _deleteRawFile(job.payloadPath);
    await db.transaction(() async {
      await (db.delete(db.uploadJobs)..where(
            (row) =>
                row.sessionId.equals(job.sessionId) &
                row.state.equals('delete_pending') &
                row.ownerEmail.equals(job.ownerEmail!),
          ))
          .go();
      // A restart could have fetched an old policy before deletion synced.
      await (db.delete(
        db.kvStore,
      )..where((row) => row.key.like('bandit:%'))).go();
    });
  }

  Future<void> _deleteRawFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  Future<List<LocalSessionRewards>> localRewards(
    String origin,
    String experimentVersion,
  ) async {
    final sessions = await listSessions();
    return [
      for (final session in sessions)
        if (session.origin == origin &&
            session.manifest.experimentVersion == experimentVersion)
          LocalSessionRewards(
            sessionId: session.id,
            origin: DataOrigin.values.byName(session.origin),
            experimentVersion: experimentVersion,
            personal: session.mode == SessionMode.personal.name,
            rewards: [
              for (final decision in session.decisions)
                if (decision.updatedBandit && decision.reward != null)
                  LocalReward(
                    StimulusAction.byId(decision.action),
                    decision.reward!,
                  ),
            ],
          ),
    ];
  }

  Future<void> enqueueUpload(
    String sessionId,
    String checksum,
    String rawPath,
    String ownerEmail,
  ) {
    return db
        .into(db.uploadJobs)
        .insertOnConflictUpdate(
          UploadJobsCompanion.insert(
            sessionId: sessionId,
            ownerEmail: Value(ownerEmail.toLowerCase()),
            checksum: checksum,
            payloadPath: rawPath,
            state: 'pending',
          ),
        );
  }

  Future<List<PendingUpload>> pendingUploads() async {
    final rows = await (db.select(
      db.uploadJobs,
    )..where((table) => table.state.equals('pending'))).get();
    return [
      for (final row in rows)
        PendingUpload(
          sessionId: row.sessionId,
          ownerEmail: row.ownerEmail,
          checksum: row.checksum,
          payloadPath: row.payloadPath,
          attempts: row.attempts,
        ),
    ];
  }

  Future<void> claimLegacyUploads(String ownerEmail) async {
    await (db.update(
      db.uploadJobs,
    )..where((table) => table.ownerEmail.isNull())).write(
      UploadJobsCompanion(ownerEmail: Value(ownerEmail.toLowerCase())),
    );
  }

  Future<void> markUpload(
    String sessionId,
    String state, {
    int? attempts,
    String? error,
  }) {
    return (db.update(
      db.uploadJobs,
    )..where((table) => table.sessionId.equals(sessionId))).write(
      UploadJobsCompanion(
        state: Value(state),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        lastError: Value(error),
      ),
    );
  }

  SavedSession _saved(StoredSession row) {
    return SavedSession(
      id: row.id,
      origin: row.origin,
      mode: row.mode,
      manifest: SessionManifest.fromJson(
        jsonDecode(row.manifestJson) as Map<String, dynamic>,
      ),
      decisions: [
        for (final item in jsonDecode(row.decisionsJson) as List<dynamic>)
          DecisionEvent.fromJson(item as Map<String, dynamic>),
      ],
      frames: [
        for (final item in jsonDecode(row.framesJson) as List<dynamic>)
          FeatureFrame.fromJson(item as Map<String, dynamic>),
      ],
      status: row.status,
      checksum: row.checksum,
      createdAt: row.createdAt,
    );
  }
}
