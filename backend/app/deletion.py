"""Deletion seams used by model publication without inventing model cleanup."""
import json

from app.models import (OwnerDeletionEpoch, SessionDeletion, MeditationFeedbackRecord,
    MeditationTrainingJob, MeditationTrainingRequest, PersonalEegModel)


def read_deletion_epoch(db, owner):
    row = db.get(OwnerDeletionEpoch, owner)
    return row.epoch if row is not None else 0


def bump_deletion_epoch(db, owner):
    """Caller holds the User row lock; helper does not commit its transaction."""
    row = db.get(OwnerDeletionEpoch, owner)
    if row is None:
        row = OwnerDeletionEpoch(user_id=owner, epoch=1)
        db.add(row)
    else:
        row.epoch += 1
    db.flush()
    return row.epoch


def session_is_deleted(db, owner, session_id):
    return db.get(SessionDeletion, (owner, session_id)) is not None


def remove_meditation_evidence(db, owner, session_ids):
    """Remove ratings and snapshots/aliases containing the deleted evidence."""
    ids = set(session_ids)
    db.query(MeditationFeedbackRecord).filter(MeditationFeedbackRecord.user_id == owner,
        MeditationFeedbackRecord.session_id.in_(ids)).delete(synchronize_session=False)
    affected = set()
    for job in db.query(MeditationTrainingJob).filter_by(user_id=owner).all():
        try:
            dataset = json.loads(job.dataset_json)
            if not isinstance(dataset, list):
                raise ValueError('Unsupported dataset')
            if any(isinstance(item, dict) and item.get('session_id') in ids for item in dataset):
                affected.add(job.id)
        except (ValueError, TypeError):
            # An unreadable snapshot cannot be proven free of deleted evidence.
            affected.add(job.id)
    for request in db.query(MeditationTrainingRequest).filter_by(user_id=owner).all():
        try:
            if json.loads(request.body_json).get('session_id') in ids:
                affected.add(request.job_id)
        except (ValueError, TypeError, AttributeError):
            affected.add(request.job_id)
    # Models include only usable rows; a removed job snapshot can also
    # contain an unusable session which never influenced the fitted model.
    for model in db.query(PersonalEegModel).filter_by(user_id=owner).all():
        try:
            body = json.loads(model.body_json)
            included = body['included_session_ids']
            if not isinstance(included, list) or set(included).intersection(ids):
                db.delete(model)
            elif model.job_id in affected:
                model.job_id = None
        except (ValueError, TypeError, KeyError):
            db.delete(model)
    db.flush()
    if affected:
        db.query(MeditationTrainingRequest).filter(MeditationTrainingRequest.user_id == owner,
            MeditationTrainingRequest.job_id.in_(affected)).delete(synchronize_session=False)
        db.query(MeditationTrainingJob).filter(MeditationTrainingJob.user_id == owner,
            MeditationTrainingJob.id.in_(affected)).delete(synchronize_session=False)
