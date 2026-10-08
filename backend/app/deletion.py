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
    job_scopes = {}
    for job in db.query(MeditationTrainingJob).filter_by(user_id=owner).all():
        job_scopes[job.id] = (job.origin, job.protocol_version)
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
    revoked, retained, seen_scopes = set(), set(), set()
    for model in db.query(PersonalEegModel).filter_by(user_id=owner).order_by(
        PersonalEegModel.created_at.desc(), PersonalEegModel.id.desc()).all():
        scope = (model.origin, model.protocol_version)
        latest = scope not in seen_scopes
        seen_scopes.add(scope)
        try:
            body = json.loads(model.body_json)
            included = body['included_session_ids']
            if not isinstance(included, list) or set(included).intersection(ids):
                revoked.add(scope)
                db.delete(model)
            else:
                if latest and body.get('status') != 'revoked':
                    retained.add(scope)
                if model.job_id in affected:
                    model.job_id = None
        except (ValueError, TypeError, KeyError):
            revoked.add(scope)
            db.delete(model)
    db.flush()
    if affected:
        db.query(MeditationTrainingRequest).filter(MeditationTrainingRequest.user_id == owner,
            MeditationTrainingRequest.job_id.in_(affected)).delete(synchronize_session=False)
        db.query(MeditationTrainingJob).filter(MeditationTrainingJob.user_id == owner,
            MeditationTrainingJob.id.in_(affected)).delete(synchronize_session=False)
    # A pending first fit needs rebuilding too. Excluded-only deletion preserves
    # an already retained artifact rather than forcing new collection.
    return revoked | ({job_scopes[jid] for jid in affected if jid in job_scopes} - retained)


def rebuild_meditation_evidence(db, owner, scopes):
    """Caller holds User lock; recordings/ratings have already been retired.

    A latest marker prevents historical ready resurrection. Jobs retain their
    canonical dataset key; reusing a historical job detaches its optional model
    FK before the worker publishes a new opaque version.
    """
    import uuid
    from datetime import UTC, datetime
    from app.meditation import training_dataset
    from app.personal_eeg import dataset_fingerprint
    from app.eeg_model import PREPROCESSING, QUALITY

    for origin, protocol in sorted(scopes):
        dataset = training_dataset(db, owner, origin, protocol)
        fingerprint = dataset_fingerprint(dataset)
        job = db.query(MeditationTrainingJob).filter_by(user_id=owner, origin=origin,
            protocol_version=protocol, dataset_fingerprint=fingerprint).one_or_none()
        if job is None:
            job = MeditationTrainingJob(id=str(uuid.uuid4()), user_id=owner, origin=origin,
                protocol_version=protocol, dataset_fingerprint=fingerprint,
                dataset_json=json.dumps(dataset, sort_keys=True, separators=(',', ':')),
                status='queued', created_at=datetime.now(UTC))
            db.add(job)
        else:
            for model in db.query(PersonalEegModel).filter_by(user_id=owner, job_id=job.id).all():
                model.job_id = None
            job.status, job.error = 'queued', None
        mid, created = str(uuid.uuid4()), datetime.now(UTC)
        body = dict(schema_version=1, preprocessing_version=PREPROCESSING, quality_version=QUALITY,
            protocol_version=protocol, id=mid, owner_account_id=owner, origin=origin,
            model_version=PREPROCESSING + ':' + mid, dataset_fingerprint=fingerprint,
            server_deletion_epoch=read_deletion_epoch(db, owner), created_at=created.isoformat(),
            status='revoked', reasons=['Deleted learning evidence; rebuilding from remaining fixed sessions'],
            included_session_ids=[], evidence=[], fixed_minutes=[],
            validation=dict(session_count=0, mae=None, correlation=None, context_mae=None, gates={}))
        db.add(PersonalEegModel(id=mid, user_id=owner, job_id=None, origin=origin,
            protocol_version=protocol, model_version=body['model_version'],
            body_json=json.dumps(body), created_at=created))
    db.flush()
