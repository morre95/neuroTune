"""Project contracts and atomic revision/idempotency writes (A3/B2)."""
import hashlib
import json
import math
import re
import uuid
import wave
from datetime import UTC, datetime
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import HTTPException
from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, model_validator
from sqlalchemy import text, update
from sqlalchemy.exc import IntegrityError, OperationalError

from app.audio import asset_path
from app.models import (AudioAsset, AudioProfileVersion, AudioProject,
                        AudioProjectRequest, AudioProjectRevision,
                        AudioProjectSourceReference, AudioRender)

MAX_FRAMES = 172800000
MAX_REVISION = 9007199254740991


def numeric(value):
    if type(value) not in (int, float) or (type(value) is float and not math.isfinite(value)):
        raise ValueError('Expected a finite JSON number, not a boolean or string.')
    return value


def identifier(value):
    if isinstance(value, uuid.UUID):
        return value
    if not isinstance(value, str) or not re.fullmatch(
            r'[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', value):
        raise ValueError('Expected a UUID.')
    return value


Integer = Annotated[int, BeforeValidator(numeric)]
Number = Annotated[float, BeforeValidator(numeric)]
Identifier = Annotated[uuid.UUID, BeforeValidator(identifier)]


class Contract(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Source(Contract):
    id: Identifier
    kind: Literal['asset']
    asset_id: Identifier
    frame_count: Integer = Field(ge=1, le=MAX_FRAMES)
    checksum_sha256: str = Field(pattern=r'^[0-9a-f]{64}$')


class ProfileSource(Source):
    kind: Literal['profile_background']
    profile_version_id: Identifier


class Cut(Contract):
    kind: Literal['cut']
    frames: Annotated[Literal[0], BeforeValidator(numeric)]


class Crossfade(Contract):
    kind: Literal['crossfade']
    curve: Literal['linear']
    frames: Integer = Field(ge=1, le=480000)


class Clip(Contract):
    id: Identifier
    source_id: Identifier
    start_frame: Integer = Field(ge=0, lt=MAX_FRAMES)
    end_frame: Integer = Field(ge=1, le=MAX_FRAMES)
    gain: Number = Field(ge=0, le=4)
    transition_after: Cut | Crossfade = Field(discriminator='kind')


class SequenceRecipe(Contract):
    schema_version: Annotated[Literal[1], BeforeValidator(numeric)]
    kind: Literal['audio_sequence']
    sample_rate_hz: Annotated[Literal[48000], BeforeValidator(numeric)]
    channels: Annotated[Literal[2], BeforeValidator(numeric)]
    sample_width_bytes: Annotated[Literal[2], BeforeValidator(numeric)]
    sources: list[Annotated[Source | ProfileSource, Field(discriminator='kind')]]
    clips: list[Clip] = Field(max_length=100)
    frame_count: Integer = Field(ge=0, le=MAX_FRAMES)

    @model_validator(mode='after')
    def sequence_rules(self):
        sources = {source.id: source for source in self.sources}
        if len(sources) != len(self.sources) or len({c.id for c in self.clips}) != len(self.clips):
            raise ValueError('S1: Source and clip IDs must be unique.')
        incoming, total = 0, 0
        for index, clip in enumerate(self.clips):
            source = sources.get(clip.source_id)
            if source is None or not 0 <= clip.start_frame < clip.end_frame <= source.frame_count:
                raise ValueError('S1: Trim must be inside its source.')
            length, outgoing = clip.end_frame - clip.start_frame, clip.transition_after.frames
            if (index == len(self.clips) - 1 and clip.transition_after.kind != 'cut') or incoming + outgoing > length:
                raise ValueError('S3: Transitions must fit both neighbours without triple overlap; last clip must cut.')
            total += length - outgoing
            incoming = outgoing
        if total != self.frame_count:
            raise ValueError('S2: frame_count must equal the exact sequence length.')
        return self


class FixedPolicy(Contract):
    mode: Literal['fixed']


class SelectablePolicy(Contract):
    mode: Literal['selectable']
    default: Literal['full_file']
    minimum_minutes: Annotated[Literal[1], BeforeValidator(numeric)]
    maximum_minutes: Annotated[Literal[60], BeforeValidator(numeric)]
    step_minutes: Annotated[Literal[1], BeforeValidator(numeric)]


class PublicationSettings(Contract):
    carrier_hz: Number = Field(ge=100, le=400)
    tone_gain: Number = Field(ge=0, le=.95)
    background_gain: Number = Field(ge=0, le=.95)
    playback_policy: FixedPolicy | SelectablePolicy = Field(discriminator='mode')

    @model_validator(mode='after')
    def headroom(self):
        if Decimal(str(self.tone_gain)) + Decimal(str(self.background_gain)) > Decimal('.95'):
            raise ValueError('S5: Tone and background gains must total at most 0.95.')
        return self


class ProjectContents(Contract):
    name: str = Field(min_length=1, max_length=120)
    recipe: SequenceRecipe
    settings: PublicationSettings

    @model_validator(mode='after')
    def named(self):
        if not self.name.strip():
            raise ValueError('Give the project a name.')
        return self


class CreateProject(ProjectContents):
    request_id: Identifier
    project_id: Identifier


class SaveProject(ProjectContents):
    request_id: Identifier
    expected_revision: Integer = Field(ge=1, le=MAX_REVISION)


def fail(status, code, message, **details):
    raise HTTPException(status, dict(code=code, message=message, **details))


def owned_project(db, owner, project_id):
    head = db.query(AudioProject).filter_by(id=project_id, user_id=owner).one_or_none()
    if head is None:
        fail(404, 'NOT_FOUND', 'Project not found.')
    return head


def utc(value):
    # SQLite drops timezone information; all persisted project times are UTC.
    return value.replace(tzinfo=UTC).isoformat().replace('+00:00', 'Z')


def project_body(head, revision):
    return dict(schema_version=1, kind='audio_project', id=head.id,
        owner_account_id=head.user_id, revision=revision.revision, name=revision.name,
        recipe=json.loads(revision.recipe_json), settings=json.loads(revision.settings_json),
        created_at=utc(head.created_at), updated_at=utc(revision.created_at))


def checksum(stream):
    return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_sources(db, owner, recipe):
    verified = {}
    for source in recipe.sources:
        asset_id = str(source.asset_id)
        if asset_id not in verified:
            asset = db.query(AudioAsset).filter_by(id=asset_id, user_id=owner).with_for_update().one_or_none()
            if asset is None:
                fail(404, 'NOT_FOUND', 'Source not found.')
            if asset.status != 'ready' or not asset.checksum_sha256:
                fail(422, 'INVALID_SOURCE', 'Choose a ready source.', rule='S1')
            try:
                # One open descriptor checks header, complete PCM length and hash;
                # no whole-file allocation, including for one-hour sources.
                with asset_path(owner, asset_id, 'canonical.wav').open('rb') as stream:
                    with wave.open(stream, 'rb') as audio:
                        frames = audio.getnframes()
                        if not 1 <= frames <= MAX_FRAMES:
                            raise ValueError('duration')
                        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (2, 2, 48000, 'NONE'):
                            raise ValueError('format')
                        remaining = frames * 4
                        while remaining:
                            chunk = audio.readframes(min(16384, (remaining + 3) // 4))
                            if not chunk:
                                raise ValueError('truncated')
                            remaining -= len(chunk)
                    stream.seek(0)
                    digest = checksum(stream)
                if not 1 <= frames <= MAX_FRAMES or digest != asset.checksum_sha256:
                    raise ValueError('metadata')
            except (OSError, EOFError, ValueError, wave.Error):
                fail(422, 'INVALID_SOURCE', 'Source audio is unavailable or invalid.', rule='S1')
            verified[asset_id] = (frames, digest)
        if verified[asset_id] != (source.frame_count, source.checksum_sha256):
            fail(422, 'INVALID_SOURCE', 'Source metadata does not match its audio.', rule='S1')
        if isinstance(source, ProfileSource):
            version = db.query(AudioProfileVersion).filter_by(
                id=str(source.profile_version_id), user_id=owner).with_for_update().one_or_none()
            if version is None:
                fail(404, 'NOT_FOUND', 'Profile version not found.')
            render = db.query(AudioRender).filter_by(id=version.render_id, user_id=owner).one_or_none()
            body = json.loads(version.body_json)
            frames = body.get('frame_count', round(body.get('duration_seconds', 0) * 48000))
            if (render is None or render.status != 'ready' or
                    render.checksum_sha256 != source.checksum_sha256 or
                    body.get('checksum_sha256') != source.checksum_sha256 or frames != source.frame_count):
                fail(422, 'INVALID_SOURCE', 'Source does not match the published background.', rule='S1')


def replay(receipt, project_id, digest):
    if receipt.project_id != project_id or receipt.payload_sha256 != digest:
        fail(409, 'REQUEST_ID_REUSE', 'This request ID was already used with different contents or project.')
    return json.loads(receipt.response_json)


def write_project(db, owner, project_id, request, *, create):
    operation = 'create' if create else 'save'
    data = request.model_dump(mode='json')
    digest = hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    key = (owner, operation, str(request.request_id))
    previous = db.get(AudioProjectRequest, key)
    if previous is not None:
        return replay(previous, project_id, digest)
    # Discard the auth/read transaction before taking the atomic write claim.
    db.rollback()
    connection = db.connection()
    sqlite = connection.dialect.name == 'sqlite'
    raw = connection.connection.driver_connection if sqlite else None
    old_timeout = raw.execute('PRAGMA busy_timeout').fetchone()[0] if sqlite else None
    if sqlite:
        connection.exec_driver_sql('PRAGMA busy_timeout=0')
    elif connection.dialect.name == 'postgresql':
        connection.execute(text("SET LOCAL lock_timeout = '1ms'"))
    try:
        now = datetime.now(UTC)
        receipt = AudioProjectRequest(user_id=owner, operation=operation,
            request_id=key[2], project_id=project_id, payload_sha256=digest,
            response_json='{}', created_at=now)
        db.add(receipt)
        db.flush()  # Unique claim and result stay in the same transaction.
        if create:
            existing = db.get(AudioProject, project_id)
            if existing is not None:
                if existing.user_id != owner:
                    fail(404, 'NOT_FOUND', 'Project not found.')
                fail(409, 'PROJECT_EXISTS', 'Project already exists. Read it before saving.')
            head = AudioProject(id=project_id, user_id=owner, revision=1,
                created_at=now, updated_at=now)
            db.add(head)
            db.flush()
            revision_number = 1
        else:
            head = owned_project(db, owner, project_id)
            if head.revision != request.expected_revision:
                fail(409, 'REVISION_CONFLICT', 'A newer project revision has been saved.',
                    project_id=project_id, expected_revision=request.expected_revision, current_revision=head.revision)
            if head.revision == MAX_REVISION:
                fail(409, 'REVISION_LIMIT', 'Project revision limit reached.')
            revision_number = head.revision + 1
            changed = db.execute(update(AudioProject).where(AudioProject.id == project_id,
                AudioProject.user_id == owner, AudioProject.revision == request.expected_revision)
                .values(revision=revision_number, updated_at=now))
            if changed.rowcount != 1:
                db.refresh(head)
                fail(409, 'REVISION_CONFLICT', 'A newer project revision has been saved.',
                    project_id=project_id, expected_revision=request.expected_revision, current_revision=head.revision)
        validate_sources(db, owner, request.recipe)
        revision = AudioProjectRevision(project_id=project_id, revision=revision_number,
            user_id=owner, name=request.name, recipe_json=request.recipe.model_dump_json(),
            settings_json=request.settings.model_dump_json(), created_at=now)
        db.add(revision)
        db.flush()
        for source in request.recipe.sources:
            db.add(AudioProjectSourceReference(project_id=project_id, revision=revision_number,
                user_id=owner, source_id=str(source.id), asset_id=str(source.asset_id),
                kind=source.kind, profile_version_id=str(source.profile_version_id)
                if isinstance(source, ProfileSource) else None))
        result = project_body(head, revision)
        receipt.response_json = json.dumps(result, allow_nan=False)
        db.flush()
        if sqlite:
            raw.execute(f'PRAGMA busy_timeout={old_timeout}')
        db.commit()
        return result
    except IntegrityError:
        if sqlite:
            raw.execute(f'PRAGMA busy_timeout={old_timeout}')
        db.rollback()
        previous = db.get(AudioProjectRequest, key)
        if previous is not None:
            return replay(previous, project_id, digest)
        fail(409, 'WRITE_CONFLICT', 'Another write completed. Reload the project and retry.')
    except OperationalError as exc:
        if sqlite:
            raw.execute(f'PRAGMA busy_timeout={old_timeout}')
        db.rollback()
        if getattr(exc.orig, 'sqlstate', None) == '55P03' or getattr(exc.orig, 'sqlite_errorcode', 0) & 255 in (5, 6):
            fail(409, 'REQUEST_IN_PROGRESS', 'Another write is in progress. Retry with the same request ID.')
        raise
    except Exception:
        if sqlite and not connection.closed:
            raw.execute(f'PRAGMA busy_timeout={old_timeout}')
        db.rollback()
        raise
