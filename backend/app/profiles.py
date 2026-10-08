"""Immutable library contracts and durable background rendering."""
import hashlib
import json
import struct
import subprocess
import uuid
import wave
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import or_, update
from sqlalchemy.orm import Session

from app.audio import _command, asset_path
from app.config import settings
from app.models import AudioRender


class TrackRecipe(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    asset_id: uuid.UUID
    trim_start_seconds: float = Field(default=0, ge=0, le=600)
    trim_end_seconds: float = Field(gt=0, le=600)
    gain: float = Field(default=1, ge=0, le=4)
    loop: bool = False

    @model_validator(mode='after')
    def ordered_trim(self):
        if round(self.trim_end_seconds * 48000) <= round(self.trim_start_seconds * 48000):
            raise ValueError('Trim end must be after trim start by at least one audio sample.')
        return self


class MixRecipe(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    schema_version: Literal[1] = 1
    duration_seconds: int = Field(default=600, ge=30, le=600, strict=True)
    tracks: list[TrackRecipe] = Field(min_length=1, max_length=1)


class ProfileSettings(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    name: str = Field(min_length=1, max_length=120)
    render_id: uuid.UUID
    carrier_hz: float = Field(default=220, ge=100, le=400)
    tone_gain: float = Field(default=.2, ge=0, le=.95)
    background_gain: float = Field(default=.6, ge=0, le=.95)
    loop: bool = True

    @model_validator(mode='after')
    def headroom(self):
        self.name = self.name.strip()
        if not self.name:
            raise ValueError('Give the profile a name.')
        if Decimal(str(self.tone_gain)) + Decimal(str(self.background_gain)) > Decimal('0.95'):
            raise ValueError('Tone and background gains must total at most 0.95.')
        return self


class ProfileVersion(BaseModel):
    """Published immutable metadata; tones contain no assigned binaural action."""
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    schema_version: Literal[1]
    id: uuid.UUID
    owner_account_id: uuid.UUID
    profile_id: uuid.UUID
    version: int = Field(ge=1)
    name: str = Field(min_length=1, max_length=120)
    background_asset_id: uuid.UUID
    recipe: MixRecipe
    carrier_hz: float = Field(ge=100, le=400)
    tone_gain: float = Field(ge=0, le=.95)
    background_gain: float = Field(ge=0, le=.95)
    loop: bool
    duration_seconds: int = Field(ge=30, le=600)
    normalization_factor: float = Field(gt=0, le=1)
    checksum_sha256: str = Field(pattern='^[0-9a-f]{64}$')
    preview_checksum_sha256: str = Field(pattern='^[0-9a-f]{64}$')
    sample_rate_hz: Literal[48000]
    channels: Literal[2]
    sample_width_bytes: Literal[2]
    created_at: str


def render_body(render: AudioRender):
    return dict(id=render.id, schema_version=1, recipe=json.loads(render.recipe_json),
                status=render.status, progress=render.progress, error=render.error,
                normalization_factor=render.normalization_factor,
                checksum_sha256=render.checksum_sha256,
                preview_checksum_sha256=render.preview_checksum_sha256,
                sample_rate_hz=48000, channels=2, sample_width_bytes=2)


def _checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run_render_jobs(db: Session) -> int:
    now = datetime.now(UTC)
    available = or_(AudioRender.lease_until.is_(None), AudioRender.lease_until < now)
    ids = db.query(AudioRender.id).filter(AudioRender.status == 'pending', available).limit(10).all()
    processed = 0
    for (render_id,) in ids:
        token = str(uuid.uuid4())
        now = datetime.now(UTC)
        available = or_(AudioRender.lease_until.is_(None), AudioRender.lease_until < now)
        claimed = db.execute(update(AudioRender).where(AudioRender.id == render_id,
            AudioRender.status == 'pending', available).values(lease_token=token, progress=.1,
            lease_until=now + timedelta(seconds=3 * settings.audio_process_timeout_seconds + 60)))
        db.commit()
        if not claimed.rowcount:
            continue
        render = db.get(AudioRender, render_id)
        directory = asset_path(render.user_id, render.id, 'background.wav').parent
        directory.mkdir(parents=True, exist_ok=True)
        raw = directory / f'{token}.f32'
        saved = directory / f'{token}.wav'
        preview = directory / f'{token}-preview.wav'
        values = {}
        try:
            recipe = MixRecipe.model_validate_json(render.recipe_json)
            track = recipe.tracks[0]
            start, end = round(track.trim_start_seconds * 48000), round(track.trim_end_seconds * 48000)
            filters = [f'atrim=start_sample={start}:end_sample={end}', 'asetpts=PTS-STARTPTS']
            if track.loop:
                filters.append(f'aloop=loop=-1:size={end-start}')
            filters += [f'volume={track.gain}:precision=double', f'apad=whole_len={recipe.duration_seconds*48000}']
            _command(['ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-i',
                str(asset_path(render.user_id, str(track.asset_id), 'canonical.wav')), '-af', ','.join(filters),
                '-t', str(recipe.duration_seconds), '-ar', '48000', '-ac', '2', '-threads', '1',
                '-f', 'f32le', '-y', str(raw)])
            if raw.stat().st_size != recipe.duration_seconds * 48000 * 8:
                raise ValueError('Rendered background has an invalid duration.')
            peak = 0.0
            with raw.open('rb') as audio:
                while chunk := audio.read(65536):
                    peak = max(peak, max(abs(value[0]) for value in struct.iter_unpack('<f', chunk)))
            factor = 1 / peak if peak > 1 else 1.0
            _command(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'f32le', '-ar', '48000', '-ac', '2',
                '-threads', '1', '-i', str(raw), '-af', f'volume={factor}:precision=double',
                '-c:a', 'pcm_s16le', '-threads', '1', '-y', str(saved)])
            # Preview is the first thirty seconds of this exact normalized render.
            with wave.open(str(saved), 'rb') as source, wave.open(str(preview), 'wb') as target:
                if (source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getnframes()) != (2, 2, 48000, recipe.duration_seconds * 48000):
                    raise ValueError('Rendered background has an invalid audio format.')
                target.setparams(source.getparams())
                target.writeframes(source.readframes(30 * 48000))
            values = dict(status='ready', progress=1, normalization_factor=factor,
                checksum_sha256=_checksum(saved), preview_checksum_sha256=_checksum(preview), error=None)
            db.refresh(render)
            if render.lease_token != token:
                continue
            saved.replace(directory / 'background.wav')
            preview.replace(directory / 'preview.wav')
        except subprocess.TimeoutExpired:
            values = dict(status='failed', error='Rendering timed out. Try a shorter background.')
        except (ValueError, OSError, subprocess.CalledProcessError, wave.Error):
            values = dict(status='failed', error='Could not render this background. Check the recording and trim settings.')
        finally:
            for temporary in (raw, saved, preview):
                temporary.unlink(missing_ok=True)
        db.execute(update(AudioRender).where(AudioRender.id == render.id, AudioRender.lease_token == token)
                   .values(**values, lease_token=None, lease_until=None))
        db.commit()
        processed += 1
    return processed
