import json
import hashlib
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import CalibrationPlanRecord, User, MeditationFeedbackRecord, MeditationTrainingJob, MeditationTrainingRequest
from app.meditation import PlanIn, require_profile, FeedbackIn, owned_recording, validate_meditation, TrainingIn, training_dataset

router = APIRouter(prefix='/meditation', tags=['meditation'])


@router.post('/calibration-plans')
def create_plan(body: PlanIn, response: Response, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    db.query(User).filter_by(id=user.id).with_for_update().one()
    if str(body.owner_account_id) != user.id:
        raise HTTPException(404, 'Plan not found')
    require_profile(db, user.id, body.profile)
    row = db.get(CalibrationPlanRecord, str(body.id))
    value = body.model_dump(mode='json')
    if row is not None:
        if row.user_id != user.id:
            raise HTTPException(404, 'Plan not found')
        if PlanIn.model_validate(json.loads(row.body_json)) != body:
            raise HTTPException(409, 'Immutable plan conflict')
        return json.loads(row.body_json)
    row = CalibrationPlanRecord(id=str(body.id), user_id=user.id, body_json=json.dumps(value), created_at=body.created_at)
    db.add(row)
    db.commit()
    response.status_code = 201
    return value


@router.get('/calibration-plans')
def list_plans(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return [json.loads(p.body_json) for p in db.query(CalibrationPlanRecord).filter_by(user_id=user.id).all()]


@router.get('/calibration-plans/{plan_id}')
def read_plan(plan_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    row = db.get(CalibrationPlanRecord, plan_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(404, 'Plan not found')
    return json.loads(row.body_json)


@router.post('/sessions/{session_id}/feedback')
def save_feedback(session_id: str, body: FeedbackIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    db.query(User).filter_by(id=user.id).with_for_update().one()
    row = owned_recording(db, user.id, session_id)
    if str(body.owner_account_id) != user.id or body.session_id != session_id:
        raise HTTPException(404, 'Feedback not found')
    validate_meditation(db, user.id, json.loads(row.manifest_json), completed=True)
    value = body.model_dump(mode='json')
    existing = db.get(MeditationFeedbackRecord, (user.id, session_id))
    if existing is not None:
        if body.revision < existing.revision or (body.revision == existing.revision and json.loads(existing.body_json) != value):
            raise HTTPException(409, 'Feedback revision conflict')
        if body.revision == existing.revision:
            return value
        existing.revision, existing.body_json, existing.updated_at = body.revision, json.dumps(value), datetime.now(UTC)
    else:
        db.add(MeditationFeedbackRecord(user_id=user.id, session_id=session_id, revision=body.revision,
            body_json=json.dumps(value), updated_at=datetime.now(UTC)))
    db.commit()
    return value


@router.get('/sessions/{session_id}/feedback')
def read_feedback(session_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    owned_recording(db, user.id, session_id)
    row = db.get(MeditationFeedbackRecord, (user.id, session_id))
    if row is None:
        raise HTTPException(404, 'Feedback not found')
    return json.loads(row.body_json)


def job_body(job):
    return dict(id=job.id, schema_version=1, origin=job.origin, protocol_version=job.protocol_version,
        dataset_fingerprint=job.dataset_fingerprint, status=job.status, error=job.error)


@router.post('/training/jobs', status_code=202)
def create_training(body: TrainingIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    db.query(User).filter_by(id=user.id).with_for_update().one()
    recording = owned_recording(db, user.id, body.session_id)
    meta = validate_meditation(db, user.id, json.loads(recording.manifest_json), completed=True)
    ratings = db.get(MeditationFeedbackRecord, (user.id, body.session_id))
    if (meta['mode'] not in {'fixed', 'calibration'} or ratings is None
        or ratings.revision != body.feedback_revision or meta['origin'] != body.origin
        or meta['protocol_version'] != body.protocol_version):
        raise HTTPException(409, 'Training context or feedback revision mismatch')
    value = body.model_dump(mode='json')
    existing = db.get(MeditationTrainingRequest, str(body.request_id))
    if existing is not None:
        if existing.user_id != user.id:
            raise HTTPException(404, 'Request not found')
        if json.loads(existing.body_json) != value:
            raise HTTPException(409, 'Training request conflict')
        return job_body(db.get(MeditationTrainingJob, existing.job_id))
    dataset = json.dumps(training_dataset(db, user.id, body.origin, body.protocol_version), sort_keys=True, separators=(',', ':'))
    fingerprint = hashlib.sha256(dataset.encode()).hexdigest()
    job = db.query(MeditationTrainingJob).filter_by(user_id=user.id, origin=body.origin,
        protocol_version=body.protocol_version, dataset_fingerprint=fingerprint).one_or_none()
    if job is None:
        job = MeditationTrainingJob(id=str(uuid.uuid4()), user_id=user.id, origin=body.origin,
            protocol_version=body.protocol_version, dataset_fingerprint=fingerprint, dataset_json=dataset,
            status='queued', created_at=datetime.now(UTC))
        db.add(job)
        db.flush()
    db.add(MeditationTrainingRequest(id=str(body.request_id), user_id=user.id, job_id=job.id, body_json=json.dumps(value)))
    db.commit()
    return job_body(job)


@router.get('/training/jobs/{job_id}')
def read_training(job_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    job = db.get(MeditationTrainingJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(404, 'Job not found')
    return job_body(job)
