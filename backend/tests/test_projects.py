"""Project storage integrity and authenticated API contracts (B1/B2)."""
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


@pytest.fixture
def project_api(tmp_path, monkeypatch):
    import hashlib
    import wave
    from fastapi.testclient import TestClient
    from app.auth import create_access_token
    from app.db import get_db
    from app.main import app

    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path / 'audio'))
    engine = create_engine(f"sqlite:///{tmp_path / 'api.db'}",
                           connect_args={'check_same_thread': False})
    Base.metadata.create_all(engine)
    project, other = seed(engine)
    source = project['recipe']['sources'][0]
    from app.audio import asset_path
    path = asset_path(project['owner_account_id'], source['asset_id'], 'canonical.wav')
    path.parent.mkdir(parents=True)
    with wave.open(str(path), 'wb') as audio:
        audio.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
        audio.writeframes(b'\0' * 48000 * 4)
    source['frame_count'] = 48000
    source['checksum_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    project['recipe']['clips'][0].update(start_frame=0, end_frame=48000)
    project['recipe']['frame_count'] = 48000
    with Session(engine) as db:
        asset = db.get(AudioAsset, source['asset_id'])
        asset.duration_seconds = 1
        asset.checksum_sha256 = source['checksum_sha256']
        db.commit()

    def get_test_db():
        with Session(engine, autoflush=False) as db:
            yield db

    app.dependency_overrides[get_db] = get_test_db
    headers = lambda uid: {'Authorization': f'Bearer {create_access_token(uid)}'}
    body = {key: copy.deepcopy(project[key]) for key in ('name', 'recipe', 'settings')}
    body.update(request_id=str(uuid.uuid4()), project_id=project['id'])
    yield TestClient(app), engine, body, headers(project['owner_account_id']), headers(other), path
    app.dependency_overrides.pop(get_db, None)
    engine.dispose()


PROJECTS = '/v1/audio/projects'


def saved_body(created, **changes):
    result = {key: copy.deepcopy(created[key]) for key in ('name', 'recipe', 'settings')}
    result.update(request_id=str(uuid.uuid4()), expected_revision=created['revision'])
    result.update(changes)
    return result


def test_api_create_reopen_list_and_retry_after_later_save(project_api):
    client, engine, body, owner, other, _ = project_api
    response = client.post(PROJECTS, json=body, headers=owner)
    assert response.status_code == 201, response.text
    first = response.json()
    assert first['revision'] == 1 and first['id'] == body['project_id']
    assert first['created_at'].endswith('Z') and first['updated_at'].endswith('Z')
    assert first['recipe'] == body['recipe']
    assert client.get(f"{PROJECTS}/{first['id']}", headers=owner).json() == first
    save = saved_body(first, name='Andra revisionen')
    second = client.put(f"{PROJECTS}/{first['id']}", json=save, headers=owner)
    assert second.status_code == 200, second.text
    second = second.json()
    third_save = saved_body(second, name='Senaste arbetet')
    third = client.put(f"{PROJECTS}/{first['id']}", json=third_save, headers=owner).json()
    engine.dispose()  # New DB connections, no process-local retry cache.
    assert client.post(PROJECTS, json=body, headers=owner).json() == first
    assert client.put(f"{PROJECTS}/{first['id']}", json=save, headers=owner).json() == second
    assert client.get(f"{PROJECTS}/{first['id']}", headers=owner).json() == third
    assert third['created_at'] == first['created_at'] and third['revision'] == 3
    assert client.get(PROJECTS, headers=owner).json() == {'items': [third], 'next_cursor': None}
    assert client.get(PROJECTS, headers=other).json()['items'] == []
    with Session(engine) as db:
        assert db.query(AudioProject).count() == 1
        assert db.query(AudioProjectRevision).count() == 3
        assert db.query(AudioProjectSourceReference).count() == 3
        assert db.query(AudioRender).count() == 0


def test_api_ownership_stale_revision_and_request_reuse(project_api):
    client, engine, body, owner, other, _ = project_api
    assert client.post(PROJECTS, json=body).status_code == 401
    first = client.post(PROJECTS, json=body, headers=owner).json()
    url = f"{PROJECTS}/{body['project_id']}"
    for method, payload in (('get', None), ('put', saved_body(first))):
        response = client.request(method, url, json=payload, headers=other)
        assert response.status_code == 404
    assert client.post(PROJECTS, json=body, headers=other).status_code == 404
    changed = body | {'name': 'Annat innehåll'}
    response = client.post(PROJECTS, json=changed, headers=owner)
    assert response.status_code == 409
    assert response.json()['detail']['code'] == 'REQUEST_ID_REUSE'
    different = body | {'project_id': str(uuid.uuid4())}
    assert client.post(PROJECTS, json=different, headers=owner).json()['detail']['code'] == 'REQUEST_ID_REUSE'
    save = saved_body(first)
    assert client.put(url, json=save, headers=owner).status_code == 200
    stale = saved_body(first, name='Gammal flik')
    response = client.put(url, json=stale, headers=owner)
    assert response.status_code == 409
    assert response.json()['detail'] == dict(code='REVISION_CONFLICT',
        message=response.json()['detail']['message'], project_id=first['id'],
        expected_revision=1, current_revision=2)
    assert client.put(url, json=save | {'name': 'Ändrad retry'}, headers=owner).json()['detail']['code'] == 'REQUEST_ID_REUSE'
    with Session(engine) as db:
        assert db.query(AudioProjectRevision).count() == 2


@pytest.mark.parametrize('change', ['unknown', 'foreign', 'pending', 'frames', 'checksum', 'missing', 'corrupt', 'truncated', 'format'])
def test_api_checks_real_source_before_writing(project_api, change):
    client, engine, body, owner, _, path = project_api
    source = body['recipe']['sources'][0]
    if change == 'unknown':
        source['asset_id'] = str(uuid.uuid4())
    elif change == 'foreign':
        with Session(engine) as db:
            source['asset_id'] = db.query(AudioAsset).filter(AudioAsset.id != source['asset_id']).one().id
    elif change == 'pending':
        with Session(engine) as db:
            db.get(AudioAsset, source['asset_id']).status = 'pending'
            db.commit()
    elif change == 'frames':
        source['frame_count'] += 1
    elif change == 'checksum':
        source['checksum_sha256'] = 'b' * 64
    elif change == 'missing':
        path.unlink()
    elif change == 'truncated':
        with path.open('r+b') as audio:
            audio.truncate(48)
    elif change == 'format':
        import struct
        with path.open('r+b') as audio:
            audio.seek(22)
            audio.write(struct.pack('<H', 1))
    else:
        # Same length/header, different samples: comparing client to DB is insufficient.
        with path.open('r+b') as audio:
            audio.seek(-2, 2)
            audio.write(b'\x01\x00')
    response = client.post(PROJECTS, json=body, headers=owner)
    assert response.status_code == (404 if change in ('unknown', 'foreign') else 422), response.text
    assert isinstance(response.json()['detail']['code'], str)
    assert str(path) not in response.text
    with Session(engine) as db:
        assert db.query(AudioProject).count() == 0
        assert db.query(AudioProjectRevision).count() == 0
        from app.models import AudioProjectRequest
        assert db.query(AudioProjectRequest).count() == 0


EDITOR_FIXTURE = json.loads((Path(__file__).resolve().parents[2]
                            / 'contracts/fixtures/audio_editor.json').read_text())


def changed_fixture(case):
    value = copy.deepcopy(EDITOR_FIXTURE['roots'][case['root']])
    for pointer, replacement in case.get('set', {}).items():
        parts = pointer.strip('/').split('/')
        target = value
        for part in parts[:-1]:
            target = target[int(part)] if isinstance(target, list) else target[part]
        key = int(parts[-1]) if isinstance(target, list) else parts[-1]
        target[key] = copy.deepcopy(replacement)
    if 'repeat_clips' in case:
        clip = value['clips'][0]
        value['clips'] = [copy.deepcopy(clip) | {'id': f'{1000+i:08x}-1111-4111-8111-111111111111'}
                          for i in range(case['repeat_clips'])]
    return value


@pytest.mark.parametrize('case', [c for c in EDITOR_FIXTURE['cases'] if c['root'] == 'sequence'],
                         ids=lambda c: c['name'])
def test_sequence_runtime_matches_approved_fixtures(case):
    from pydantic import ValidationError
    from app.projects import SequenceRecipe
    value = changed_fixture(case)
    if case['schema_valid'] and not case.get('semantic_error'):
        SequenceRecipe.model_validate(value)
    else:
        with pytest.raises(ValidationError) as error:
            SequenceRecipe.model_validate(value)
        if case.get('semantic_error'):
            assert case['semantic_error'] in str(error.value)


@pytest.mark.parametrize('mutation', ['trim', 'outside', 'unknown_source', 'total', 'gain',
    'boolean', 'string', 'fractional', 'schema_bool', 'blank', 'extra', 'policy'])
def test_api_rejects_invalid_edits_without_losing_latest_revision(project_api, mutation):
    client, engine, body, owner, _, _ = project_api
    first = client.post(PROJECTS, json=body, headers=owner).json()
    save = saved_body(first)
    clip = save['recipe']['clips'][0]
    if mutation == 'trim': clip['end_frame'] = 0
    elif mutation == 'outside': clip['end_frame'] = 48001
    elif mutation == 'unknown_source': clip['source_id'] = str(uuid.uuid4())
    elif mutation == 'total': save['recipe']['frame_count'] = 2
    elif mutation == 'gain': save['settings'].update(tone_gain=.5, background_gain=.5)
    elif mutation == 'boolean': clip['start_frame'] = False
    elif mutation == 'string': clip['start_frame'] = '0'
    elif mutation == 'fractional': clip['start_frame'] = .5
    elif mutation == 'schema_bool': save['recipe']['schema_version'] = True
    elif mutation == 'blank': save['name'] = ' \t\n'
    elif mutation == 'extra': save['owner_account_id'] = str(uuid.uuid4())
    elif mutation == 'policy': save['settings']['playback_policy']['maximum_minutes'] = 61
    response = client.put(f"{PROJECTS}/{first['id']}", json=save, headers=owner)
    assert response.status_code == 422, response.text
    assert isinstance(response.json()['detail']['message'], str)
    assert client.get(f"{PROJECTS}/{first['id']}", headers=owner).json() == first
    with Session(engine) as db:
        assert db.query(AudioProjectRevision).count() == 1


def test_api_pagination_is_account_bound_and_validated(project_api):
    client, _, body, owner, other, _ = project_api
    expected = []
    for i in range(3):
        body = body | dict(request_id=str(uuid.uuid4()), project_id=str(uuid.uuid4()), name=str(i))
        expected.insert(0, client.post(PROJECTS, json=body, headers=owner).json()['id'])
    first = client.get(PROJECTS, params={'limit': 2}, headers=owner).json()
    assert [p['id'] for p in first['items']] == expected[:2]
    assert first['next_cursor']
    last = client.get(PROJECTS, params={'limit': 2, 'cursor': first['next_cursor']}, headers=owner).json()
    assert [p['id'] for p in last['items']] == expected[2:]
    assert last['next_cursor'] is None
    for cursor, headers in ((first['next_cursor'], other), (first['next_cursor'] + 'x', owner), ('bad', owner)):
        assert client.get(PROJECTS, params={'cursor': cursor}, headers=headers).status_code == 422
    for limit in (0, 101):
        assert client.get(PROJECTS, params={'limit': limit}, headers=owner).status_code == 422


def test_api_concurrent_tabs_save_one_revision_and_keep_retry_receipt(project_api):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    client, engine, body, owner, _, _ = project_api
    first = client.post(PROJECTS, json=body, headers=owner).json()
    url = f"{PROJECTS}/{first['id']}"
    barrier = Barrier(2)
    edits = [saved_body(first, name=f'Flik {i}') for i in range(2)]

    def save(edit):
        barrier.wait(timeout=5)
        return client.put(url, json=edit, headers=owner)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(save, edits))
    assert sorted(r.status_code for r in results) == [200, 409]
    winner = next(r.json() for r in results if r.status_code == 200)
    losing_edit = edits[next(i for i, r in enumerate(results) if r.status_code == 409)]
    conflict = client.put(url, json=losing_edit, headers=owner)
    assert conflict.status_code == 409
    assert conflict.json()['detail']['code'] == 'REVISION_CONFLICT'
    assert client.get(url, headers=owner).json() == winner
    with Session(engine) as db:
        assert db.query(AudioProjectRevision).count() == 2


def test_api_inflight_request_returns_conflict_and_rolls_back(project_api):
    from app.models import AudioProjectRequest
    client, engine, body, owner, _, _ = project_api
    with Session(engine) as active:
        active.add(AudioProjectRequest(user_id=EDITOR_FIXTURE['roots']['project']['owner_account_id'],
            operation='create', request_id=body['request_id'], project_id=body['project_id'],
            payload_sha256='a' * 64, response_json='{}', created_at=datetime.now(UTC)))
        active.flush()  # A second connection must neither wait nor create a duplicate.
        response = client.post(PROJECTS, json=body, headers=owner)
        assert response.status_code == 409, response.text
        assert response.json()['detail']['code'] == 'REQUEST_IN_PROGRESS'
        active.rollback()
    assert client.post(PROJECTS, json=body, headers=owner).status_code == 201


def test_api_empty_and_unplaced_sources_remain_saved(project_api):
    client, engine, body, owner, _, _ = project_api
    body['recipe'].update(clips=[], frame_count=0)
    first = client.post(PROJECTS, json=body, headers=owner)
    assert first.status_code == 201
    with Session(engine) as db:
        assert db.query(AudioProjectSourceReference).count() == 1
    save = saved_body(first.json())
    save['recipe']['sources'] = []
    response = client.put(f"{PROJECTS}/{body['project_id']}", json=save, headers=owner)
    assert response.status_code == 200
    with Session(engine) as db:
        assert db.query(AudioProjectSourceReference).count() == 1  # older revision retains it


@pytest.mark.parametrize('mode', ['valid', 'foreign_profile', 'wrong_background'])
def test_api_profile_source_requires_matching_owned_background(project_api, mode):
    client, engine, body, owner, _, _ = project_api
    source = body['recipe']['sources'][0]
    uid = EDITOR_FIXTURE['roots']['project']['owner_account_id']
    vid, rid = str(uuid.uuid4()), str(uuid.uuid4())
    with Session(engine) as db:
        account = uid if mode != 'foreign_profile' else db.query(User).filter(User.id != uid).one().id
        digest = source['checksum_sha256'] if mode != 'wrong_background' else 'f' * 64
        db.add(AudioRender(id=rid, user_id=account, recipe_json='{}', status='ready',
            checksum_sha256=digest, created_at=datetime.now(UTC)))
        db.flush()
        db.add(AudioProfileVersion(id=vid, profile_id=str(uuid.uuid4()), user_id=account,
            version=1, render_id=rid, body_json=json.dumps(dict(schema_version=1,
                checksum_sha256=digest, duration_seconds=1)), created_at=datetime.now(UTC)))
        db.commit()
    source.update(kind='profile_background', profile_version_id=vid)
    response = client.post(PROJECTS, json=body, headers=owner)
    assert response.status_code == {'valid': 201, 'foreign_profile': 404, 'wrong_background': 422}[mode], response.text
    with Session(engine) as db:
        refs = db.query(AudioProjectSourceReference).all()
        assert len(refs) == (1 if mode == 'valid' else 0)
        if refs:
            assert refs[0].profile_version_id == vid and refs[0].kind == 'profile_background'


def test_api_hour_limit_uses_actual_header_and_accepts_exact_hour(project_api):
    import hashlib
    import struct
    client, engine, body, owner, _, path = project_api
    source = body['recipe']['sources'][0]
    header = bytearray(path.read_bytes()[:44])
    for frames in (172800000, 172800001):
        struct.pack_into('<I', header, 4, frames * 4 + 36)
        struct.pack_into('<I', header, 40, frames * 4)
        # Sparse real WAV: exercises streaming validation without a 691MB allocation.
        with path.open('wb') as stream:
            stream.write(header)
            stream.truncate(frames * 4 + 44)
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        with Session(engine) as db:
            asset = db.get(AudioAsset, source['asset_id'])
            asset.checksum_sha256 = digest
            asset.duration_seconds = frames / 48000
            db.commit()
        source.update(frame_count=172800000, checksum_sha256=digest)
        body['recipe']['clips'][0]['end_frame'] = 172800000
        body['recipe']['frame_count'] = 172800000
        body.update(request_id=str(uuid.uuid4()), project_id=str(uuid.uuid4()))
        response = client.post(PROJECTS, json=body, headers=owner)
        assert response.status_code == (201 if frames == 172800000 else 422), response.text


def test_api_failed_reference_write_rolls_back_head_and_receipt(project_api):
    from app.models import AudioProjectRequest
    client, engine, body, owner, _, _ = project_api
    first = client.post(PROJECTS, json=body, headers=owner).json()
    edit = saved_body(first, name='Ska sparas atomiskt')
    with engine.begin() as connection:
        connection.exec_driver_sql("CREATE TRIGGER fail_project_reference BEFORE INSERT ON audio_project_sources "
            "BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END")
    url = f"{PROJECTS}/{first['id']}"
    assert client.put(url, json=edit, headers=owner).status_code == 409
    assert client.get(url, headers=owner).json() == first
    with Session(engine) as db:
        assert db.query(AudioProjectRevision).count() == 1
        assert db.query(AudioProjectRequest).count() == 1
    with engine.begin() as connection:
        connection.exec_driver_sql('DROP TRIGGER fail_project_reference')
    assert client.put(url, json=edit, headers=owner).json()['revision'] == 2


@pytest.mark.parametrize('case', [c for c in EDITOR_FIXTURE['cases'] if c['name'] in (
    'gain-sum', 'exact-gain-boundary', 'gain-boundary-over', 'blank-project-name')], ids=lambda c: c['name'])
def test_project_contents_match_approved_fixtures(case):
    from pydantic import ValidationError
    from app.projects import ProjectContents
    value = changed_fixture(case)
    contents = {key: value[key] for key in ('name', 'recipe', 'settings')}
    if case['schema_valid'] and not case.get('semantic_error'):
        ProjectContents.model_validate(contents)
    else:
        with pytest.raises(ValidationError):
            ProjectContents.model_validate(contents)
