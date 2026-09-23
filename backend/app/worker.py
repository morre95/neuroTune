import json
import uuid
from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.models import BanditVersion, SessionRecord, TrainingJob

ACTIONS = ["binaural_6", "binaural_8", "binaural_10", "binaural_12", "control"]


def process_job(db: Session, job: TrainingJob) -> None:
    job.status = "running"
    sessions = (
        db.query(SessionRecord)
        .filter(
            SessionRecord.user_id == job.user_id,
            SessionRecord.origin == job.origin,
            SessionRecord.experiment_version == job.experiment_version,
        )
        .all()
    )
    stats = {action: {"n": 0, "mean": 0.0} for action in ACTIONS}
    included: list[str] = []
    for session in sessions:
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
        db.query(BanditVersion)
        .filter(
            BanditVersion.user_id == job.user_id,
            BanditVersion.origin == job.origin,
            BanditVersion.experiment_version == job.experiment_version,
        )
        .count()
    )
    policy_version = f"v{previous + 1}"
    body = {
        "policy_version": policy_version,
        "experiment_version": job.experiment_version,
        "data_origin": job.origin,
        "epsilon": 0.2,
        "actions": stats,
        "included_session_ids": included,
        "created_at_iso": datetime.now(UTC).isoformat(),
    }
    db.add(
        BanditVersion(
            id=str(uuid.uuid4()),
            user_id=job.user_id,
            policy_version=policy_version,
            origin=job.origin,
            experiment_version=job.experiment_version,
            body=json.dumps(body),
            created_at=datetime.now(UTC),
        )
    )
    job.status = "done"
    job.bandit_version = policy_version
    db.commit()


def run_once(db: Session) -> int:
    jobs = db.query(TrainingJob).filter(TrainingJob.status == "queued").all()
    for job in jobs:
        try:
            process_job(db, job)
        except Exception as exc:  # noqa: BLE001
            job.status = "failed"
            job.error = str(exc)
            db.commit()
    return len(jobs)


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
