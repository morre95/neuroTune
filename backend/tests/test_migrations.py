import hashlib
import io
import json
import wave
from datetime import UTC, datetime
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings


def test_session_deletion_migration_preserves_existing_schema(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setattr(settings, "database_url", url)
    config = Config("alembic.ini")
    command.upgrade(config, "001_initial")
    db = create_engine(url)
    assert "session_deletions" not in inspect(db).get_table_names()
    command.upgrade(config, "head")
    schema = inspect(db)
    assert "sessions" in schema.get_table_names()
    assert "session_deletions" in schema.get_table_names()
    assert schema.get_pk_constraint("session_deletions")["constrained_columns"] == ["user_id", "session_id"]
    db.dispose()


def test_single_active_migration_clears_duplicate_active_experiments(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setattr(settings, "database_url", url)
    config = Config("alembic.ini")
    command.upgrade(config, "002_session_deletions")
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(
            text("INSERT INTO experiments (id, version, body, active) VALUES ('a', '1', '{}', true), ('b', '2', '{}', true)")
        )
    command.upgrade(config, "head")
    with db.connect() as connection:
        active = connection.execute(text("SELECT count(*) FROM experiments WHERE active")).scalar_one()
        assert active == 0
        with pytest.raises(IntegrityError):
            connection.execute(text("UPDATE experiments SET active = true"))
    command.downgrade(config, "002_session_deletions")
    db.dispose()


def test_meditation_sync_migration_preserves_legacy_and_durable_revision_queues(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'meditation-migration.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    config = Config('alembic.ini')
    command.upgrade(config, '005_audio_profiles')
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(text("INSERT INTO users (id,email,password_hash,created_at) VALUES ('legacy','legacy@test','hash','2026-01-01')"))
        connection.execute(text("INSERT INTO sessions (id,user_id,checksum,origin,experiment_version,manifest_json,decisions_json,frames_json,raw_path,created_at) VALUES ('old','legacy','checksum','muse','old-version','{}','[]','[]','original.bin','2026-01-01')"))
    command.upgrade(config, 'head')
    schema = inspect(db)
    assert {'calibration_plans', 'meditation_feedback', 'meditation_training_jobs', 'meditation_training_requests'}.issubset(schema.get_table_names())
    with db.connect() as connection:
        assert connection.execute(text("SELECT raw_path FROM sessions WHERE id='old'")).scalar_one() == 'original.bin'
    command.downgrade(config, '005_audio_profiles')
    assert 'meditation_feedback' not in inspect(db).get_table_names()
    db.dispose()


def test_meditation_deletion_migration_scrubs_preexisting_deleted_evidence_and_keeps_retained_data(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'deletion-migration.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    config = Config('alembic.ini')
    command.upgrade(config, '006_meditation_sync')
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(text("INSERT INTO users VALUES ('owner','owner@test','hash','2026-01-01')"))
        connection.execute(text("INSERT INTO session_deletions VALUES ('owner','deleted',NULL,'2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_feedback VALUES ('owner','deleted',1,'{}','2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_training_jobs VALUES ('old-job','owner','muse','meditation-1','old','[{\"session_id\":\"deleted\"}]','queued',NULL,'2026-01-01'), ('kept-job','owner','simulator','meditation-1','kept','[{\"session_id\":\"kept\"}]','queued',NULL,'2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_training_requests VALUES ('old-request','owner','old-job','{\"session_id\":\"deleted\"}')"))
    command.upgrade(config, 'head')
    with db.connect() as connection:
        assert connection.execute(text('SELECT count(*) FROM meditation_feedback')).scalar_one() == 0
        assert connection.execute(text('SELECT id FROM meditation_training_jobs')).scalars().all() == ['kept-job']
        assert connection.execute(text('SELECT count(*) FROM meditation_training_requests')).scalar_one() == 0
        assert connection.execute(text('SELECT epoch FROM owner_deletion_epochs')).scalar_one() == 1
        assert connection.execute(text('SELECT count(*) FROM session_deletions')).scalar_one() == 1
    command.downgrade(config, '006_meditation_sync')
    assert 'owner_deletion_epochs' not in inspect(db).get_table_names()
    db.dispose()


def test_personal_model_migration_follows_reviewed_deletion_epoch_and_preserves_jobs(tmp_path,monkeypatch):
    url=f"sqlite:///{tmp_path/'model.db'}"
    monkeypatch.setattr(settings,'database_url',url)
    config=Config('alembic.ini')
    command.upgrade(config,'007_meditation_deletions')
    db=create_engine(url)
    command.upgrade(config,'head')
    schema=inspect(db)
    assert 'personal_eeg_models' in schema.get_table_names()
    fk=[fk for fk in schema.get_foreign_keys('personal_eeg_models') if fk['referred_table']=='meditation_training_jobs'][0]
    assert fk['options']['ondelete']=='SET NULL'
    command.downgrade(config,'007_meditation_deletions')
    assert 'personal_eeg_models' not in inspect(db).get_table_names()
    assert 'meditation_training_jobs' in inspect(db).get_table_names()
    db.dispose()


def test_audio_projects_upgrade_preserves_legacy_profile_and_can_reopen_project(tmp_path, monkeypatch):
    from app.models import AudioProject, AudioProjectRevision, AudioProjectSourceReference
    from app.profiles import ProfileVersion

    url = f"sqlite:///{tmp_path / 'projects-upgrade.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    config = Config('alembic.ini')
    command.upgrade(config, '008_personal_eeg_models')
    fixture = json.loads((Path(__file__).resolve().parents[2]
                          / 'contracts/fixtures/audio_editor.json').read_text())['roots']['project']
    owner = fixture['owner_account_id']
    asset_id = fixture['recipe']['sources'][0]['asset_id']
    # Real canonical legacy audio and a parser-valid schema-1 profile. The
    # migration must preserve the exact metadata string and published checksum.
    audio = tmp_path / 'legacy.wav'
    with wave.open(str(audio), 'wb') as wav:
        wav.setparams((2, 2, 48000, 0, 'NONE', ''))
        wav.writeframes(bytes(30 * 192000))
    checksum = hashlib.sha256(audio.read_bytes()).hexdigest()
    fixture['recipe']['sources'][0].update(frame_count=30 * 48000, checksum_sha256=checksum)
    fixture['recipe']['clips'][0]['end_frame'] = 30 * 48000
    fixture['recipe']['frame_count'] = 30 * 48000
    profile = dict(schema_version=1, id='11111111-1111-4111-8111-111111111111',
        owner_account_id=owner, profile_id='22222222-2222-4222-8222-222222222222',
        version=1, name='Äldre profil', background_asset_id='33333333-3333-4333-8333-333333333333',
        recipe=dict(schema_version=1, duration_seconds=30,
            tracks=[dict(asset_id=asset_id, trim_end_seconds=30)]),
        carrier_hz=220, tone_gain=.2, background_gain=.6, loop=True,
        duration_seconds=30, normalization_factor=1,
        checksum_sha256=checksum, preview_checksum_sha256=checksum,
        sample_rate_hz=48000, channels=2, sample_width_bytes=2,
        created_at='2026-01-01T00:00:00Z')
    assert ProfileVersion.model_validate(profile).duration_seconds == 30
    original_body = json.dumps(profile, ensure_ascii=False, indent=2)
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(text('INSERT INTO users VALUES (:id,:email,:password,:created)'),
            dict(id=owner, email='legacy@test.invalid', password='unused', created='2026-01-01'))
        connection.execute(text('INSERT INTO audio_assets '
            '(id,user_id,schema_version,filename,source_format,status,original_bytes,original_sha256,'
            'checksum_sha256,duration_seconds,source_channels,created_at) '
            'VALUES (:id,:owner,1,\'legacy.wav\',\'wav\',\'ready\',:size,:hash,:hash,30,2,\'2026-01-01\')'),
            dict(id=asset_id, owner=owner, size=audio.stat().st_size, hash=checksum))
        connection.execute(text('INSERT INTO audio_renders '
            '(id,user_id,recipe_json,status,progress,normalization_factor,checksum_sha256,preview_checksum_sha256,created_at) '
            'VALUES (:id,:owner,:recipe,\'ready\',1,1,:hash,:hash,\'2026-01-01\')'),
            dict(id=profile['background_asset_id'], owner=owner, recipe=json.dumps(profile['recipe']), hash=checksum))
        connection.execute(text('INSERT INTO audio_profile_versions '
            '(id,profile_id,user_id,version,render_id,body_json,created_at) '
            'VALUES (:id,:profile,:owner,1,:render,:body,\'2026-01-01\')'),
            dict(id=profile['id'], profile=profile['profile_id'], owner=owner,
                 render=profile['background_asset_id'], body=original_body))
        before = {table: connection.execute(text('SELECT * FROM ' + table)).all()
                  for table in ('users', 'audio_assets', 'audio_renders', 'audio_profile_versions')}
    command.upgrade(config, 'head')
    with db.connect() as connection:
        for table, rows in before.items():
            assert connection.execute(text('SELECT * FROM ' + table)).all() == rows
        assert connection.execute(text('PRAGMA foreign_key_check')).all() == []
    with Session(db) as session:
        now = datetime.now(UTC)
        session.add(AudioProject(id=fixture['id'], user_id=owner, revision=1,
            created_at=now, updated_at=now))
        session.flush()
        session.add(AudioProjectRevision(project_id=fixture['id'], user_id=owner,
            revision=1, name='Sparat efter uppgradering', recipe_json=json.dumps(fixture['recipe']),
            settings_json=json.dumps(fixture['settings']), created_at=now))
        session.flush()
        session.add(AudioProjectSourceReference(project_id=fixture['id'], user_id=owner,
            revision=1, source_id=fixture['recipe']['sources'][0]['id'], asset_id=asset_id, kind='asset'))
        session.commit()
    db.dispose()
    reopened = create_engine(url)
    with Session(reopened) as session:
        saved = session.get(AudioProjectRevision, (fixture['id'], 1))
        assert saved.name == 'Sparat efter uppgradering'
        assert json.loads(saved.recipe_json) == fixture['recipe']
    # Reverting the additive migration removes only new storage/indexes.
    command.downgrade(config, '008_personal_eeg_models')
    assert 'audio_projects' not in inspect(reopened).get_table_names()
    with reopened.connect() as connection:
        assert connection.execute(text('SELECT body_json FROM audio_profile_versions')).scalar_one() == original_body
        assert connection.execute(text('SELECT checksum_sha256 FROM audio_renders')).scalar_one() == checksum
    assert hashlib.sha256(audio.read_bytes()).hexdigest() == checksum
    reopened.dispose()


def test_audio_projects_migration_compiles_for_postgresql_without_rewriting_legacy(monkeypatch):
    monkeypatch.setattr(settings, 'database_url', 'postgresql+psycopg://unused@localhost/unused')
    output = io.StringIO()
    config = Config('alembic.ini', output_buffer=output)
    command.upgrade(config, '008_personal_eeg_models:009_audio_projects', sql=True)
    sql = output.getvalue()
    assert 'CREATE TABLE audio_projects' in sql
    assert 'CREATE TABLE audio_project_revisions' in sql
    assert 'CREATE TABLE audio_project_sources' in sql
    assert 'FOREIGN KEY(asset_id, user_id) REFERENCES audio_assets (id, user_id) ON DELETE RESTRICT' in sql
    assert 'FOREIGN KEY(profile_version_id, user_id) REFERENCES audio_profile_versions (id, user_id) ON DELETE RESTRICT' in sql
    assert 'CREATE UNIQUE INDEX uq_audio_assets_id_user' in sql
    assert 'ALTER TABLE audio_assets' not in sql
    assert 'UPDATE audio_' not in sql
