import hashlib
import uuid
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.audio import MAX_SOURCE_BYTES, asset_path, asset_body
from app.db import get_db
from app.models import AudioAsset, User

router = APIRouter(prefix="/audio/assets", tags=["audio"])
FORMATS = {".wav": "wav", ".mp3": "mp3", ".m4a": "mov", ".aac": "aac", ".flac": "flac"}


def owned_asset(db: Session, user_id: str, asset_id: str) -> AudioAsset:
    asset = db.query(AudioAsset).filter_by(id=asset_id, user_id=user_id).one_or_none()
    if asset is None:
        raise HTTPException(404, "Audio asset not found")
    return asset


@router.post("", status_code=202)
async def upload(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    filename = Path(unquote(request.headers.get("X-Audio-Filename", ""))).name
    source_format = FORMATS.get(Path(filename).suffix.lower())
    if not source_format or len(filename) > 255:
        raise HTTPException(400, "Choose a WAV, MP3, M4A/AAC, or FLAC recording.")
    length = request.headers.get("Content-Length")
    if length and (not length.isdigit() or int(length) > MAX_SOURCE_BYTES):
        raise HTTPException(413, "Recording must be no larger than 100 MiB.")
    asset_id = str(uuid.uuid4())
    path = asset_path(user.id, asset_id, "original")
    path.parent.mkdir(parents=True, exist_ok=True)
    size = 0
    digest = hashlib.sha256()
    try:
        with path.open("xb") as target:
            async for chunk in request.stream():
                size += len(chunk)
                if size > MAX_SOURCE_BYTES:
                    raise HTTPException(413, "Recording must be no larger than 100 MiB.")
                target.write(chunk)
                digest.update(chunk)
        if not size:
            raise HTTPException(400, "Recording is empty. Choose a playable audio file.")
        asset = AudioAsset(id=asset_id, user_id=user.id, filename=filename,
            source_format=source_format, original_bytes=size, original_sha256=digest.hexdigest(),
            created_at=datetime.now(UTC), status="pending")
        db.add(asset)
        db.commit()
    except BaseException:
        db.rollback()
        path.unlink(missing_ok=True)
        raise
    return asset_body(asset)


@router.get("")
def list_assets(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return [asset_body(asset) for asset in db.query(AudioAsset).filter_by(user_id=user.id).order_by(AudioAsset.created_at.desc()).all()]


@router.get("/{asset_id}")
def read_asset(asset_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return asset_body(owned_asset(db, user.id, asset_id))


@router.get("/{asset_id}/download")
def download(asset_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    asset = owned_asset(db, user.id, asset_id)
    if asset.status != "ready":
        raise HTTPException(409, "Audio is not ready. Wait for processing or upload a corrected recording.")
    return FileResponse(asset_path(user.id, asset.id, "canonical.wav"), media_type="audio/wav", filename=f"{asset.id}.wav", headers={"Cache-Control": "private, no-store"})
