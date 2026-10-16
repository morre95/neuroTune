"""Private project CRUD; legacy endpoint error formats remain unchanged."""
from datetime import datetime

import jwt
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import settings
from app.db import get_db
from app.models import AudioProject, AudioProjectRevision, User
from app.projects import (CreateProject, Identifier, SaveProject, fail,
                          owned_project, project_body, utc, write_project)


class ProjectRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handle(request):
            try:
                response = await original(request)
                response.headers['Cache-Control'] = 'private, no-store'
                return response
            except RequestValidationError as exc:
                error = exc.errors()[0]
                message = error['msg']
                details = dict(field='/' + '/'.join(map(str, error['loc'])))
                for rule in ('S1', 'S2', 'S3', 'S5'):
                    if f'{rule}:' in message:
                        details['rule'] = rule
                fail(422, 'INVALID_REQUEST', message, **details)
            except HTTPException as exc:
                if isinstance(exc.detail, dict):
                    raise
                code = 'UNAUTHORIZED' if exc.status_code == 401 else 'INVALID_REQUEST'
                raise HTTPException(exc.status_code, dict(code=code, message=str(exc.detail)), headers=exc.headers) from exc

        return handle


router = APIRouter(prefix='/audio/projects', tags=['audio projects'], route_class=ProjectRoute)


@router.post('', status_code=201)
def create_project(body: CreateProject, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return write_project(db, user.id, str(body.project_id), body, create=True)


@router.get('')
def list_projects(cursor: str | None = Query(default=None, max_length=2048),
                  limit: int = Query(default=20, ge=1, le=100),
                  user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(AudioProject, AudioProjectRevision).join(AudioProjectRevision, and_(
        AudioProjectRevision.project_id == AudioProject.id,
        AudioProjectRevision.revision == AudioProject.revision,
        AudioProjectRevision.user_id == AudioProject.user_id)).filter(AudioProject.user_id == user.id)
    if cursor:
        try:
            values = jwt.decode(cursor, settings.jwt_secret, algorithms=['HS256'])
            if values['typ'] != 'audio-project-cursor' or values['owner'] != user.id:
                raise ValueError('account or cursor type')
            timestamp = datetime.fromisoformat(values['updated_at'])
            if timestamp.tzinfo is None or not isinstance(values['id'], str):
                raise ValueError('cursor position')
        except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
            fail(422, 'INVALID_CURSOR', 'Cursor is invalid for this account.')
        query = query.filter(or_(AudioProject.updated_at < timestamp,
            and_(AudioProject.updated_at == timestamp, AudioProject.id < values['id'])))
    heads = query.order_by(AudioProject.updated_at.desc(), AudioProject.id.desc()).limit(limit + 1).all()
    items = [project_body(head, revision) for head, revision in heads[:limit]]
    next_cursor = None
    if len(heads) > limit:
        last = heads[limit - 1][0]
        next_cursor = jwt.encode(dict(typ='audio-project-cursor', owner=user.id,
            updated_at=utc(last.updated_at), id=last.id), settings.jwt_secret, algorithm='HS256')
    return dict(items=items, next_cursor=next_cursor)


@router.get('/{project_id}')
def read_project(project_id: Identifier, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    head = owned_project(db, user.id, str(project_id))
    return project_body(head, db.get(AudioProjectRevision, (head.id, head.revision)))


@router.put('/{project_id}')
def save_project(project_id: Identifier, body: SaveProject,
                 user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return write_project(db, user.id, str(project_id), body, create=False)
