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

  Future<void> saveAuth(String json) => db.putKv('auth', json);

  Future<String?> loadAuth() => db.getKv('auth');

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
