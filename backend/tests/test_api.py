import base64
import hashlib
import json
import os
from pathlib import Path

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("RAW_DATA_DIR", "/tmp/neurotune-raw-test")
os.environ.setdefault(
    "CONTRACTS_PATH",
    str(Path(__file__).resolve().parents[2] / "contracts" / "default_experiment.json"),
)

from fastapi.testclient import TestClient

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
    assert me.json()["version"] == "2026.2"
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
