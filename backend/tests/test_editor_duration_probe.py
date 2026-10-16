"""A2 characterization: keep legacy eligibility closed during the editor rollout."""
import json
from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

# Initialize the repository's in-memory test database before importing app.db.
from test_api import auth, client
from app.db import SessionLocal
from app.meditation import PlanIn, training_dataset
from app.models import SessionRecord, MeditationFeedbackRecord
from app.profiles import ProfileVersion
from app.worker import build_policy
from test_meditation_sync import context, recording, feedback


def test_old_upload_feedback_and_calibration_keep_exact_ten_minute_gate(tmp_path, monkeypatch):
    token, profile, plan = context(tmp_path, monkeypatch)
    listed = client.get('/v1/audio/profiles', headers=auth(token))
    assert listed.status_code == 200
    assert listed.json() == [profile]
    assert PlanIn.model_validate(plan).duration_seconds == 600
    for seconds in (599, 601, 3600):
        with pytest.raises(ValidationError):
            PlanIn.model_validate(plan | {'duration_seconds': seconds})
    # A new schema must be negotiated; sending it to an old parser is unsafe.
    with pytest.raises(ValidationError):
        ProfileVersion.model_validate(profile | {'schema_version': 2})
    for seconds in (599, 599 + 47999 / 48000, 600, 600 + 1 / 48000, 3600):
        body = recording(profile, played_frames=round(seconds * 48000))
        body['manifest']['duration_seconds'] = seconds
        uploaded = client.post('/v1/sessions', headers=auth(token), json=body)
        assert uploaded.status_code == (200 if seconds <= 600 else 422), uploaded.text
        if seconds <= 600:
            sid = body['manifest']['session_id']
            response = client.post(f'/v1/meditation/sessions/{sid}/feedback',
                headers=auth(token), json=feedback(profile, sid))
            assert response.status_code == (200 if seconds == 600 else 409)
    body = recording(profile, schema_version=2, protocol_version='editor-duration-probe-2')
    body['manifest']['experiment_version'] = 'editor-duration-probe-2'
    assert client.post('/v1/sessions', headers=auth(token), json=body).status_code == 422


def test_restored_long_or_new_protocol_rows_never_enter_old_training(tmp_path, monkeypatch):
    token, profile, _ = context(tmp_path, monkeypatch)
    valid = recording(profile)
    sid = valid['manifest']['session_id']
    assert client.post('/v1/sessions', headers=auth(token), json=valid).status_code == 200
    assert client.post(f'/v1/meditation/sessions/{sid}/feedback',
        headers=auth(token), json=feedback(profile, sid)).status_code == 200
    owner = profile['owner_account_id']
    with SessionLocal() as db:
        # Exercise consumers of already persisted rows as well as upload gates.
        # Include a ten-minute new-protocol row: duration alone is not eligibility.
        for seconds, protocol in ((3600, 'meditation-1'), (600, 'editor-duration-probe-2')):
            body = recording(profile, played_frames=seconds * 48000, protocol_version=protocol)
            manifest = body['manifest']
            manifest.update(duration_seconds=seconds, experiment_version=protocol)
            restored_id = manifest['session_id']
            db.add(SessionRecord(id=restored_id, user_id=owner, origin='muse',
                experiment_version=protocol, checksum=body['checksum_sha256'],
                manifest_json=json.dumps(manifest), frames_json='[]',
                decisions_json=json.dumps([dict(action='binaural_10', reward=9,
                    updated_bandit=True)]), raw_path=str(tmp_path / 'absent'),
                created_at=datetime.now(UTC)))
            db.add(MeditationFeedbackRecord(user_id=owner, session_id=restored_id,
                revision=2, body_json=json.dumps(feedback(profile, restored_id)),
                updated_at=datetime.now(UTC)))
        db.flush()
        assert [row['session_id'] for row in training_dataset(db, owner, 'muse', 'meditation-1')] == [sid]
        assert training_dataset(db, owner, 'muse', 'editor-duration-probe-2') == []
        # Even a misrouted old NIR worker cannot consume their reward decisions.
        for protocol in ('meditation-1', 'editor-duration-probe-2'):
            policy = json.loads(build_policy(db, owner, 'muse', protocol).body)
            assert policy['included_session_ids'] == []
            assert policy['actions']['binaural_10']['n'] == 0
