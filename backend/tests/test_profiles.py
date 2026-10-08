import hashlib
import io
import uuid
import wave

from app.config import settings
from app.db import SessionLocal
from app.worker import run_once
from test_api import auth, client, register


def source(token):
    pcm = io.BytesIO()
    with wave.open(pcm, 'wb') as wav:
        wav.setparams((2, 2, 48000, 0, 'NONE', ''))
        wav.writeframes(b'\x00\x20\x00\x10' * 4800)
    asset = client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'rain.wav'}, content=pcm.getvalue()).json()
    with SessionLocal() as db:
        run_once(db)
    return asset['id']


def test_render_preview_and_save_named_profile(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset_id = source(token)
    recipe = {'schema_version': 1, 'duration_seconds': 45, 'tracks': [{'asset_id': asset_id, 'trim_start_seconds': 0, 'trim_end_seconds': .1, 'gain': .5, 'loop': True}]}
    response = client.post('/v1/audio/renders', headers=auth(token), json=recipe)
    assert response.status_code == 202, response.text
    render_id = response.json()['id']
    assert client.post('/v1/audio/profiles', headers=auth(token), json={'name': 'Rain', 'render_id': render_id}).status_code == 409
    with SessionLocal() as db:
        run_once(db)
    render = client.get(f'/v1/audio/renders/{render_id}', headers=auth(token)).json()
    assert render['status'] == 'ready', render
    preview = client.get(f'/v1/audio/renders/{render_id}/preview', headers=auth(token)).content
    saved = client.post('/v1/audio/profiles', headers=auth(token), json={'name': 'Rain', 'render_id': render_id})
    assert saved.status_code == 201, saved.text
    profile = saved.json()
    assert (profile['version'], profile['carrier_hz'], profile['tone_gain'], profile['background_gain']) == (1, 220, .2, .6)
    assert profile['recipe'] == recipe
    assert profile['normalization_factor'] == 1
    background = client.get(f"/v1/audio/profiles/versions/{profile['id']}/download", headers=auth(token)).content
    assert hashlib.sha256(background).hexdigest() == profile['checksum_sha256']
    with wave.open(io.BytesIO(preview)) as a, wave.open(io.BytesIO(background)) as b:
        assert a.getnframes() == 30 * 48000
        assert b.getnframes() == 45 * 48000
        assert a.readframes(a.getnframes()) == b.readframes(30 * 48000)
    assert client.get('/v1/audio/profiles', headers=auth(token)).json() == [profile]


def ready_render(token, asset_id, **changes):
    recipe = {'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_start_seconds': 0, 'trim_end_seconds': .1, 'gain': 1, 'loop': True} | changes]}
    response = client.post('/v1/audio/renders', headers=auth(token), json=recipe)
    assert response.status_code == 202, response.text
    with SessionLocal() as db:
        run_once(db)
    return response.json()['id']


def test_revising_creates_an_immutable_version_and_all_files_remain_private(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    owner = register(f'{uuid.uuid4()}@example.com')['access_token']
    stranger = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset_id = source(owner)
    render_id = ready_render(owner, asset_id)
    first = client.post('/v1/audio/profiles', headers=auth(owner), json={'name': 'Rain', 'render_id': render_id}).json()
    old_audio = client.get(f"/v1/audio/profiles/versions/{first['id']}/download", headers=auth(owner)).content
    newer_render = ready_render(owner, asset_id, gain=.5, loop=False)
    edited = client.post(f"/v1/audio/profiles/{first['profile_id']}/versions", headers=auth(owner), json={'name': 'Soft rain', 'render_id': newer_render, 'carrier_hz': 300, 'tone_gain': .3, 'background_gain': .65, 'loop': False})
    assert edited.status_code == 201, edited.text
    second = edited.json()
    assert (second['version'], second['profile_id'], second['carrier_hz'], second['loop']) == (2, first['profile_id'], 300, False)
    assert second['checksum_sha256'] != first['checksum_sha256']
    assert client.get(f"/v1/audio/profiles/versions/{first['id']}", headers=auth(owner)).json() == first
    assert client.get(f"/v1/audio/profiles/versions/{first['id']}/download", headers=auth(owner)).content == old_audio
    assert client.get('/v1/audio/profiles', headers=auth(stranger)).json() == []
    assert client.get('/v1/audio/profiles').status_code == 401
    for path in (f'/renders/{render_id}', f'/renders/{render_id}/preview', f"/profiles/versions/{first['id']}", f"/profiles/versions/{first['id']}/download", f"/profiles/versions/{first['id']}/preview"):
        assert client.get('/v1/audio'+path, headers=auth(stranger)).status_code == 404
    assert client.post('/v1/audio/renders', headers=auth(stranger), json={'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_end_seconds': .1}]}).status_code == 404
    assert client.post(f"/v1/audio/profiles/{first['profile_id']}/versions", headers=auth(stranger), json={'name': 'Stolen', 'render_id': render_id}).status_code == 404
    assert client.post('/v1/audio/profiles', headers=auth(stranger), json={'name': 'Stolen', 'render_id': render_id}).status_code == 404


def test_settings_and_source_boundaries_reject_unusable_recipes(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset_id = source(token)
    render_id = ready_render(token, asset_id)
    for changes in ({'carrier_hz': 99}, {'carrier_hz': 401}, {'tone_gain': .4, 'background_gain': .6}, {'tone_gain': -.1}, {'name': '  '}, {'frequency_difference_hz': 10}):
        response = client.post('/v1/audio/profiles', headers=auth(token), json={'name': 'Rain', 'render_id': render_id} | changes)
        assert response.status_code == 422, response.text
    for changes in ({'duration_seconds': 29}, {'duration_seconds': 601}, {'schema_version': 2}):
        assert client.post('/v1/audio/renders', headers=auth(token), json={'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_end_seconds': .1}]} | changes).status_code == 422
    for changes in ({'trim_end_seconds': .2}, {'trim_start_seconds': .1}, {'gain': 5}):
        assert client.post('/v1/audio/renders', headers=auth(token), json={'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_end_seconds': .1} | changes]}).status_code == 422
    pending = client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'bad.wav'}, content=b'bad').json()
    assert client.post('/v1/audio/renders', headers=auth(token), json={'tracks': [{'asset_id': pending['id'], 'trim_end_seconds': .1}]}).status_code == 409
    assert client.get('/v1/audio/profiles', headers=auth(token)).json() == []


def test_peak_factor_is_static_and_trim_gain_and_padding_are_audible(tmp_path, monkeypatch):
    import struct
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    pcm = io.BytesIO()
    with wave.open(pcm, 'wb') as wav:
        wav.setparams((2, 2, 48000, 0, 'NONE', ''))
        wav.writeframes(b'\x00\x10\x00\x08' * 2400 + b'\x00\x40\x00\x20' * 2400)
    asset = client.post('/v1/audio/assets', headers=auth(token) | {'X-Audio-Filename': 'levels.wav'}, content=pcm.getvalue()).json()
    with SessionLocal() as db:
        run_once(db)
    render_id = ready_render(token, asset['id'], gain=4, trim_start_seconds=.05, loop=False)
    render = client.get(f'/v1/audio/renders/{render_id}', headers=auth(token)).json()
    assert render['normalization_factor'] == .5
    preview = client.get(f'/v1/audio/renders/{render_id}/preview', headers=auth(token)).content
    with wave.open(io.BytesIO(preview)) as wav:
        left, right = struct.unpack('<hh', wav.readframes(1))
        assert left == 32767
        assert right == 16384
        wav.setpos(4800)
        assert wav.readframes(100) == b'\x00' * 400


def test_pending_render_recovers_expired_lease_and_failure_cannot_be_saved(tmp_path, monkeypatch):
    from datetime import UTC, datetime, timedelta
    from app.models import AudioRender
    monkeypatch.setattr(settings, 'audio_data_dir', str(tmp_path))
    token = register(f'{uuid.uuid4()}@example.com')['access_token']
    asset_id = source(token)
    render_id = client.post('/v1/audio/renders', headers=auth(token), json={'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_end_seconds': .1, 'loop': True}]}).json()['id']
    with SessionLocal() as db:
        render = db.get(AudioRender, render_id)
        render.lease_token = str(uuid.uuid4())
        render.lease_until = datetime.now(UTC) - timedelta(seconds=1)
        db.commit()
        run_once(db)
    assert client.get(f'/v1/audio/renders/{render_id}', headers=auth(token)).json()['status'] == 'ready'
    failed_id = client.post('/v1/audio/renders', headers=auth(token), json={'duration_seconds': 30, 'tracks': [{'asset_id': asset_id, 'trim_end_seconds': .1}]}).json()['id']
    monkeypatch.setattr(settings, 'audio_process_timeout_seconds', 0)
    with SessionLocal() as db:
        run_once(db)
    failed = client.get(f'/v1/audio/renders/{failed_id}', headers=auth(token)).json()
    assert failed['status'] == 'failed'
    assert 'timed out' in failed['error']
    assert client.get(f'/v1/audio/renders/{failed_id}/preview', headers=auth(token)).status_code == 409
    assert client.post('/v1/audio/profiles', headers=auth(token), json={'name': 'Invalid', 'render_id': failed_id}).status_code == 409
