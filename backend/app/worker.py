import json
import uuid
from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.models import BanditVersion, SessionRecord, TrainingJob, User

ACTIONS = ["binaural_6", "binaural_8", "binaural_10", "binaural_12", "control"]


def process_job(db: Session, job: TrainingJob) -> None:
    # Serialize policy building with deletion and upload for this account.
    db.query(User).filter(User.id == job.user_id).with_for_update().one()
    db.refresh(job)
    if job.status != "queued":
        return
    job.status = "running"
    policy = build_policy(db, job.user_id, job.origin, job.experiment_version)
    job.status = "done"
    job.bandit_version = policy.policy_version
    db.commit()


def build_policy(db: Session, user_id: str, origin: str, experiment_version: str) -> BanditVersion:
    """Rebuild from remaining sessions, inside the caller's transaction."""
    sessions = (
        db.query(SessionRecord)
        .filter(
            SessionRecord.user_id == user_id,
            SessionRecord.origin == origin,
            SessionRecord.experiment_version == experiment_version,
        )
        .all()
    )
    stats = {action: {"n": 0, "mean": 0.0} for action in ACTIONS}
    included: list[str] = []
    for session in sessions:
        if json.loads(session.manifest_json).get('meditation') is not None:
            continue
        decisions = json.loads(session.decisions_json)
        used = False
        for decision in decisions:
            if decision.get("aborted") or not decision.get("updated_bandit"):
                continue
            reward = decision.get("reward")
            action = decision.get("action")
            if reward is None or action not in stats:
                continue
            current = stats[action]
            current["n"] += 1
            current["mean"] += (float(reward) - current["mean"]) / current["n"]
            used = True
        if used:
            included.append(session.id)
    previous = (
        db.query(BanditVersion.policy_version)
        .filter(
            BanditVersion.user_id == user_id,
            BanditVersion.origin == origin,
            BanditVersion.experiment_version == experiment_version,
        )
        .all()
    )
    versions = [int(row.policy_version[1:]) for row in previous if row.policy_version.startswith("v") and row.policy_version[1:].isdigit()]
    policy_version = f"v{max(versions, default=0) + 1}"
    body = {
        "policy_version": policy_version,
        "experiment_version": experiment_version,
        "data_origin": origin,
        "epsilon": 0.2,
        "actions": stats,
        "included_session_ids": included,
        "created_at_iso": datetime.now(UTC).isoformat(),
    }
    policy = BanditVersion(
        id=str(uuid.uuid4()),
        user_id=user_id,
        policy_version=policy_version,
        origin=origin,
        experiment_version=experiment_version,
        body=json.dumps(body),
        created_at=datetime.now(UTC),
    )
    db.add(policy)
    return policy


def run_once(db: Session) -> int:
    jobs = db.query(TrainingJob).filter(TrainingJob.status == "queued").all()
    for job in jobs:
        try:
            process_job(db, job)
        except Exception as exc:  # noqa: BLE001
            job.status = "failed"
            job.error = str(exc)
            db.commit()
    from app.audio import run_audio_jobs
    from app.profiles import run_render_jobs

    return len(jobs) + run_audio_jobs(db) + run_render_jobs(db)


def main() -> None:
    import time

    from app.db import SessionLocal

    while True:
        db = SessionLocal()
        try:
            run_once(db)
        finally:
            db.close()
        time.sleep(1)


if __name__ == "__main__":
    main()
