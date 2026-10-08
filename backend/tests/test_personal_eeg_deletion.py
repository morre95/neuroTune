import json
import uuid
from pathlib import Path

from test_api import auth, client
from app.db import SessionLocal
from app.models import PersonalEegModel
from app.worker import run_once
from test_eeg_model_math import frames
from test_meditation_sync import context, recording, feedback


def test_deleting_included_evidence_removes_model_after_previous_unusable_job_detachment(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    config = json.loads(Path('../contracts/default_experiment.json').read_text())
    useful = recording(profile, quality_version=config['quality_version'], eeg_config=config, playback_timeline_version=1)
    useful['frames'] = frames(range(11, 61))
    sid = useful['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=useful).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback', headers=auth(token), json=feedback(profile, sid, revision=1)).status_code == 200
    unusable = recording(profile)
    bad = unusable['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=unusable).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{bad}/feedback', headers=auth(token), json=feedback(profile, bad, revision=1)).status_code == 200
    request = dict(schema_version=1, request_id=str(uuid.uuid4()), session_id=bad, feedback_revision=1, origin='muse', protocol_version='meditation-1')
    assert client.post('/v1/meditation/training/jobs', headers=auth(token), json=request).status_code == 202
    with SessionLocal() as db:
        run_once(db)
    latest = client.get('/v1/meditation/models/latest', headers=auth(token)).json()
    assert latest['included_session_ids'] == [sid]
    mid = latest['id']
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [bad]}).status_code == 200
    with SessionLocal() as db:
        assert db.get(PersonalEegModel, mid).job_id is None
    assert client.get('/v1/meditation/models/latest', headers=auth(token)).json()['id'] == mid
    assert client.post('/v1/sessions/delete', headers=auth(token), json={'session_ids': [sid]}).status_code == 200
    with SessionLocal() as db:
        assert db.get(PersonalEegModel, mid) is None, 'Detached artifact still holds deleted included-session evidence'
    revoked = client.get('/v1/meditation/models/latest', headers=auth(token)).json()
    assert revoked['status'] == 'revoked' and revoked['included_session_ids'] == []
