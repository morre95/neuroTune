import json
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import BanditVersion, User
from app.worker import ACTIONS

router = APIRouter(prefix="/bandit", tags=["bandit"])


@router.get("/latest")
def latest_bandit(
    origin: str = Query(...),
    experiment_version: str = Query(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    row = (
        db.query(BanditVersion)
        .filter(
            BanditVersion.user_id == user.id,
            BanditVersion.origin == origin,
            BanditVersion.experiment_version == experiment_version,
        )
        .order_by(BanditVersion.created_at.desc())
        .first()
    )
    if row is None:
        return {
            "policy_version": "0",
            "experiment_version": experiment_version,
            "data_origin": origin,
            "epsilon": 0.2,
            "actions": {action: {"n": 0, "mean": 0.0} for action in ACTIONS},
            "included_session_ids": [],
            "created_at_iso": datetime.now(UTC).isoformat(),
        }
    return json.loads(row.body)
