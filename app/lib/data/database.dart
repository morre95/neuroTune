import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class StoredSessions extends Table {
  TextColumn get id => text()();
  TextColumn get origin => text()();
  TextColumn get mode => text()();
  TextColumn get manifestJson => text()();
  TextColumn get decisionsJson => text()();
  TextColumn get framesJson => text()();
  TextColumn get status => text()();
  TextColumn get checksum => text()();
  TextColumn get rawPath => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class UploadJobs extends Table {
  TextColumn get sessionId => text()();
  TextColumn get ownerEmail => text().nullable()();
  TextColumn get checksum => text()();
  TextColumn get payloadPath => text()();
  TextColumn get state => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId};
}

class KvStore extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class CachedAudioProfiles extends Table {
  TextColumn get ownerAccountId => text()();
  TextColumn get versionId => text()();
  TextColumn get metadataJson => text()();
  TextColumn get readyPath => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {ownerAccountId, versionId};
}

@DataClassName('StoredCalibrationPlan')
class CalibrationPlans extends Table {
  TextColumn get ownerAccountId => text()();
  TextColumn get id => text()();
  TextColumn get bodyJson => text()();
  TextColumn get syncState => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {ownerAccountId, id};
}

class CalibrationAttempts extends Table {
  TextColumn get ownerAccountId => text()();
  TextColumn get sessionId => text()();
  TextColumn get planId => text()();
  IntColumn get slot => integer()();
  TextColumn get state => text().withDefault(const Constant('reserved'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId};
}

class MeditationFeedbackRows extends Table {
  TextColumn get ownerAccountId => text()();
  TextColumn get sessionId => text()();
  IntColumn get mentalBusyness => integer().nullable()();
  IntColumn get relaxation => integer().nullable()();
  IntColumn get revision => integer()();
  TextColumn get syncState => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {ownerAccountId, sessionId};
}

@DriftDatabase(
  tables: [
    StoredSessions,
    UploadJobs,
    KvStore,
    CachedAudioProfiles,
    CalibrationPlans,
    CalibrationAttempts,
    MeditationFeedbackRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'neurotune'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(uploadJobs, uploadJobs.ownerEmail);
      if (from < 3) await m.createTable(cachedAudioProfiles);
      if (from < 4) {
        await m.createTable(calibrationPlans);
        await m.createTable(calibrationAttempts);
        await m.createTable(meditationFeedbackRows);
      }
    },
  );

  Future<void> putKv(String key, String value) async {
    await into(
      kvStore,
    ).insertOnConflictUpdate(KvStoreCompanion.insert(key: key, value: value));
  }

  Future<void> deleteKv(String key) async {
    await (delete(kvStore)..where((table) => table.key.equals(key))).go();
  }

  Future<String?> getKv(String key) async {
    final row = await (select(
      kvStore,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }
}
