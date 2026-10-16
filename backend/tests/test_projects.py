"""Persistence/integrity tests for B1. HTTP validation belongs to B2."""
import copy
import json
import uuid
from datetime import UTC, datetime
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.db import Base
from app.models import (AudioAsset, AudioProfileVersion, AudioProject,
                        AudioProjectRevision, AudioProjectSourceReference,
                        AudioRender, User)


@pytest.fixture(params=['metadata', 'migration'])
def storage(tmp_path, monkeypatch, request):
    url = f"sqlite:///{tmp_path / 'projects.db'}"
    if request.param == 'migration':
        monkeypatch.setattr(settings, 'database_url', url)
        command.upgrade(Config('alembic.ini'), 'head')
    engine = create_engine(url)
    if request.param == 'metadata':
        Base.metadata.create_all(engine)
    yield engine
    engine.dispose()


def seed(engine):
    fixture = json.loads((Path(__file__).resolve().parents[2]
                          / 'contracts/fixtures/audio_editor.json').read_text())
    project = copy.deepcopy(fixture['roots']['project'])
    owner, other = project['owner_account_id'], str(uuid.uuid4())
    source = project['recipe']['sources'][0]
    now = datetime.now(UTC)
    with Session(engine) as db:
        db.add_all([User(id=uid, email=f'{uid}@test.invalid', password_hash='unused',
                         created_at=now) for uid in (owner, other)])
        db.flush()
        for uid, aid in ((owner, source['asset_id']), (other, str(uuid.uuid4()))):
            db.add(AudioAsset(id=aid, user_id=uid, filename='canonical.wav',
                source_format='wav', status='ready', original_bytes=44,
                original_sha256='a' * 64, checksum_sha256=source['checksum_sha256'],
                duration_seconds=3600, source_channels=2, created_at=now))
        db.commit()
    return project, other


def save_first(db, project):
    now = datetime.now(UTC)
    db.add(AudioProject(id=project['id'], user_id=project['owner_account_id'],
        revision=1, created_at=now, updated_at=now))
    db.flush()
    db.add(AudioProjectRevision(project_id=project['id'],
        user_id=project['owner_account_id'], revision=1, name=project['name'],
        recipe_json=json.dumps(project['recipe']),
        settings_json=json.dumps(project['settings']), created_at=now))
    db.flush()


def reference(project, *, revision=1, **changes):
    source = project['recipe']['sources'][0]
    values = dict(project_id=project['id'],
        user_id=project['owner_account_id'], revision=revision,
        source_id=source['id'], asset_id=source['asset_id'], kind='asset',
        profile_version_id=None)
    values.update(changes)
    return AudioProjectSourceReference(**values)


def test_reopen_revisions_and_unplaced_sources_without_rendering(storage):
    project, _ = seed(storage)
    # Unplaced sources are retained even by an otherwise empty draft.
    project['recipe']['clips'] = []
    project['recipe']['frame_count'] = 0
    with Session(storage) as db:
        save_first(db, project)
        db.add(reference(project))
        db.commit()
    # Dispose the pool and open a completely new engine against the same file.
    storage.dispose()
    reopened = create_engine(storage.url)
    try:
        with Session(reopened) as db:
            assert db.execute(text('PRAGMA foreign_keys')).scalar_one() == 1
            head = db.get(AudioProject, project['id'])
            revision = db.get(AudioProjectRevision, (head.id, head.revision))
            assert head.user_id == project['owner_account_id']
            assert json.loads(revision.recipe_json) == project['recipe']
            assert json.loads(revision.settings_json) == project['settings']
            assert revision.name == project['name']
            assert db.query(AudioProjectSourceReference).count() == 1
            assert db.execute(text('SELECT count(*) FROM audio_renders')).scalar_one() == 0
            head.revision = 2
            db.add(AudioProjectRevision(project_id=head.id, user_id=head.user_id,
                revision=2, name='Ny revision', recipe_json=revision.recipe_json,
                settings_json=revision.settings_json, created_at=datetime.now(UTC)))
            db.flush()
            db.add(reference(project, revision=2))
            db.commit()
        with Session(reopened) as db:
            assert db.get(AudioProject, project['id']).revision == 2
            assert db.get(AudioProjectRevision, (project['id'], 1)).name == project['name']
            assert db.get(AudioProjectRevision, (project['id'], 2)).name == 'Ny revision'
            assert sorted(row.revision for row in db.query(AudioProjectSourceReference)) == [1, 2]
    finally:
        reopened.dispose()


def test_reference_prevents_cleanup_of_asset_even_after_new_revision(storage):
    project, _ = seed(storage)
    with Session(storage) as db:
        save_first(db, project)
        db.add(reference(project))
        db.commit()
        db.execute(text('UPDATE audio_projects SET revision=2 WHERE id=:id'),
                   {'id': project['id']})
        empty_recipe = copy.deepcopy(project['recipe'])
        empty_recipe.update(sources=[], clips=[], frame_count=0)
        db.add(AudioProjectRevision(project_id=project['id'],
            user_id=project['owner_account_id'], revision=2, name='Tom revision',
            recipe_json=json.dumps(empty_recipe),
            settings_json=json.dumps(project['settings']), created_at=datetime.now(UTC)))
        db.commit()
        with pytest.raises(IntegrityError):
            db.execute(text('DELETE FROM audio_assets WHERE id=:id'),
                       {'id': project['recipe']['sources'][0]['asset_id']})
        db.rollback()
        assert db.query(AudioAsset).count() == 2


def test_shared_audio_stays_until_last_project_reference_is_released(storage):
    project, _ = seed(storage)
    second = copy.deepcopy(project)
    second['id'] = str(uuid.uuid4())
    asset_id = project['recipe']['sources'][0]['asset_id']
    with Session(storage) as db:
        for draft in (project, second):
            save_first(db, draft)
            db.add(reference(draft))
        db.commit()
        db.execute(text('DELETE FROM audio_projects WHERE id=:id'), {'id': project['id']})
        db.commit()
        assert db.query(AudioProjectSourceReference).count() == 1
        with pytest.raises(IntegrityError):
            db.execute(text('DELETE FROM audio_assets WHERE id=:id'), {'id': asset_id})
        db.rollback()
        db.execute(text('DELETE FROM audio_projects WHERE id=:id'), {'id': second['id']})
        db.commit()
        assert db.query(AudioProjectSourceReference).count() == 0
        # Releasing a reference never deletes a file/asset by itself.
        assert db.get(AudioAsset, asset_id) is not None
        db.execute(text('DELETE FROM audio_assets WHERE id=:id'), {'id': asset_id})
        db.commit()
        assert db.query(AudioAsset).count() == 1


def test_foreign_source_or_revision_owner_cannot_be_attached(storage):
    project, other = seed(storage)
    with Session(storage) as db:
        save_first(db, project)
        db.commit()
        foreign_asset = db.query(AudioAsset).filter_by(user_id=other).one()
        db.add(reference(project, asset_id=foreign_asset.id))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        db.add(AudioProjectRevision(project_id=project['id'], user_id=other,
            revision=2, name='Fel konto', recipe_json='{}', settings_json='{}',
            created_at=datetime.now(UTC)))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


def test_failed_reference_rolls_back_head_revision_and_new_recipe(storage):
    project, other = seed(storage)
    with Session(storage) as db:
        save_first(db, project)
        db.add(reference(project))
        db.commit()
        head = db.get(AudioProject, project['id'])
        head.revision = 2
        db.add(AudioProjectRevision(project_id=head.id, user_id=head.user_id,
            revision=2, name='Ska rullas tillbaka', recipe_json='{}',
            settings_json='{}', created_at=datetime.now(UTC)))
        db.flush()
        foreign_asset = db.query(AudioAsset).filter_by(user_id=other).one()
        db.add(reference(project, revision=2, asset_id=foreign_asset.id))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.get(AudioProject, project['id']).revision == 1
        assert db.get(AudioProjectRevision, (project['id'], 2)) is None
        assert db.query(AudioProjectSourceReference).count() == 1


def test_profile_source_retains_original_version_and_rejects_foreign_provenance(storage):
    project, other = seed(storage)
    versions = []
    with Session(storage) as db:
        for owner in (project['owner_account_id'], other):
            render_id, version_id = str(uuid.uuid4()), str(uuid.uuid4())
            db.add(AudioRender(id=render_id, user_id=owner, recipe_json='{}',
                status='ready', progress=1, checksum_sha256='a' * 64,
                created_at=datetime.now(UTC)))
            db.flush()
            # The persistence layer retains opaque legacy metadata; validation
            # of a usable, matching background is the B2 API boundary's job.
            db.add(AudioProfileVersion(id=version_id, profile_id=str(uuid.uuid4()),
                user_id=owner, version=1, render_id=render_id,
                body_json='{"schema_version":1}', created_at=datetime.now(UTC)))
            versions.append(version_id)
        save_first(db, project)
        db.commit()
        db.add(reference(project, kind='profile_background', profile_version_id=versions[1]))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        db.add(reference(project, kind='profile_background', profile_version_id=versions[0]))
        db.commit()
        with pytest.raises(IntegrityError):
            db.execute(text('DELETE FROM audio_profile_versions WHERE id=:id'), {'id': versions[0]})
        db.rollback()
        assert db.get(AudioProfileVersion, versions[0]).body_json == '{"schema_version":1}'


@pytest.mark.parametrize('changes', [
    {'kind': 'profile_background'},
    {'kind': 'asset', 'profile_version_id': str(uuid.uuid4())},
    {'kind': 'unknown'},
    {'revision': 2},
])
def test_source_requires_valid_kind_provenance_and_existing_revision(storage, changes):
    project, _ = seed(storage)
    with Session(storage) as db:
        save_first(db, project)
        db.commit()
        db.add(reference(project, **changes))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.query(AudioProjectSourceReference).count() == 0


@pytest.mark.parametrize('changes', [
    {'schema_version': 2}, {'revision': 0}, {'revision': 9007199254740992},
])
def test_project_head_constraints_match_contract(storage, changes):
    project, _ = seed(storage)
    now = datetime.now(UTC)
    values = dict(id=project['id'], user_id=project['owner_account_id'],
                  schema_version=1, revision=1, created_at=now, updated_at=now)
    values.update(changes)
    with Session(storage) as db:
        db.add(AudioProject(**values))
        with pytest.raises(IntegrityError):
            db.commit()
