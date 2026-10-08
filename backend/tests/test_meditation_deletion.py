import uuid

from test_api import auth, client, register
from test_meditation_sync import context, feedback, recording


def rated_job(token, profile, plan=None, origin='muse'):
    body = recording(profile, plan, origin=origin)
    body['manifest']['data_origin'] = origin
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid)).status_code == 200
    request = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid, feedback_revision=2,
        origin=origin, protocol_version='meditation-1')
    result = client.post('/v1/meditation/training/jobs', headers=auth(token), json=request)
    assert result.status_code == 202, result.text
    return body, request, result.json()['id']


def test_owned_deletion_removes_ratings_job_snapshots_and_aliases_but_preserves_other_source_and_plan(tmp_path, monkeypatch):
    token, profile, plan = context(tmp_path, monkeypatch)
    assert client.post('/v1/meditation/calibration-plans', headers=auth(token), json=plan).status_code == 201
    body, request, job = rated_job(token, profile, plan)
    alias = request | {'request_id': str(uuid.uuid4())}
    assert client.post('/v1/meditation/training/jobs', headers=auth(token), json=alias).json()['id'] == job
    other, _, other_job = rated_job(token, profile, origin='simulator')
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [sid]}).status_code == 200
    assert client.get(f'/v1/meditation/training/jobs/{job}', headers=auth(token)).status_code == 404
    assert client.get(f'/v1/meditation/training/jobs/{other_job}', headers=auth(token)).status_code == 200
    assert client.get(f'/v1/sessions/{other["manifest"]["session_id"]}', headers=auth(token)).status_code == 200
    assert client.get(f'/v1/meditation/calibration-plans/{plan["id"]}', headers=auth(token)).json() == plan
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 410
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid)).status_code == 410
    assert client.post('/v1/meditation/training/jobs', headers=auth(token), json=request).status_code == 410


def test_deletion_epoch_is_monotonic_idempotent_owned_and_unknown_ids_are_tombstoned(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    body, _, _ = rated_job(token, profile)
    sid = body['manifest']['session_id']
    foreign = register(f'{uuid.uuid4()}@example.com')['access_token']
    response = client.post('/v1/sessions/delete', headers=auth(foreign), json={'session_ids': [sid]})
    assert response.status_code == 404
    first = client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [sid]}).json()
    assert first['deletion_epoch'] == 1
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [sid, sid]}).json()['deletion_epoch'] == 1
    unknown = str(uuid.uuid4())
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [unknown]}).json()['deletion_epoch'] == 2
    late = recording(profile)
    late['manifest']['session_id'] = unknown
    assert client.post('/v1/sessions', headers=auth(token), json=late).status_code == 410
    assert client.post('/v1/sessions/delete', headers=auth(foreign), json={'session_ids': [str(uuid.uuid4())]}).json()['deletion_epoch'] == 1
