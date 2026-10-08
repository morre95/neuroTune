"""Owned deletion/rebuild through real synthetic Simulator API and worker."""
import json
import math
import uuid
from pathlib import Path

from app.db import SessionLocal
from app.worker import run_once
from test_api import auth, client
from test_eeg_model_math import frames, channel
from test_meditation_sync import context, recording, feedback


def add_fixed(token, profile, target):
    config = json.loads(Path('../contracts/default_experiment.json').read_text())
    body = recording(profile, origin='simulator', quality_version=config['quality_version'],
        eeg_config=config, playback_timeline_version=1)
    body['manifest']['data_origin'] = 'simulator'
    body['frames'] = frames(range(11,61), channels=[
        channel(name, 2*math.exp((target-4.5)/3), 2, 2) for name in ['A','B']])
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    rating = feedback(profile, sid, revision=1, busy=10-target, relaxed=target)
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=rating).status_code == 200
    return sid, body, rating


def request(token, sid):
    body = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid,
        feedback_revision=1, origin='simulator', protocol_version='meditation-1')
    response = client.post('/v1/meditation/training/jobs', headers=auth(token), json=body)
    assert response.status_code == 202, response.text
    return body, response.json()


def latest(token):
    response = client.get('/v1/meditation/models/latest', headers=auth(token), params={'origin':'simulator'})
    assert response.status_code == 200, response.text
    return response.json()


def consume():
    with SessionLocal() as db:
        run_once(db)


def test_deletion_rebuild_is_durable_idempotent_and_never_resurrects_historical_ready(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    saved = [add_fixed(token, profile, target) for target in range(10) for _ in range(2)]
    request(token, saved[-1][0])
    consume()
    old = latest(token)
    assert old['status'] == 'ready' and old['validation']['session_count'] == 20
    extra, _, _ = add_fixed(token, profile, 4)
    request(token, extra)
    consume()
    newer = latest(token)
    assert newer['status'] == 'ready' and newer['validation']['session_count'] == 21
    assert newer['model_version'] != old['model_version']

    deleted = client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids':[extra]})
    assert deleted.status_code == 200
    revoked = latest(token)
    assert revoked['status'] == 'revoked', 'deletion silently resurrected a historical ready artifact'
    assert revoked['included_session_ids'] == [] and revoked.get('fixed_minutes', []) == []
    assert revoked['model_version'] not in [old['model_version'], newer['model_version']]
    repeat = client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids':[extra]})
    assert repeat.json()['deletion_epoch'] == deleted.json()['deletion_epoch']
    assert latest(token)['id'] == revoked['id']
    # Remaining fingerprint equals an old completed job. Explicit rebuilding
    # must still produce a new opaque model, without a unique-job/FK failure.
    consume()
    rebuilt = latest(token)
    assert rebuilt['status'] == 'ready' and rebuilt['validation']['session_count'] == 20
    assert rebuilt['dataset_fingerprint'] == old['dataset_fingerprint']
    assert rebuilt['model_version'] not in [old['model_version'], newer['model_version'], revoked['model_version']]
    assert extra not in rebuilt['included_session_ids']
    consume()
    assert latest(token)['id'] == rebuilt['id'], 'idle worker duplicated a completed rebuild'

    sid, raw, rating = saved[-1]
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids':[sid]}).status_code == 200
    assert latest(token)['status'] == 'revoked'
    consume()
    insufficient = latest(token)
    assert insufficient['status'] == 'insufficient' and insufficient['validation']['session_count'] == 19
    assert sid not in insufficient['included_session_ids']
    assert client.post('/v1/sessions', headers=auth(token), json=raw).status_code == 410
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=rating).status_code == 410
    late = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid,
        feedback_revision=1, origin='simulator', protocol_version='meditation-1')
    assert client.post('/v1/meditation/training/jobs', headers=auth(token), json=late).status_code == 410
    replacement, _, _ = add_fixed(token, profile, 9)
    request(token, replacement)
    consume()
    recovered = latest(token)
    assert recovered['status'] == 'ready' and recovered['validation']['session_count'] == 20
    assert recovered['model_version'] != rebuilt['model_version']
    assert sid not in recovered['included_session_ids'] and replacement in recovered['included_session_ids']
