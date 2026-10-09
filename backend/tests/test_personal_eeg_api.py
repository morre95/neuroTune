"""Synthetic Simulator evidence only: proves delivery/math, not physical EEG."""
import json
import os
import pytest
import math
import uuid
from pathlib import Path
from test_api import auth, client, register
from app.db import SessionLocal
from app.worker import run_once
from test_meditation_sync import context, recording, feedback
from test_profiles import source, ready_render
from test_eeg_model_math import frames, channel


def test_fresh_request_retries_failed_training_without_reactivating_old_model(tmp_path, monkeypatch):
    import app.personal_eeg as learner
    token, profile, _ = context(tmp_path, monkeypatch)
    body = recording(profile)
    sid = body['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token),
                       json=feedback(profile, sid)).status_code == 200
    request = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=sid,
                   feedback_revision=2, origin='muse', protocol_version='meditation-1')
    endpoint = '/v1/meditation/training/jobs'
    initial = client.post(endpoint, headers=auth(token), json=request).json()
    original = learner.train_model

    def transient_failure(_rows):
        raise OSError('Temporary training resource failure')

    monkeypatch.setattr(learner, 'train_model', transient_failure)
    with SessionLocal() as db:
        run_once(db)
    failed = client.get('/v1/meditation/models/latest', headers=auth(token), params={'origin': 'muse'}).json()
    assert failed['status'] == 'failed'
    # Replaying the same delivery remains idempotent; a fresh user request retries.
    assert client.post(endpoint, headers=auth(token), json=request).json()['status'] == 'failed'
    retry = client.post(endpoint, headers=auth(token), json=request | {'request_id': str(uuid.uuid4())}).json()
    assert retry['id'] == initial['id']
    assert retry['status'] == 'queued'
    assert client.get('/v1/meditation/models/latest', headers=auth(token), params={'origin': 'muse'}).json()['id'] == failed['id']
    # Another transient failure must publish a fresh failed artifact safely too.
    with SessionLocal() as db:
        run_once(db)
    failed_again = client.get('/v1/meditation/models/latest', headers=auth(token), params={'origin': 'muse'}).json()
    assert failed_again['status'] == 'failed' and failed_again['id'] != failed['id']
    monkeypatch.setattr(learner, 'train_model', original)
    assert client.post(endpoint, headers=auth(token), json=request | {'request_id': str(uuid.uuid4())}).json()['status'] == 'queued'
    with SessionLocal() as db:
        run_once(db)
    assert client.get(f"{endpoint}/{initial['id']}", headers=auth(token)).json()['status'] == 'done'
    latest = client.get('/v1/meditation/models/latest', headers=auth(token), params={'origin': 'muse'}).json()
    assert latest['id'] != failed_again['id']
    assert latest['status'] == 'insufficient'  # Retry does not bypass validation gates.


def test_synthetic_simulator_api_worker_exports_ready_model(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    other_asset = source(token)
    render = ready_render(token, other_asset)
    other_profile = client.post('/v1/audio/profiles', headers=auth(token), json={'name':'Synthetic forest', 'render_id':render}).json()
    config = json.loads(Path('../contracts/default_experiment.json').read_text())
    recordings=[]
    for r in range(10):
        for bg, p in enumerate([profile, other_profile]):
            body = recording(p, origin='simulator', quality_version=config['quality_version'], eeg_config=config,
                playback_timeline_version=1)
            body['manifest']['data_origin'] = 'simulator'
            body['frames'] = frames(range(11,601 if r==0 and bg==0 else 61), channels=[channel('A', 2*math.exp((r-4.5)/3),2,2*math.exp(-.1 if bg==0 else .1)),
                channel('B',2*math.exp((r-4.5)/3),2,2*math.exp(-.1 if bg==0 else .1))])
            sid = body['manifest']['session_id']
            result = client.post('/v1/sessions', headers=auth(token), json=body)
            assert result.status_code == 200, result.text
            assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(p,sid,revision=1,busy=10-r,relaxed=r)).status_code==200
            recordings.append((p,sid))
    request = dict(schema_version=1,request_id=str(uuid.uuid4()),session_id=sid,feedback_revision=1,origin='simulator',protocol_version='meditation-1')
    job = client.post('/v1/meditation/training/jobs',headers=auth(token),json=request).json()
    with SessionLocal() as db:
        assert run_once(db) >= 1
    latest = client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'})
    assert latest.status_code==200, latest.text
    model=latest.json()
    assert model['status']=='ready', model
    assert model['validation']['session_count']==20
    assert len(model['fixed_minutes'])==29
    assert model['origin']=='simulator'
    assert model['owner_account_id']==profile['owner_account_id']
    assert model['dataset_fingerprint']==job['dataset_fingerprint']
    assert model['validation']['mae'] < .2
    assert model['validation']['correlation'] > .99
    fixture=Path('../contracts/fixtures/synthetic_simulator_model.json')
    if os.environ.get('UPDATE_SYNTHETIC_MODEL_FIXTURE')=='1':
        fixture.write_text(json.dumps({'description':'Synthetic Simulator only; no physical Muse evidence','model':model},indent=2)+'\n')
    shared=json.loads(fixture.read_text())['model']
    for key in ['means','scales','coefficients']:
        assert model[key]==pytest.approx(shared[key],abs=1e-12)
    assert model['intercept']==pytest.approx(shared['intercept'],abs=1e-12)
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'muse'}).status_code==404
    other = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.get('/v1/meditation/models/latest',headers=auth(other),params={'origin':'simulator'}).status_code==404
    assert client.get('/v1/meditation/models/latest').status_code==401
    unusable=recording(profile,origin='simulator')
    unusable['manifest']['data_origin']='simulator'
    bad_sid=unusable['manifest']['session_id']
    assert client.post('/v1/sessions',headers=auth(token),json=unusable).status_code==200
    assert client.post(f'/v1/meditation/sessions/{bad_sid}/feedback',headers=auth(token),json=feedback(profile,bad_sid,revision=1)).status_code==200
    bad_job=client.post('/v1/meditation/training/jobs',headers=auth(token),json=request | {'request_id':str(uuid.uuid4()),'session_id':bad_sid}).json()
    with SessionLocal() as db:
        run_once(db)
    latest=client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'}).json()
    assert latest['validation']['session_count']==20 and bad_sid not in latest['included_session_ids']
    assert client.post('/v1/sessions/delete',headers=auth(token),json={'session_ids':[bad_sid]}).status_code==200
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'}).json()['id']==latest['id']
    assert client.get(f"/v1/meditation/training/jobs/{bad_job['id']}",headers=auth(token)).status_code==404
    assert client.post('/v1/sessions/delete',headers=auth(token),json={'session_ids':['unrelated-source-deletion']}).status_code==200
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'}).json()['status']=='ready'
    # The checked-in artifact consumed by Dart is synthetic, never measured Muse evidence.
    for p,recording_id in recordings:
        assert client.post(f'/v1/meditation/sessions/{recording_id}/feedback',headers=auth(token),json=feedback(p,recording_id,revision=2,busy=5,relaxed=5)).status_code==200
    newer=client.post('/v1/meditation/training/jobs',headers=auth(token),json=request | {'request_id':str(uuid.uuid4()),'feedback_revision':2}).json()
    with SessionLocal() as db:
        run_once(db)
    failed=client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'}).json()
    assert failed['status']=='failed_validation'
    assert failed['id'] != model['id']
    assert failed['validation']['correlation'] is None
    assert client.post('/v1/sessions/delete',headers=auth(token),json={'session_ids':[sid]}).status_code==200
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'}).json()['status']=='revoked'
    assert client.get(f"/v1/meditation/training/jobs/{newer['id']}",headers=auth(token)).status_code==404


def test_server_epoch_change_during_fit_prevents_publication(tmp_path, monkeypatch):
    import app.personal_eeg as learner
    token, profile, _ = context(tmp_path, monkeypatch)
    body=recording(profile)
    sid=body['manifest']['session_id']
    assert client.post('/v1/sessions',headers=auth(token),json=body).status_code==200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback',headers=auth(token),json=feedback(profile,sid)).status_code==200
    request=dict(schema_version=1,request_id=str(uuid.uuid4()),session_id=sid,feedback_revision=2,origin='muse',protocol_version='meditation-1')
    job=client.post('/v1/meditation/training/jobs',headers=auth(token),json=request).json()
    original=learner.train_model
    def deleting_fit(rows):
        assert client.post('/v1/sessions/delete',headers=auth(token),json={'session_ids':['unknown-during-fit']}).status_code==200
        return original(rows)
    monkeypatch.setattr(learner,'train_model',deleting_fit)
    with SessionLocal() as db:
        run_once(db)
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'muse'}).status_code==404
    assert client.get(f"/v1/meditation/training/jobs/{job['id']}",headers=auth(token)).json()['status']=='queued'
    monkeypatch.setattr(learner,'train_model',original)
    with SessionLocal() as db:
        run_once(db)
    assert client.get(f"/v1/meditation/training/jobs/{job['id']}",headers=auth(token)).json()['status']=='done'
