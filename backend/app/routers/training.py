import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import TrainingJob, User

router = APIRouter(prefix="/training", tags=["training"])


class JobIn(BaseModel):
    origin: str
    experiment_version: str


@router.post("/jobs")
def create_job(body: JobIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    if body.origin not in {"simulator", "muse"}:
        raise HTTPException(status_code=400, detail="origin must be simulator or muse")
    job = TrainingJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        origin=body.origin,
        experiment_version=body.experiment_version,
        status="queued",
        created_at=datetime.now(UTC),
    )
    db.add(job)
    db.commit()
    return {"id": job.id, "status": job.status}


@router.get("/jobs/{job_id}")
def get_job(job_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    job = db.get(TrainingJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status_code=404, detail="Job not found")
    return {
        "id": job.id,
        "status": job.status,
        "origin": job.origin,
        "experiment_version": job.experiment_version,
        "bandit_version": job.bandit_version,
        "error": job.error,
    }
