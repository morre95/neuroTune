import base64
import hashlib
import json
import os
from pathlib import Path
import pytest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("JWT_SECRET", "test-only-secret-at-least-32-bytes-long")
os.environ.setdefault("RAW_DATA_DIR", "/tmp/neurotune-raw-test")
os.environ.setdefault(
    "CONTRACTS_PATH",
    str(Path(__file__).resolve().parents[2] / "contracts" / "default_experiment.json"),
)

from fastapi.testclient import TestClient

from app.config import settings
from app.db import Base, SessionLocal, engine
from app.main import app, seed_experiment
from app.worker import run_once

Base.metadata.create_all(engine)
seed_experiment()
client = TestClient(app)


def register(email: str, password: str = "correct-horse") -> dict:
    response = client.post("/v1/auth/register", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def upload(token: str, session_id: str, raw: bytes = b"eeg-bytes", reward: float | None = 0.5) -> dict:
    digest = hashlib.sha256(raw).hexdigest()
    body = {
        "manifest": {
            "session_id": session_id,
            "experiment_version": "2026.2",
            "policy_version": "0",
            "data_origin": "simulator",
            "timeline": "monotonic_session_seconds",
            "sample_rate_hz": 256,
        },
        "decisions": [
            {
                "action": "binaural_10",
                "reward": reward,
                "updated_bandit": reward is not None,
                "aborted": False,
            }
        ],
        "frames": [],
        "raw_base64": base64.b64encode(raw).decode(),
        "checksum_sha256": digest,
    }
    return client.post("/v1/sessions", json=body, headers=auth(token)).json() | {"status": client.post("/v1/sessions", json=body, headers=auth(token)).status_code}


def post_session(token: str, session_id: str, raw: bytes = b"eeg-bytes", reward: float | None = 0.5):
    digest = hashlib.sha256(raw).hexdigest()
    body = {
        "manifest": {
            "session_id": session_id,
            "experiment_version": "2026.2",
            "policy_version": "0",
            "data_origin": "simulator",
            "timeline": "monotonic_session_seconds",
            "sample_rate_hz": 256,
        },
        "decisions": [
            {
                "action": "binaural_10",
                "reward": reward,
                "updated_bandit": reward is not None,
                "aborted": False,
            }
        ],
        "frames": [],
        "raw_base64": base64.b64encode(raw).decode(),
        "checksum_sha256": digest,
    }
    return client.post("/v1/sessions", json=body, headers=auth(token))


def test_register_login_refresh_logout():
    tokens = register("person@example.com")
    me = client.get("/v1/experiments/active", headers=auth(tokens["access_token"]))
    assert me.status_code == 200
    assert me.json()["version"] == "2026.4"
    refreshed = client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert refreshed.status_code == 200
    old = client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert old.status_code == 401
    logged_out = client.post(
        "/v1/auth/logout",
        json={"refresh_token": refreshed.json()["refresh_token"]},
        headers=auth(refreshed.json()["access_token"]),
    )
    assert logged_out.status_code == 200


def test_accounts_are_separated_and_uploads_are_idempotent():
    alice = register("alice@example.com")
    bob = register("bob@example.com")
    first = post_session(alice["access_token"], "session-alice")
    assert first.status_code == 200
    again = post_session(alice["access_token"], "session-alice")
    assert again.status_code == 200
    conflict = post_session(alice["access_token"], "session-alice", raw=b"other-bytes")
    assert conflict.status_code == 409
    bob_view = client.get("/v1/sessions/session-alice", headers=auth(bob["access_token"]))
    assert bob_view.status_code == 404
    bob_list = client.get("/v1/sessions", headers=auth(bob["access_token"]))
    assert bob_list.json() == []
    alice_list = client.get("/v1/sessions", headers=auth(alice["access_token"]))
    assert len(alice_list.json()) == 1
    db = SessionLocal()
    try:
        from app.models import SessionRecord

        assert db.query(SessionRecord).filter(SessionRecord.id == "session-alice").count() == 1
    finally:
        db.close()


def test_session_id_cannot_escape_raw_directory():
    tokens = register("path-check@example.com")
    response = post_session(tokens["access_token"], "../outside")
    assert response.status_code == 400
    assert "session_id" in response.json()["detail"]


def test_training_builds_a_personal_policy_once():
    tokens = register("trainer@example.com")
    created = post_session(tokens["access_token"], "session-train", reward=1.0)
    assert created.status_code == 200
    post_session(tokens["access_token"], "session-train", reward=1.0)
    job = client.post(
        "/v1/training/jobs",
        json={"origin": "simulator", "experiment_version": "2026.2"},
        headers=auth(tokens["access_token"]),
    )
    assert job.status_code == 200
    db = SessionLocal()
    try:
        assert run_once(db) == 1
    finally:
        db.close()
    done = client.get(f"/v1/training/jobs/{job.json()['id']}", headers=auth(tokens["access_token"]))
    assert done.json()["status"] == "done"
    policy = client.get(
        "/v1/bandit/latest",
        params={"origin": "simulator", "experiment_version": "2026.2"},
        headers=auth(tokens["access_token"]),
    )
    body = policy.json()
    assert body["included_session_ids"] == ["session-train"]
    assert body["actions"]["binaural_10"]["n"] == 1
    other = client.get(
        "/v1/bandit/latest",
        params={"origin": "simulator", "experiment_version": "2026.2"},
        headers=auth(register("other@example.com")["access_token"]),
    )
    assert other.json()["policy_version"] == "0"
    assert other.json()["included_session_ids"] == []


def test_bulk_delete_removes_raw_data_and_rebuilds_policy():
    from app.models import BanditVersion, SessionDeletion, SessionRecord

    token = register("delete-many@example.com")["access_token"]
    for sid, reward in [("delete-one", 0.1), ("delete-two", 0.2), ("keep-three", 0.3)]:
        assert post_session(token, sid, reward=reward).status_code == 200
    client.post("/v1/training/jobs", json={"origin": "simulator", "experiment_version": "2026.2"}, headers=auth(token))
    with SessionLocal() as db:
        run_once(db)
        paths = [Path(db.get(SessionRecord, sid).raw_path) for sid in ["delete-one", "delete-two"]]
        owner = db.get(SessionRecord, "delete-one").user_id
    body = {"session_ids": ["delete-one", "delete-two", "never-uploaded"]}
    response = client.post("/v1/sessions/delete", json=body, headers=auth(token))
    assert response.status_code == 200, response.text
    assert set(response.json()["deleted_session_ids"]) == set(body["session_ids"])
    assert all(not path.exists() for path in paths)
    assert client.get("/v1/sessions/delete-one", headers=auth(token)).status_code == 404
    assert [row["session_id"] for row in client.get("/v1/sessions", headers=auth(token)).json()] == ["keep-three"]
    assert client.post("/v1/sessions/delete", json=body, headers=auth(token)).status_code == 200
    assert post_session(token, "delete-one").status_code == 410
    assert post_session(token, "never-uploaded").status_code == 410
    policy = client.get("/v1/bandit/latest", params={"origin": "simulator", "experiment_version": "2026.2"}, headers=auth(token)).json()
    assert policy["included_session_ids"] == ["keep-three"]
    assert policy["actions"]["binaural_10"]["n"] == 1
    assert policy["actions"]["binaural_10"]["mean"] == pytest.approx(0.3)
    with SessionLocal() as db:
        assert db.get(SessionRecord, "delete-one") is None
        assert db.get(SessionDeletion, (owner, "delete-one")).raw_path is None
        assert db.query(BanditVersion).filter(BanditVersion.user_id == owner).count() == 1


def test_bulk_delete_is_atomic_and_account_scoped():
    from app.models import SessionDeletion, SessionRecord

    alice = register("delete-owner@example.com")["access_token"]
    bob = register("delete-other@example.com")["access_token"]
    assert post_session(alice, "delete-owned").status_code == 200
    assert post_session(bob, "delete-foreign").status_code == 200
    body = {"session_ids": ["delete-owned", "delete-foreign"]}
    assert client.post("/v1/sessions/delete", json=body, headers=auth(alice)).status_code == 404
    with SessionLocal() as db:
        row = db.get(SessionRecord, "delete-owned")
        assert row is not None
        assert Path(row.raw_path).exists()
        assert db.get(SessionDeletion, (row.user_id, "delete-owned")) is None
        assert db.get(SessionRecord, "delete-foreign") is not None
    assert client.post("/v1/sessions/delete", json=body).status_code == 401
    assert client.post("/v1/sessions/delete", json={"session_ids": ["../escape"]}, headers=auth(alice)).status_code == 400
    assert client.post("/v1/sessions/delete", json={"session_ids": []}, headers=auth(alice)).status_code == 422
    assert client.post("/v1/sessions/delete", json={"session_ids": [str(i) for i in range(101)]}, headers=auth(alice)).status_code == 422


def test_delete_retries_raw_file_cleanup_without_restoring_session(monkeypatch):
    from app.models import SessionDeletion, SessionRecord

    token = register("delete-cleanup@example.com")["access_token"]
    assert post_session(token, "delete-cleanup").status_code == 200
    with SessionLocal() as db:
        row = db.get(SessionRecord, "delete-cleanup")
        owner, path = row.user_id, Path(row.raw_path)
    original = Path.unlink

    def fail_cleanup(self, *args, **kwargs):
        if self == path:
            raise OSError("temporary cleanup failure")
        return original(self, *args, **kwargs)

    monkeypatch.setattr(Path, "unlink", fail_cleanup)
    with pytest.raises(OSError, match="temporary cleanup failure"):
        client.post("/v1/sessions/delete", json={"session_ids": ["delete-cleanup"]}, headers=auth(token))
    with SessionLocal() as db:
        assert db.get(SessionRecord, "delete-cleanup") is None
        assert db.get(SessionDeletion, (owner, "delete-cleanup")).raw_path is not None
    monkeypatch.setattr(Path, "unlink", original)
    assert client.post("/v1/sessions/delete", json={"session_ids": ["delete-cleanup"]}, headers=auth(token)).status_code == 200
    assert not path.exists()


def test_seeding_a_new_version_leaves_one_active_experiment(monkeypatch, tmp_path):
    original = Path(settings.contracts_path)
    body = json.loads(original.read_text())
    newer = tmp_path / "experiment.json"
    newer.write_text(json.dumps({**body, "version": "test-newer"}))
    tokens = register("seed@example.com")

    monkeypatch.setattr(settings, "contracts_path", str(newer))
    seed_experiment()
    active = client.get("/v1/experiments/active", headers=auth(tokens["access_token"]))
    monkeypatch.setattr(settings, "contracts_path", str(original))
    seed_experiment()

    assert active.status_code == 200
    assert active.json()["version"] == "test-newer"


def test_startup_preserves_legacy_config_and_publishes_current_quality():
    import uuid
    from app.models import Experiment

    legacy = json.loads(Path(settings.contracts_path).read_text())
    legacy.update(version='2026.3', quality_version='2026.3-unverified')
    original_body = json.dumps(legacy)
    # Disposable startup fixture: the previous deployed DB has only its old
    # canonical row, not the new shipped configuration.
    with SessionLocal() as db:
        db.query(Experiment).filter(Experiment.version == '2026.4').delete()
        old = db.query(Experiment).filter(Experiment.version == '2026.3').one_or_none()
        if old is None:
            old = Experiment(id=str(uuid.uuid4()), version='2026.3', body=original_body, active=True)
            db.add(old)
        else:
            old.body, old.active = original_body, True
        db.commit()
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    for _ in range(2):
        with TestClient(app) as restarted:
            active = restarted.get('/v1/experiments/active', headers=auth(token))
            assert active.status_code == 200
            assert active.json()['version'] == '2026.4'
            assert active.json()['quality_version'] == '2026.4-unverified'
        with SessionLocal() as db:
            assert db.query(Experiment).filter_by(version='2026.3').one().body == original_body
            assert db.query(Experiment).filter_by(active=True).count() == 1
