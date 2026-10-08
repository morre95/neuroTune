"""Owned immutable contexts and independent revisioned outcomes."""
import json
import math
import uuid
from collections import Counter
from datetime import UTC, datetime
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models import AudioProfileVersion
from app.profiles import ProfileVersion

ACTIONS = {'control', 'binaural_6', 'binaural_8', 'binaural_10', 'binaural_12'}
PROTOCOL = 'meditation-1'


class PlanIn(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schema_version: int = Field(strict=True, ge=1, le=1)
    id: uuid.UUID
    owner_account_id: uuid.UUID
    protocol_version: Literal['meditation-1']
    profile_version_id: uuid.UUID
    profile: ProfileVersion
    eye_state: Literal['open', 'closed']
    origin: Literal['muse', 'simulator']
    duration_seconds: int = Field(strict=True, ge=600, le=600)
    schedule: list[str] = Field(min_length=10, max_length=10)
    created_at: datetime

    @model_validator(mode='after')
    def balanced(self):
        if Counter(self.schedule) != Counter({a: 2 for a in ACTIONS}):
            raise ValueError('Each action must occur twice')
        if self.profile.id != self.profile_version_id or self.profile.owner_account_id != self.owner_account_id:
            raise ValueError('Profile context mismatch')
        if self.created_at.tzinfo is None:
            raise ValueError('Plan time must include a timezone')
        self.profile.created_at = datetime.fromisoformat(self.profile.created_at.replace('Z', '+00:00')).astimezone(UTC).isoformat()
        return self


def require_profile(db, owner, profile):
    stored = db.query(AudioProfileVersion).filter_by(id=str(profile.id), user_id=owner).one_or_none()
    if stored is None:
        raise HTTPException(404, 'Profile version not found')
    expected = ProfileVersion.model_validate(json.loads(stored.body_json))
    # Profile created_at is a display string; normalize its equivalent UTC encoding.
    a, b = profile.model_dump(mode='json'), expected.model_dump(mode='json')
    try:
        for body in (a, b):
            timestamp = datetime.fromisoformat(body['created_at'].replace('Z', '+00:00'))
            if timestamp.tzinfo is None:
                raise ValueError('Missing timezone')
            body['created_at'] = timestamp.astimezone(UTC).isoformat()
    except (ValueError, TypeError):
        raise HTTPException(422, 'Invalid profile timestamp') from None
    if a != b or str(profile.owner_account_id) != owner:
        raise HTTPException(409, 'Profile snapshot mismatch')


class FeedbackIn(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schema_version: int = Field(strict=True, ge=1, le=1)
    owner_account_id: uuid.UUID
    session_id: str = Field(pattern=r'^[A-Za-z0-9_-]{1,64}$')
    mental_busyness: int = Field(strict=True, ge=0, le=10)
    relaxation: int = Field(strict=True, ge=0, le=10)
    revision: int = Field(strict=True, ge=1)


def is_meditation_manifest(manifest):
    """Reserved markers protect routing even for rows saved by older versions."""
    return (manifest.get('meditation') is not None or manifest.get('mode') == 'meditation'
        or manifest.get('experiment_version') == PROTOCOL)


def validate_meditation(db, owner, manifest, completed=False):
    from app.models import CalibrationPlanRecord
    from pydantic import ValidationError
    meta = manifest.get('meditation')
    if not isinstance(meta, dict):
        raise HTTPException(422, 'Meditation context required')
    if any(not isinstance(meta.get(key), str) for key in ('mode', 'fixed_action', 'origin', 'eye_state')):
        raise HTTPException(422, 'Invalid meditation scalar metadata')
    try:
        profile = ProfileVersion.model_validate(meta.get('profile'))
    except ValidationError:
        raise HTTPException(422, 'Invalid profile context') from None
    require_profile(db, owner, profile)
    frames = meta.get('played_frames')
    duration = manifest.get('duration_seconds')
    if (meta.get('schema_version') != 1 or meta.get('protocol_version') != PROTOCOL
        or manifest.get('experiment_version') != PROTOCOL or manifest.get('mode') != 'meditation'
        or meta.get('mode') not in {'fixed', 'calibration', 'adaptive'}
        or meta.get('owner_account_id', owner) != owner
        or meta.get('profile_version_id') != str(profile.id)
        or meta.get('fixed_action') not in ACTIONS
        or meta.get('origin') not in {'muse', 'simulator'}
        or meta.get('origin') != manifest.get('data_origin')
        or meta.get('eye_state') not in {'open', 'closed'} or meta.get('eye_state') != manifest.get('eye_state')
        or type(frames) is not int or not 0 <= frames <= 28800000
        or type(duration) not in {int, float} or not math.isfinite(duration) or abs(duration - frames / 48000) > 1e-6):
        raise HTTPException(422, 'Meditation metadata mismatch')
    if completed and (frames != 28800000 or manifest.get('ended_in_phase') != 'completed' or manifest.get('stop_reason') is not None):
        raise HTTPException(409, 'Feedback requires 600 completed active seconds')
    if meta['mode'] == 'calibration':
        plan_id = meta.get('calibration_plan_id')
        if not isinstance(plan_id, str):
            raise HTTPException(422, 'Invalid calibration plan identifier')
        try:
            uuid.UUID(plan_id)
        except ValueError:
            raise HTTPException(422, 'Invalid calibration plan identifier') from None
        plan = db.get(CalibrationPlanRecord, plan_id)
        if plan is None or plan.user_id != owner:
            raise HTTPException(404, 'Calibration plan not found')
        body = PlanIn.model_validate(json.loads(plan.body_json))
        slot = meta.get('calibration_slot')
        if (type(slot) is not int or not 0 <= slot < 10 or meta.get('calibration_schema_version') != 1
            or meta.get('owner_account_id') != owner or meta['fixed_action'] != body.schedule[slot]
            or meta['origin'] != body.origin or meta['eye_state'] != body.eye_state
            or profile.model_dump(exclude={'created_at'}) != body.profile.model_dump(exclude={'created_at'})):
            raise HTTPException(422, 'Calibration context mismatch')
    return meta


def owned_recording(db, owner, session_id):
    from app.models import SessionDeletion, SessionRecord
    if db.get(SessionDeletion, (owner, session_id)) is not None:
        raise HTTPException(410, 'Session was deleted')
    row = db.get(SessionRecord, session_id)
    if row is None or row.user_id != owner:
        raise HTTPException(404, 'Session not found')
    return row


class TrainingIn(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schema_version: int = Field(strict=True, ge=1, le=1)
    request_id: uuid.UUID
    session_id: str = Field(pattern=r'^[A-Za-z0-9_-]{1,64}$')
    feedback_revision: int = Field(strict=True, ge=1)
    origin: Literal['muse', 'simulator']
    protocol_version: Literal['meditation-1']


def training_dataset(db, owner, origin, protocol):
    from app.models import SessionRecord, MeditationFeedbackRecord
    result = []
    for recording in db.query(SessionRecord).filter_by(user_id=owner, origin=origin, experiment_version=protocol).order_by(SessionRecord.id).all():
        manifest = json.loads(recording.manifest_json)
        meta = manifest.get('meditation')
        if not isinstance(meta, dict) or meta.get('mode') not in {'fixed', 'calibration'}:
            continue
        try:
            validate_meditation(db, owner, manifest, completed=True)
        except HTTPException:
            continue
        ratings = db.get(MeditationFeedbackRecord, (owner, recording.id))
        if ratings is not None:
            result.append(dict(session_id=recording.id, checksum_sha256=recording.checksum,
                feedback=json.loads(ratings.body_json), meditation=meta))
    return result
