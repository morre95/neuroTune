"""Durable audio imports with bounded decoding and recoverable worker leases."""
import hashlib
import json
import math
import subprocess
import uuid
import wave
from datetime import UTC, datetime, timedelta
from pathlib import Path

from sqlalchemy import or_, update
from sqlalchemy.orm import Session

from app.config import settings
from app.models import AudioAsset

MAX_SOURCE_BYTES = 100 * 1024 * 1024
MAX_DURATION = 600


def asset_path(user_id: str, asset_id: str, name: str) -> Path:
    # IDs are generated internally; reject path traversal even for internal callers.
    return Path(settings.audio_data_dir) / str(uuid.UUID(user_id)) / str(uuid.UUID(asset_id)) / name


def asset_body(asset: AudioAsset) -> dict:
    return {"id": asset.id, "schema_version": asset.schema_version, "filename": asset.filename,
        "status": asset.status, "error": asset.error, "duration_seconds": asset.duration_seconds,
        "source_channels": asset.source_channels, "sample_rate_hz": 48000 if asset.status == "ready" else None,
        "channels": 2 if asset.status == "ready" else None, "sample_width_bytes": 2 if asset.status == "ready" else None,
        "checksum_sha256": asset.checksum_sha256, "original_sha256": asset.original_sha256,
        "original_bytes": asset.original_bytes, "created_at": asset.created_at.isoformat()}


def _command(args: list[str]) -> str:
    result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, timeout=settings.audio_process_timeout_seconds, check=True)
    return result.stdout.decode()


def run_audio_jobs(db: Session) -> int:
    now = datetime.now(UTC)
    available = or_(AudioAsset.lease_until.is_(None), AudioAsset.lease_until < now)
    ids = db.query(AudioAsset.id).filter(AudioAsset.status == "pending", available).limit(10).all()
    processed = 0
    for (asset_id,) in ids:
        now = datetime.now(UTC)
        available = or_(AudioAsset.lease_until.is_(None), AudioAsset.lease_until < now)
        token = str(uuid.uuid4())
        # Both commands have a timeout; leave margin before another worker can reclaim.
        claimed = db.execute(update(AudioAsset).where(AudioAsset.id == asset_id,
            AudioAsset.status == "pending", available).values(lease_token=token,
            lease_until=now + timedelta(seconds=2 * settings.audio_process_timeout_seconds + 30)))
        db.commit()
        if not claimed.rowcount:
            continue
        asset = db.get(AudioAsset, asset_id)
        temporary = asset_path(asset.user_id, asset.id, f"{token}.wav")
        final = asset_path(asset.user_id, asset.id, "canonical.wav")
        values = {}
        try:
            source = str(asset_path(asset.user_id, asset.id, "original"))
            # Force the allowed demuxer. A renamed playlist cannot open files or URLs.
            probe = json.loads(_command(["ffprobe", "-v", "error", "-protocol_whitelist", "file,pipe",
                "-f", asset.source_format, "-select_streams", "a", "-show_entries",
                "stream=channels,duration:format=duration", "-of", "json", source]))
            streams = probe.get("streams", [])
            if len(streams) != 1 or streams[0].get("channels") not in (1, 2):
                raise ValueError("Choose a recording with one mono or stereo audio stream (1 or 2 channels).")
            duration = float(probe.get("format", {}).get("duration", streams[0].get("duration", 0)))
            if not math.isfinite(duration) or duration < 0 or duration > MAX_DURATION:
                raise ValueError("Trim your recording to ten minutes or less before uploading.")
            channel_args = ["-af", "pan=stereo|c0=c0|c1=c0"] if streams[0]["channels"] == 1 else []
            _command(["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-protocol_whitelist", "file,pipe", "-f", asset.source_format,
                "-threads", "1", "-i", source, "-map", "0:a:0", "-vn", "-t", "600.01", "-ac", "2", "-ar", "48000",
                "-c:a", "pcm_s16le", "-threads", "1", *channel_args, "-y", str(temporary)])
            with wave.open(str(temporary), "rb") as audio:
                decoded_duration = audio.getnframes() / audio.getframerate()
                if decoded_duration <= 0 or decoded_duration > MAX_DURATION:
                    raise ValueError("Choose a non-empty recording of ten minutes or less.")
                if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (2, 2, 48000):
                    raise ValueError("Audio conversion failed. Try exporting your recording as WAV.")
            with temporary.open("rb") as rendered:
                checksum = hashlib.file_digest(rendered, "sha256").hexdigest()
            # Own the lease before publishing; a superseded worker cannot overwrite ready audio.
            db.refresh(asset)
            if asset.lease_token != token:
                continue
            temporary.replace(final)
            values = dict(status="ready", checksum_sha256=checksum,
                duration_seconds=decoded_duration, source_channels=streams[0]["channels"], error=None)
        except ValueError as exc:
            values = dict(status="failed", error=str(exc))
        except subprocess.TimeoutExpired:
            values = dict(status="failed", error="Processing timed out. Try a shorter recording or export it as WAV.")
        except (subprocess.CalledProcessError, OSError, json.JSONDecodeError, wave.Error):
            values = dict(status="failed", error="Could not decode this recording. Export a valid WAV, MP3, M4A/AAC, or FLAC and upload again.")
        finally:
            temporary.unlink(missing_ok=True)
        db.execute(update(AudioAsset).where(AudioAsset.id == asset.id, AudioAsset.lease_token == token)
            .values(**values, lease_token=None, lease_until=None))
        db.commit()
        processed += 1
    return processed
