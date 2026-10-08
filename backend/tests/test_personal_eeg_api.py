"""Synthetic Simulator evidence only: proves delivery/math, not physical EEG."""
import json
import math
import uuid
from pathlib import Path
from app.db import SessionLocal
from app.worker import run_once
from test_api import auth, client, register
from test_meditation_sync import context, recording, feedback
from test_profiles import source, ready_render
from test_eeg_model_math import frames, channel


def test_synthetic_simulator_api_worker_exports_ready_model(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    other_asset = source(token)
    render = ready_render(token, other_asset)
    other_profile = client.post('/v1/audio/profiles', headers=auth(token), json={'name':'Synthetic forest', 'render_id':render}).json()
    config = json.loads(Path('../contracts/default_experiment.json').read_text())
    for r in range(10):
        for bg, p in enumerate([profile, other_profile]):
            body = recording(p, origin='simulator', quality_version=config['quality_version'], eeg_config=config,
                playback_timeline_version=1)
            body['manifest']['data_origin'] = 'simulator'
            body['frames'] = frames(range(11,61), channels=[channel('A', 2*math.exp((r-4.5)/3),2,2*math.exp(-.1 if bg==0 else .1)),
                channel('B',2*math.exp((r-4.5)/3),2,2*math.exp(-.1 if bg==0 else .1))])
            sid = body['manifest']['session_id']
            result = client.post('/v1/sessions', headers=auth(token), json=body)
            assert result.status_code == 200, result.text
            assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(p,sid,revision=1,busy=10-r,relaxed=r)).status_code==200
    request = dict(schema_version=1,request_id=str(uuid.uuid4()),session_id=sid,feedback_revision=1,origin='simulator',protocol_version='meditation-1')
    job = client.post('/v1/meditation/training/jobs',headers=auth(token),json=request).json()
    with SessionLocal() as db:
        assert run_once(db) >= 1
    latest = client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'simulator'})
    assert latest.status_code==200, latest.text
    model=latest.json()
    assert model['status']=='ready', model
    assert model['validation']['session_count']==20
    assert len(model['fixed_minutes'])==20
    assert model['origin']=='simulator'
    assert model['owner_account_id']==profile['owner_account_id']
    assert model['dataset_fingerprint']==job['dataset_fingerprint']
    assert model['validation']['mae'] < .2
    assert model['validation']['correlation'] > .99
    assert client.get('/v1/meditation/models/latest',headers=auth(token),params={'origin':'muse'}).status_code==404
    other = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.get('/v1/meditation/models/latest',headers=auth(other),params={'origin':'simulator'}).status_code==404
    assert client.get('/v1/meditation/models/latest').status_code==401
    # Literal source provenance survives the real API/worker; fixture consumed by Dart.
    fixture=Path('../contracts/fixtures/synthetic_simulator_model.json')
    if not fixture.exists():
        fixture.write_text(json.dumps({'description':'Synthetic Simulator only; no physical Muse evidence','model':model},indent=2)+'\n')
