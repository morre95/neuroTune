from datetime import datetime

from sqlalchemy import Float, Integer, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked: Mapped[bool] = mapped_column(default=False)


class Experiment(Base):
    __tablename__ = "experiments"
    __table_args__ = (
        Index(
            "uq_experiments_one_active",
            "active",
            unique=True,
            postgresql_where=text("active"),
            sqlite_where=text("active"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[str] = mapped_column(String(64), unique=True)
    body: Mapped[str] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(default=True)


class SessionRecord(Base):
    __tablename__ = "sessions"
    __table_args__ = (UniqueConstraint("id", "checksum", name="uq_session_checksum"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    checksum: Mapped[str] = mapped_column(String(64))
    origin: Mapped[str] = mapped_column(String(32), index=True)
    experiment_version: Mapped[str] = mapped_column(String(64), index=True)
    manifest_json: Mapped[str] = mapped_column(Text)
    decisions_json: Mapped[str] = mapped_column(Text)
    frames_json: Mapped[str] = mapped_column(Text)
    raw_path: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SessionDeletion(Base):
    """No signal data: prevents delayed uploads from restoring deleted sessions."""

    __tablename__ = "session_deletions"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    session_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    raw_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    deleted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class TrainingJob(Base):
    __tablename__ = "training_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    origin: Mapped[str] = mapped_column(String(32))
    experiment_version: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32), default="queued")
    bandit_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class BanditVersion(Base):
    __tablename__ = "bandit_versions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    policy_version: Mapped[str] = mapped_column(String(64))
    origin: Mapped[str] = mapped_column(String(32), index=True)
    experiment_version: Mapped[str] = mapped_column(String(64), index=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AudioAsset(Base):
    """Owned original and canonical audio, with durable import lease."""

    __tablename__ = "audio_assets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    schema_version: Mapped[int] = mapped_column(Integer, default=1)
    filename: Mapped[str] = mapped_column(String(255))
    source_format: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    original_bytes: Mapped[int] = mapped_column(Integer)
    original_sha256: Mapped[str] = mapped_column(String(64))
    checksum_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    duration_seconds: Mapped[float | None] = mapped_column(Float, nullable=True)
    source_channels: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    lease_token: Mapped[str | None] = mapped_column(String(36), nullable=True)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AudioRender(Base):
    __tablename__ = "audio_renders"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    recipe_json: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)
    progress: Mapped[float] = mapped_column(Float, default=0)
    normalization_factor: Mapped[float | None] = mapped_column(Float, nullable=True)
    checksum_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    preview_checksum_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    lease_token: Mapped[str | None] = mapped_column(String(36), nullable=True)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AudioProfileVersion(Base):
    __tablename__ = "audio_profile_versions"
    __table_args__ = (UniqueConstraint("profile_id", "version", name="uq_audio_profile_version"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    profile_id: Mapped[str] = mapped_column(String(36), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    version: Mapped[int] = mapped_column(Integer)
    render_id: Mapped[str] = mapped_column(ForeignKey("audio_renders.id"))
    body_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class CalibrationPlanRecord(Base):
    __tablename__ = 'calibration_plans'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    body_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MeditationFeedbackRecord(Base):
    __tablename__ = 'meditation_feedback'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    session_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer)
    body_json: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MeditationTrainingJob(Base):
    __tablename__ = 'meditation_training_jobs'
    __table_args__ = (UniqueConstraint('user_id', 'origin', 'protocol_version', 'dataset_fingerprint', name='uq_meditation_dataset'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    origin: Mapped[str] = mapped_column(String(32))
    protocol_version: Mapped[str] = mapped_column(String(64))
    dataset_fingerprint: Mapped[str] = mapped_column(String(64))
    dataset_json: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(32), default='queued')
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MeditationTrainingRequest(Base):
    __tablename__ = 'meditation_training_requests'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    job_id: Mapped[str] = mapped_column(ForeignKey('meditation_training_jobs.id'))
    body_json: Mapped[str] = mapped_column(Text)
