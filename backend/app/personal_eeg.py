"""Dedicated meditation learner. No NIR policies or window-level labels."""
import hashlib
import json
import uuid
from datetime import UTC, datetime

from app.eeg_model import QUALITY, extract_minutes, finite, train_model
from app.meditation import training_dataset
from app.models import MeditationFeedbackRecord, MeditationTrainingJob, PersonalEegModel, SessionDeletion, SessionRecord, User


def dataset_fingerprint(dataset):
    return hashlib.sha256(json.dumps(dataset, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def compatible(meta):
    config = meta.get('eeg_config')
    return (isinstance(config, dict) and meta.get('quality_version') == QUALITY
        and config.get('quality_version') == QUALITY and meta.get('playback_timeline_version') == 1
        and config.get('welch_window_seconds') == 4 and config.get('welch_hop_seconds') == 1
        and config.get('theta_hz') == [4.,8.] and config.get('alpha_hz') == [8.,13.]
        and config.get('beta_hz') == [13.,30.])


def session_rows(db, job):
    rows = []
    for entry in json.loads(job.dataset_json):
        sid = entry['session_id']
        record = db.get(SessionRecord, sid)
        if (record is None or record.user_id != job.user_id or record.origin != job.origin
            or record.checksum != entry['checksum_sha256'] or db.get(SessionDeletion,(job.user_id,sid)) is not None):
            raise ValueError('Training evidence changed')
        meta, rating = entry['meditation'], entry['feedback']
        if not compatible(meta):
            continue
        minutes = extract_minutes(json.loads(record.frames_json))
        if not minutes:
            continue
        busy, relaxed = rating.get('mental_busyness'), rating.get('relaxation')
        if not all(type(value) is int and 0 <= value <= 10 for value in [busy, relaxed]):
            continue
        profile = meta['profile']
        values = [profile.get(k) for k in ['carrier_hz','tone_gain','background_gain']]
        if not all(finite(v) for v in values):
            continue
        rows.append(dict(session_id=sid, checksum_sha256=record.checksum, feedback_revision=rating['revision'],
            target=(relaxed + 10 - busy)/2, features=[sum(m['features'][i] for m in minutes)/len(minutes) for i in [0,1]],
            minutes=minutes, fixed_action=meta['fixed_action'], profile_version_id=meta['profile_version_id'],
            background_asset_id=profile['background_asset_id'], eye_state=meta['eye_state'],
            carrier_hz=values[0], tone_gain=values[1], background_gain=values[2]))
    return rows


def evidence_current(db, owner, evidence):
    for item in evidence:
        sid = item['session_id']
        record = db.get(SessionRecord, sid)
        feedback = db.get(MeditationFeedbackRecord,(owner,sid))
        if (db.get(SessionDeletion,(owner,sid)) is not None or record is None or record.user_id != owner
            or record.checksum != item['checksum_sha256'] or feedback is None or feedback.revision != item['feedback_revision']):
            return False
    return True


def process_job(db, job):
    db.query(User).filter_by(id=job.user_id).with_for_update().one()
    db.refresh(job)
    if job.status != 'queued':
        return
    if dataset_fingerprint(training_dataset(db,job.user_id,job.origin,job.protocol_version)) != job.dataset_fingerprint:
        job.status, job.error = 'stale', 'Training evidence changed'
        db.commit()
        return
    body = train_model(session_rows(db,job))
    created = datetime.now(UTC)
    versions = db.query(PersonalEegModel).filter_by(user_id=job.user_id,origin=job.origin,protocol_version=job.protocol_version).all()
    version = f'v{max([int(v.model_version[1:]) for v in versions], default=0)+1}'
    mid = str(uuid.uuid4())
    body.update(id=mid,owner_account_id=job.user_id,origin=job.origin,model_version=version,
        dataset_fingerprint=job.dataset_fingerprint,server_deletion_epoch=0,created_at=created.isoformat())
    db.add(PersonalEegModel(id=mid,user_id=job.user_id,job_id=job.id,origin=job.origin,
        protocol_version=job.protocol_version,model_version=version,body_json=json.dumps(body,allow_nan=False),created_at=created))
    job.status, job.error = 'done', None
    db.commit()


def run_jobs(db):
    ids = [job.id for job in db.query(MeditationTrainingJob).filter_by(status='queued').all()]
    for jid in ids:
        job = db.get(MeditationTrainingJob,jid)
        try:
            process_job(db, job)
        except Exception:
            db.rollback()
            job = db.get(MeditationTrainingJob,jid)
            if job is not None:
                # Fail closed: never leave an older validated artifact advertised.
                created = datetime.now(UTC)
                mid=str(uuid.uuid4())
                versions=db.query(PersonalEegModel).filter_by(user_id=job.user_id,origin=job.origin,protocol_version=job.protocol_version).all()
                version=f'v{max([int(v.model_version[1:]) for v in versions], default=0)+1}'
                body=dict(schema_version=1,preprocessing_version='meditation-eeg-1',quality_version=QUALITY,
                    protocol_version=job.protocol_version,id=mid,owner_account_id=job.user_id,origin=job.origin,
                    model_version=version,dataset_fingerprint=job.dataset_fingerprint,server_deletion_epoch=0,
                    status='failed',reasons=['Training failed; collect more data or retry'],included_session_ids=[],evidence=[],
                    validation=dict(session_count=0,mae=None,correlation=None,context_mae=None,gates={}),created_at=created.isoformat())
                db.add(PersonalEegModel(id=mid,user_id=job.user_id,job_id=job.id,origin=job.origin,protocol_version=job.protocol_version,
                    model_version=version,body_json=json.dumps(body),created_at=created))
                job.status, job.error='failed','Training failed'
                db.commit()
    return len(ids)
