import base64
import hashlib
import json
import re
from datetime import UTC, datetime
from pathlib import Path

from compression import zstd
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import settings
from app.db import get_db
from app.models import SessionRecord, User

router = APIRouter(prefix="/sessions", tags=["sessions"])


class SessionUpload(BaseModel):
    manifest: dict
    decisions: list[dict]
    frames: list[dict]
    raw_base64: str
    checksum_sha256: str


def _summary(row: SessionRecord) -> dict:
    manifest = json.loads(row.manifest_json)
    return {
        "session_id": row.id,
        "origin": row.origin,
        "experiment_version": row.experiment_version,
        "created_at": row.created_at.isoformat(),
        "duration_seconds": manifest.get("duration_seconds"),
        "checksum_sha256": row.checksum,
    }


@router.post("")
def upload_session(
    body: SessionUpload,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    session_id = body.manifest.get("session_id")
    if not isinstance(session_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", session_id) is None:
        raise HTTPException(status_code=400, detail="manifest.session_id must be a safe identifier")
    try:
        raw = base64.b64decode(body.raw_base64)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="raw_base64 is not valid base64") from exc
    digest = hashlib.sha256(raw).hexdigest()
    if digest != body.checksum_sha256:
        raise HTTPException(status_code=400, detail="checksum mismatch")
    existing = db.get(SessionRecord, session_id)
    if existing is not None:
        if existing.user_id != user.id:
            raise HTTPException(status_code=409, detail="session id not available")
        if existing.checksum == digest:
            return _summary(existing)
        raise HTTPException(status_code=409, detail="checksum conflict")
    raw_dir = Path(settings.raw_data_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_path = raw_dir / f"{session_id}.zst"
    raw_path.write_bytes(zstd.compress(raw))
    row = SessionRecord(
        id=session_id,
        user_id=user.id,
        checksum=digest,
        origin=str(body.manifest.get("data_origin", "simulator")),
        experiment_version=str(body.manifest.get("experiment_version", "")),
        manifest_json=json.dumps(body.manifest),
        decisions_json=json.dumps(body.decisions),
        frames_json=json.dumps(body.frames),
        raw_path=str(raw_path),
        created_at=datetime.now(UTC),
    )
    db.add(row)
    db.commit()
    return _summary(row)


@router.get("")
def list_sessions(db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> list[dict]:
    rows = db.query(SessionRecord).filter(SessionRecord.user_id == user.id).order_by(SessionRecord.created_at.desc()).all()
    return [_summary(row) for row in rows]


@router.get("/{session_id}")
def get_session(session_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    row = db.get(SessionRecord, session_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Session not found")
    return {
        **_summary(row),
        "manifest": json.loads(row.manifest_json),
        "decisions": json.loads(row.decisions_json),
        "frames": json.loads(row.frames_json),
    }
