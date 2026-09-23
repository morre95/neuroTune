import json

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import Experiment, User

router = APIRouter(prefix="/experiments", tags=["experiments"])


@router.get("/active")
def active_experiment(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict:
    row = db.query(Experiment).filter(Experiment.active.is_(True)).one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="No active experiment")
    return json.loads(row.body)
