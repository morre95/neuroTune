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

@DriftDatabase(tables: [StoredSessions, UploadJobs, KvStore])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'neurotune'));

  @override
  int get schemaVersion => 1;

  Future<void> putKv(String key, String value) async {
    await into(
      kvStore,
    ).insertOnConflictUpdate(KvStoreCompanion.insert(key: key, value: value));
  }

  Future<String?> getKv(String key) async {
    final row = await (select(
      kvStore,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }
}
