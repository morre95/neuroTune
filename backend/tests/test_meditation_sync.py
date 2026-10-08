import base64
import hashlib
import uuid
from datetime import UTC, datetime

from app.config import settings
from app.db import SessionLocal
from app.worker import run_once
from test_api import auth, client, register
from test_profiles import source, ready_render


def context(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path / 'audio'))
    monkeypatch.setattr(settings, 'raw_data_dir', str(tmp_path / 'raw'))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset = source(token)
    render = ready_render(token, asset)
    response = client.post('/v1/audio/profiles', headers=auth(token), json={'name': 'Rain', 'render_id': render})
    assert response.status_code == 201, response.text
    profile = response.json()
    plan = dict(schema_version=1, id=str(uuid.uuid4()), owner_account_id=profile['owner_account_id'],
        protocol_version='meditation-1', profile_version_id=profile['id'], profile=profile,
        eye_state='closed', origin='muse', duration_seconds=600,
        schedule=['control', 'binaural_6', 'binaural_8', 'binaural_10', 'binaural_12'] * 2,
        created_at=datetime.now(UTC).isoformat().replace('+00:00', 'Z'))
    return token, profile, plan


def test_owned_immutable_plan_survives_identical_retry_and_refuses_reschedule(tmp_path, monkeypatch):
    token, _, plan = context(tmp_path, monkeypatch)
    endpoint = '/v1/meditation/calibration-plans'
    first = client.post(endpoint, headers=auth(token), json=plan)
    assert first.status_code == 201, first.text
    assert client.post(endpoint, headers=auth(token), json=plan).status_code == 200
    changed = plan | {'schedule': list(reversed(plan['schedule']))}
    assert client.post(endpoint, headers=auth(token), json=changed).status_code == 409
    assert client.get(f"{endpoint}/{plan['id']}", headers=auth(token)).json() == plan
    assert client.get(endpoint, headers=auth(token)).json() == [plan]
    other = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.get(f"{endpoint}/{plan['id']}", headers=auth(other)).status_code == 404
    assert client.post(endpoint, headers=auth(other), json=plan).status_code in {403, 404}
    assert client.get(endpoint).status_code == 401


def recording(profile, plan=None, **changes):
    sid = str(uuid.uuid4())
    raw = b'unchanged-meditation-eeg'
    meta = dict(schema_version=1, protocol_version='meditation-1', mode='fixed', profile=profile,
        profile_version_id=profile['id'], fixed_action='control', owner_account_id=profile['owner_account_id'],
        eye_state='closed', origin='muse', played_frames=28800000, quality_version='eeg-1')
    if plan:
        meta.update(mode='calibration', calibration_plan_id=plan['id'], calibration_slot=0, calibration_schema_version=1)
    meta.update(changes)
    manifest = dict(session_id=sid, experiment_version='meditation-1', data_origin='muse', mode='meditation',
        eye_state='closed', duration_seconds=600, ended_in_phase='completed', stop_reason=None, meditation=meta)
    return dict(manifest=manifest, raw_base64=base64.b64encode(raw).decode(), checksum_sha256=hashlib.sha256(raw).hexdigest(),
        decisions=[], frames=[])


def feedback(profile, sid, revision=2, busy=3, relaxed=7):
    return dict(schema_version=1, owner_account_id=profile['owner_account_id'], session_id=sid,
        mental_busyness=busy, relaxation=relaxed, revision=revision)


def test_feedback_is_independent_revisioned_owned_and_cannot_restore_deleted_session(tmp_path, monkeypatch):
    token, profile, plan = context(tmp_path, monkeypatch)
    assert client.post('/v1/meditation/calibration-plans', headers=auth(token), json=plan).status_code == 201
    body = recording(profile, plan)
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    endpoint = f'/v1/meditation/sessions/{sid}/feedback'
    first = feedback(profile, sid)
    assert client.post(endpoint, headers=auth(token), json=first).status_code == 200
    assert client.post(endpoint, headers=auth(token), json=first).json() == first
    assert client.post(endpoint, headers=auth(token), json=first | {'relaxation': 8}).status_code == 409
    edited = feedback(profile, sid, revision=3, relaxed=9)
    assert client.post(endpoint, headers=auth(token), json=edited).status_code == 200
    assert client.post(endpoint, headers=auth(token), json=first).status_code == 409
    assert client.get(endpoint, headers=auth(token)).json() == edited
    for value in [True, 2.5, -1, 11, None]:
        assert client.post(endpoint, headers=auth(token), json=edited | {'revision': 4, 'relaxation': value}).status_code == 422
    other = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.post(endpoint, headers=auth(other), json=edited).status_code == 404
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    saved = client.get(f'/v1/sessions/{sid}', headers=auth(token)).json()
    assert saved['checksum_sha256'] == body['checksum_sha256']
    assert 'relaxation' not in saved['manifest']['meditation']
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [sid]}).status_code == 200
    assert client.post(endpoint, headers=auth(token), json=edited).status_code == 410


def test_training_requests_are_durable_source_scoped_and_never_build_nir_policy(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    body = recording(profile)
    body['decisions'] = [{'action': 'binaural_10', 'reward': 9, 'updated_bandit': True}]
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid)).status_code == 200
    request = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid, feedback_revision=2,
        origin='muse', protocol_version='meditation-1')
    endpoint = '/v1/meditation/training/jobs'
    first = client.post(endpoint, headers=auth(token), json=request)
    assert first.status_code == 202, first.text
    again = client.post(endpoint, headers=auth(token), json=request)
    assert again.json()['id'] == first.json()['id']
    coalesced = client.post(endpoint, headers=auth(token), json=request | {'request_id': str(uuid.uuid4())})
    assert coalesced.json()['id'] == first.json()['id']
    wrong_source = client.post(endpoint, headers=auth(token), json=request | {'origin': 'simulator'})
    assert wrong_source.status_code == 409
    assert client.post('/v1/training/jobs', headers=auth(token), json={'origin': 'muse', 'experiment_version': 'meditation-1'}).status_code == 400
    with SessionLocal() as db:
        run_once(db)
    job = client.get(f"{endpoint}/{first.json()['id']}", headers=auth(token)).json()
    assert job['status'] == 'queued'
    assert job['origin'] == 'muse' and job['protocol_version'] == 'meditation-1'
    assert 'model_version' not in job
    policy = client.get('/v1/bandit/latest', headers=auth(token), params={'origin': 'muse', 'experiment_version': 'meditation-1'}).json()
    assert policy['included_session_ids'] == []
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid, revision=3, relaxed=8)).status_code == 200
    assert client.post(endpoint, headers=auth(token), json=request).status_code == 409
    newer = client.post(endpoint, headers=auth(token), json=request | {'request_id': str(uuid.uuid4()), 'feedback_revision': 3})
    assert newer.json()['id'] != first.json()['id']


def test_upload_dependencies_strict_context_and_adaptive_outcomes_preserve_legacy(tmp_path, monkeypatch):
    token, profile, plan = context(tmp_path, monkeypatch)
    calibration = recording(profile, plan)
    assert client.post('/v1/sessions', headers=auth(token), json=calibration).status_code == 404
    invalid = plan | {'schedule': ['control'] * 10}
    assert client.post('/v1/meditation/calibration-plans', headers=auth(token), json=invalid).status_code == 422
    assert client.post('/v1/meditation/calibration-plans', headers=auth(token), json=plan).status_code == 201
    calibration['manifest']['meditation']['fixed_action'] = 'binaural_8'
    assert client.post('/v1/sessions', headers=auth(token), json=calibration).status_code == 422
    other = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.post('/v1/sessions', headers=auth(other), json=recording(profile)).status_code == 404
    stopped = recording(profile)
    stopped['manifest'].update(duration_seconds=1, ended_in_phase='stopped', stop_reason='audioLost')
    stopped['manifest']['meditation']['played_frames'] = 48000
    assert client.post('/v1/sessions', headers=auth(token), json=stopped).status_code == 200
    sid = stopped['manifest']['session_id']
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid)).status_code == 409
    adaptive = recording(profile, mode='adaptive')
    assert client.post('/v1/sessions', headers=auth(token), json=adaptive).status_code == 200
    sid = adaptive['manifest']['session_id']
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid)).status_code == 200
    req = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid, feedback_revision=2, origin='muse', protocol_version='meditation-1')
    assert client.post('/v1/meditation/training/jobs', headers=auth(token), json=req).status_code == 409
    from test_api import post_session
    assert post_session(token, 'legacy-' + str(uuid.uuid4())).status_code == 200


def test_legacy_misrouted_worker_job_cannot_learn_meditation_decisions(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    body = recording(profile)
    body['decisions'] = [{'action': 'binaural_10', 'reward': 9, 'updated_bandit': True}]
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    # Restore a previously persisted legacy job at the real worker boundary.
    from app.models import TrainingJob
    with SessionLocal() as db:
        db.add(TrainingJob(id=str(uuid.uuid4()), user_id=profile['owner_account_id'], origin='muse',
            experiment_version='meditation-1', status='queued', created_at=datetime.now(UTC)))
        db.commit()
        run_once(db)
    policy = client.get('/v1/bandit/latest', headers=auth(token), params={'origin': 'muse', 'experiment_version': 'meditation-1'}).json()
    assert policy['included_session_ids'] == []
    assert policy['actions']['binaural_10']['n'] == 0
