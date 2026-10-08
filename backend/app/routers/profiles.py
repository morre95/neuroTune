import json
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.audio import asset_path
from app.auth import get_current_user
from app.db import get_db
from app.models import AudioProfileVersion, AudioRender, User
from app.profiles import MixRecipe, ProfileSettings, ProfileVersion, render_body
from app.routers.audio import owned_asset

router = APIRouter(prefix='/audio', tags=['audio profiles'])


def owned_render(db, owner, render_id):
    render = db.query(AudioRender).filter_by(id=str(render_id), user_id=owner).one_or_none()
    if render is None:
        raise HTTPException(404, 'Render not found')
    return render


def owned_version(db, owner, version_id):
    version = db.query(AudioProfileVersion).filter_by(id=version_id, user_id=owner).one_or_none()
    if version is None:
        raise HTTPException(404, 'Profile version not found')
    return version


@router.post('/renders', status_code=202)
def create_render(recipe: MixRecipe, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    for track in recipe.tracks:
        asset = owned_asset(db, user.id, str(track.asset_id))
        if asset.status != 'ready':
            raise HTTPException(409, 'Choose a ready recording before rendering.')
        if round(track.trim_end_seconds * 48000) > round(asset.duration_seconds * 48000):
            raise HTTPException(422, 'Trim end must be within the recording.')
    render = AudioRender(id=str(uuid.uuid4()), user_id=user.id, recipe_json=recipe.model_dump_json(), created_at=datetime.now(UTC))
    db.add(render)
    db.commit()
    return render_body(render)


@router.get('/renders/{render_id}')
def read_render(render_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return render_body(owned_render(db, user.id, render_id))


@router.get('/renders/{render_id}/preview')
def preview_render(render_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    render = owned_render(db, user.id, render_id)
    if render.status != 'ready':
        raise HTTPException(409, 'Wait for a valid render before previewing.')
    return FileResponse(asset_path(user.id, render.id, 'preview.wav'), media_type='audio/wav', headers={'Cache-Control': 'private, no-store'})


def save_version(settings, user, db, profile_id=None):
    db.query(User).filter_by(id=user.id).with_for_update().one()
    previous = None
    if profile_id:
        previous = db.query(AudioProfileVersion).filter_by(profile_id=profile_id, user_id=user.id).order_by(AudioProfileVersion.version.desc()).first()
        if previous is None:
            raise HTTPException(404, 'Profile not found')
    render = owned_render(db, user.id, settings.render_id)
    if render.status != 'ready' or not render.checksum_sha256:
        raise HTTPException(409, 'Only a ready, valid render can be saved.')
    version_id = str(uuid.uuid4())
    now = datetime.now(UTC)
    body = dict(schema_version=1, id=version_id, owner_account_id=user.id, profile_id=profile_id or str(uuid.uuid4()),
        version=previous.version+1 if previous else 1, name=settings.name,
        background_asset_id=render.id, recipe=json.loads(render.recipe_json),
        carrier_hz=settings.carrier_hz, tone_gain=settings.tone_gain, background_gain=settings.background_gain,
        loop=settings.loop, duration_seconds=json.loads(render.recipe_json)['duration_seconds'],
        normalization_factor=render.normalization_factor, checksum_sha256=render.checksum_sha256,
        preview_checksum_sha256=render.preview_checksum_sha256,
        sample_rate_hz=48000, channels=2, sample_width_bytes=2, created_at=now.isoformat())
    db.add(AudioProfileVersion(id=version_id, profile_id=body['profile_id'], user_id=user.id,
        version=body['version'], render_id=render.id, body_json=json.dumps(body), created_at=now))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Another version was saved. Reload the profile and try again.')
    return body


@router.post('/profiles', status_code=201, response_model=ProfileVersion)
def create_profile(settings: ProfileSettings, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return save_version(settings, user, db)


@router.post('/profiles/{profile_id}/versions', status_code=201, response_model=ProfileVersion)
def revise_profile(profile_id: str, settings: ProfileSettings, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return save_version(settings, user, db, profile_id)


@router.get('/profiles', response_model=list[ProfileVersion])
def list_profiles(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Include all immutable versions so callers can resolve previously selected setups.
    return [json.loads(v.body_json) for v in db.query(AudioProfileVersion).filter_by(user_id=user.id).order_by(AudioProfileVersion.created_at.desc()).all()]


@router.get('/profiles/versions/{version_id}', response_model=ProfileVersion)
def read_version(version_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return json.loads(owned_version(db, user.id, version_id).body_json)


@router.get('/profiles/versions/{version_id}/download')
def download_version(version_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    version = owned_version(db, user.id, version_id)
    return FileResponse(asset_path(user.id, version.render_id, 'background.wav'), media_type='audio/wav', filename=f'{version.id}.wav', headers={'Cache-Control': 'private, no-store'})


@router.get('/profiles/versions/{version_id}/preview')
def preview_version(version_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    version = owned_version(db, user.id, version_id)
    return FileResponse(asset_path(user.id, version.render_id, 'preview.wav'), media_type='audio/wav', headers={'Cache-Control': 'private, no-store'})
