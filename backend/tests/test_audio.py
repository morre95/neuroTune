import pytest
import io
import uuid
import wave

from app.db import SessionLocal
from app.worker import run_once
from test_api import auth, client, register


def test_owner_imports_and_auditions_mono_audio(tmp_path, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    pcm = io.BytesIO()
    with wave.open(pcm, 'wb') as wav:
        wav.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
        wav.writeframes(b'\x00\x10' * 2400)
    uploaded = client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'rain.wav'}, content=pcm.getvalue())
    assert uploaded.status_code == 202, uploaded.text
    asset = uploaded.json()
    assert asset['status'] == 'pending'
    with SessionLocal() as db:
        run_once(db)
    ready = client.get(f"/v1/audio/assets/{asset['id']}", headers=auth(token)).json()
    assert ready['status'] == 'ready'
    assert ready['sample_rate_hz'] == 48000
    audio = client.get(f"/v1/audio/assets/{asset['id']}/download", headers=auth(token))
    assert audio.status_code == 200
    with wave.open(io.BytesIO(audio.content)) as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (2, 2, 48000)
        frames = wav.readframes(wav.getnframes())
        assert frames[0::4] == frames[2::4]
        assert frames[1::4] == frames[3::4]
        assert frames[400:404] == b'\x00\x10\x00\x10'


def test_foreign_account_cannot_inspect_or_download_asset(tmp_path, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    owner = register(f'{uuid.uuid4()}@example.com')['access_token']
    stranger = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset = client.post('/v1/audio/assets', headers=auth(owner) | {'X-Audio-Filename': 'private.wav'}, content=b'not-valid').json()
    assert client.get('/v1/audio/assets', headers=auth(stranger)).json() == []
    for suffix in ('', '/download'):
        assert client.get(f"/v1/audio/assets/{asset['id']}{suffix}", headers=auth(stranger)).status_code == 404
    assert client.get('/v1/audio/assets').status_code == 401
    with SessionLocal() as db:
        run_once(db)
    failed = client.get(f"/v1/audio/assets/{asset['id']}", headers=auth(owner)).json()
    assert failed['status'] == 'failed'
    assert 'valid WAV' in failed['error']


def test_invalid_uploads_fail_before_processing(tmp_path, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    assert client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'playlist.m3u'}, content=b'file').status_code == 400
    assert client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'empty.wav'}, content=b'').status_code == 400
    assert client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'large.wav', 'Content-Length': str(100*1024*1024+1)}, content=b'x').status_code == 413
    assert client.get('/v1/audio/assets', headers=auth(token)).json() == []


def test_audio_migration_preserves_old_accounts(tmp_path, monkeypatch):
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, text, inspect
    from app.config import settings
    monkeypatch.setattr(settings, 'database_url', f"sqlite:///{tmp_path / 'migration.db'}")
    config = Config(str(__import__('pathlib').Path(__file__).resolve().parents[1] / 'alembic.ini'))
    config.set_main_option('script_location', str(__import__('pathlib').Path(__file__).resolve().parents[1] / 'alembic'))
    command.upgrade(config, '003_single_active_experiment')
    database = create_engine(settings.database_url)
    with database.begin() as connection:
        connection.execute(text("INSERT INTO users (id,email,password_hash,created_at) VALUES ('old','old@example.com','hash','2026-01-01')"))
    command.upgrade(config, 'head')
    assert 'audio_assets' in inspect(database).get_table_names()
    with database.connect() as connection:
        assert connection.execute(text('SELECT email FROM users')).scalar() == 'old@example.com'
    database.dispose()


@pytest.mark.parametrize('extension,codec,channels', [('wav','pcm_s16le',2),('mp3','libmp3lame',1),('m4a','aac',2),('aac','aac',1),('flac','flac',2)])
def test_common_codecs_become_canonical_stereo(tmp_path, monkeypatch, extension, codec, channels):
    import subprocess
    import struct
    from app.config import settings
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path / 'assets'))
    source = tmp_path / f'source.{extension}'
    expression = 'aevalsrc=0.25*sin(2*PI*440*t)|0.1*sin(2*PI*660*t):s=48000:d=0.25' if channels == 2 else 'sine=frequency=440:duration=0.25'
    subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i',expression,'-ac',str(channels),'-c:a',codec,str(source)],check=True)
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset = client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': source.name}, content=source.read_bytes()).json()
    with SessionLocal() as db:
        run_once(db)
    result = client.get(f"/v1/audio/assets/{asset['id']}",headers=auth(token)).json()
    assert result['status'] == 'ready', result
    output = client.get(f"/v1/audio/assets/{asset['id']}/download",headers=auth(token)).content
    with wave.open(io.BytesIO(output)) as wav:
        assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate()) == (2,2,48000)
        samples = struct.unpack('<'+'h'*(wav.getnframes()*2),wav.readframes(wav.getnframes()))
        left,right = samples[::2],samples[1::2]
        if channels == 1:
            assert left == right
        else:
            assert sum(x*x for x in left) > sum(x*x for x in right) * 3


def test_interrupted_worker_lease_recovers_without_resubmitting(tmp_path, monkeypatch):
    from datetime import UTC, datetime, timedelta
    from app.config import settings
    from app.models import AudioAsset
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    pcm = io.BytesIO()
    with wave.open(pcm,'wb') as wav:
        wav.setparams((1,2,48000,0,'NONE',''))
        wav.writeframes(b'\x00\x10'*4800)
    asset = client.post('/v1/audio/assets',headers=auth(token)|{'X-Audio-Filename':'retry.wav'},content=pcm.getvalue()).json()
    with SessionLocal() as db:
        interrupted = db.get(AudioAsset,asset['id'])
        interrupted.lease_token = str(uuid.uuid4())
        interrupted.lease_until = datetime.now(UTC)-timedelta(seconds=1)
        db.commit()
        run_once(db)
    assert client.get(f"/v1/audio/assets/{asset['id']}",headers=auth(token)).json()['status']=='ready'


@pytest.mark.parametrize('channels,duration,error',[(3,0.1,'1 or 2 channels'),(1,601,'ten minutes')])
def test_unsupported_recordings_have_actionable_job_errors(tmp_path, monkeypatch, channels, duration, error):
    from app.config import settings
    monkeypatch.setattr(settings,'audio_data_dir',str(tmp_path / 'assets'))
    pcm=io.BytesIO()
    with wave.open(pcm,'wb') as wav:
        wav.setparams((channels,2,8000,0,'NONE',''))
        wav.writeframes(b'\x00\x10' * int(duration*8000)*channels)
    token=register(f'{uuid.uuid4()}@example.com')['access_token']
    asset=client.post('/v1/audio/assets',headers=auth(token)|{'X-Audio-Filename':'unsupported.wav'},content=pcm.getvalue()).json()
    with SessionLocal() as db:
        run_once(db)
    failed=client.get(f"/v1/audio/assets/{asset['id']}",headers=auth(token)).json()
    assert failed['status']=='failed'
    assert error in failed['error']
    assert client.get(f"/v1/audio/assets/{asset['id']}/download",headers=auth(token)).status_code==409


def test_processing_timeout_is_terminal_and_actionable(tmp_path, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings,'audio_data_dir',str(tmp_path / 'assets'))
    monkeypatch.setattr(settings,'audio_process_timeout_seconds',0)
    token=register(f'{uuid.uuid4()}@example.com')['access_token']
    asset=client.post('/v1/audio/assets',headers=auth(token)|{'X-Audio-Filename':'timeout.wav'},content=b'RIFF').json()
    with SessionLocal() as db:
        run_once(db)
    failed=client.get(f"/v1/audio/assets/{asset['id']}",headers=auth(token)).json()
    assert failed['status']=='failed'
    assert 'timed out' in failed['error']
