import 'dart:convert';
import 'package:drift/native.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';

void main() {
  test(
    'version 2 sessions remain readable after the profile-cache migration',
    () async {
      final config = ExperimentConfig.defaults();
      final manifest = SessionEngine(
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.muse,
        ),
        sessionId: 'legacy-session',
        origin: DataOrigin.muse,
        mode: SessionMode.personal,
        eyeState: EyeState.open,
        sampleRateHz: 256,
        channelNames: ['EEG1'],
        seed: 1,
        startedAt: DateTime.utc(2026),
      ).manifest();
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE stored_sessions (id TEXT NOT NULL PRIMARY KEY, origin TEXT NOT NULL, mode TEXT NOT NULL, manifest_json TEXT NOT NULL, decisions_json TEXT NOT NULL, frames_json TEXT NOT NULL, status TEXT NOT NULL, checksum TEXT NOT NULL, raw_path TEXT NOT NULL, created_at INTEGER NOT NULL)',
            );
            sqlite.execute(
              'CREATE TABLE upload_jobs (session_id TEXT NOT NULL PRIMARY KEY, owner_email TEXT, checksum TEXT NOT NULL, payload_path TEXT NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
            );
            sqlite.execute(
              'CREATE TABLE kv_store (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
            );
            sqlite.execute(
              'INSERT INTO stored_sessions VALUES (?,?,?,?,?,?,?,?,?,?)',
              [
                'legacy-session',
                'muse',
                'personal',
                jsonEncode(manifest.toJson()),
                '[]',
                '[]',
                'completed',
                'checksum',
                '/tmp/legacy.bin',
                1767225600,
              ],
            );
            sqlite.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(database.close);
      final old = (await SessionRepository(database).listSessions()).single;
      expect(old.id, 'legacy-session');
      expect(old.manifest.eyeState, 'open');
      expect(old.manifest.experimentVersion, config.version);
      await database.putKv('old-settings', 'preserved');
      expect(await database.getKv('old-settings'), 'preserved');
    },
  );

  test('new upload jobs retain their account owner', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SessionRepository(database);

    await repository.enqueueUpload(
      'session-1',
      'checksum',
      '/tmp/session.bin',
      'Person@Example.com',
    );

    expect(
      (await repository.pendingUploads()).single.ownerEmail,
      'person@example.com',
    );
  });

  test('version 1 upload jobs survive the owner migration', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE upload_jobs (
              session_id TEXT NOT NULL PRIMARY KEY,
              checksum TEXT NOT NULL,
              payload_path TEXT NOT NULL,
              state TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT
            )
          ''');
          sqlite.execute('''
            INSERT INTO upload_jobs
            (session_id, checksum, payload_path, state)
            VALUES ('legacy', 'checksum', '/tmp/legacy.bin', 'pending')
          ''');
          sqlite.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(database.close);
    final repository = SessionRepository(database);

    await repository.claimLegacyUploads('Person@Example.com');
    final jobs = await repository.pendingUploads();

    expect(jobs, hasLength(1));
    expect(jobs.single.sessionId, 'legacy');
    expect(jobs.single.ownerEmail, 'person@example.com');
  });
}
