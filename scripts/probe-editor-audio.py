"""Disposable #21 probe: real auth/database, hour WAV, bounded audition windows.

Run through web/playwright.audio-probe.config.ts or directly for manual inspection.
The seeded canonical fixture deliberately bypasses the current ten-minute importer.
No probe route is added to the production application source.
"""
import array
from datetime import UTC, datetime
import hashlib
import io
import math
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import tempfile
import uuid
import wave

RATE = 48_000
SECONDS = 3_600
WINDOW_FRAMES = 5 * RATE
PRIVATE = {"Cache-Control": "private, no-store"}

PAGE = r'''<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Private audio window probe</title>
<link rel="icon" href="/favicon.ico">
<style nonce="__NONCE__">
body{font:16px system-ui;max-width:900px;margin:40px auto;padding:16px;color:#19252b;background:#f5f7f8}
label{display:block;margin:12px 0}input,button{font:inherit;padding:8px}button{margin:8px 8px 8px 0}
canvas{display:block;width:100%;background:#fff;border:1px solid #bac8ce}output{display:block;padding:16px;background:#e0edf1}
</style>
<h1>Private audio window probe</h1>
<p>Isolated research fixture: one hour, stereo 48 kHz PCM16. Audition fetches at most five seconds.</p>
<form id="login"><label>Email<input name="email" type="email" required autocomplete="username"></label>
<label>Password<input name="password" type="password" required autocomplete="current-password"></label>
<button>Sign in</button></form>
<section id="editor" hidden><button id="logout">Sign out</button>
<canvas width="900" height="150" aria-label="One-hour waveform overview"></canvas>
<label>Start (seconds)<input id="start" type="number" min="0" max="3595" step="1" value="720"></label>
<button id="audition" disabled>Audition five seconds</button><button id="stop">Stop audition</button></section>
<output id="status" role="status" aria-live="polite">Sign in to start the isolated probe.</output>
<script nonce="__NONCE__">
const login=document.querySelector('#login'), editor=document.querySelector('#editor');
const status=document.querySelector('#status'), audition=document.querySelector('#audition');
let token=null, refreshToken=null, asset=null, generation=0, pending=null;
let context=null, source=null, wanted=null, busy=false;
function cancel() {
  generation++; wanted=null; pending?.abort(); pending=null;
  if(source) {source.onended=null;source.stop();source.disconnect();source=null;}
  for(const key of Object.keys(status.dataset)) delete status.dataset[key];
}
function reset() {
  cancel(); token=null; refreshToken=null; asset=null;
  if(context) {void context.close();context=null;}
  login.hidden=false;editor.hidden=true;audition.disabled=true;
  const canvas=document.querySelector('canvas');canvas.getContext('2d').clearRect(0,0,canvas.width,canvas.height);
}
async function api(path, signal, init={}) {
  const response=await fetch(path,{...init,signal,headers:{...init.headers,Authorization:`Bearer ${token}`}});
  if(!response.ok) throw new Error(`Request failed (${response.status}). Sign in again or retry.`);
  return response;
}
function draw(peaks) {
  const canvas=document.querySelector('canvas'), pen=canvas.getContext('2d');
  pen.clearRect(0,0,canvas.width,canvas.height);pen.fillStyle='#246b80';
  for(let i=0;i<peaks.length;i++) {
    const [low,high]=peaks[i], scale=canvas.height/65536;
    pen.fillRect(i*canvas.width/peaks.length,canvas.height/2-high*scale,1,Math.max(1,(high-low)*scale));
  }
}
login.onsubmit=async event=> {
  event.preventDefault();reset();const epoch=generation;
  const controller=new AbortController();pending=controller;
  status.textContent='Signing in and preparing the private fixture…';
  try {
    const data=new FormData(login);
    const response=await fetch('/v1/auth/login',{method:'POST',signal:controller.signal,
      headers:{'Content-Type':'application/json'},body:JSON.stringify({email:data.get('email'),password:data.get('password')})});
    if(!response.ok) throw new Error('Sign in failed.');
    const pair=await response.json();if(epoch!==generation)return;
    token=pair.access_token;refreshToken=pair.refresh_token;login.reset();
    const fixture=await (await api('/probe/fixture',controller.signal,{method:'POST'})).json();
    if(epoch!==generation)return;asset=fixture.id;
    const overview=await (await api(`/probe/audio/${asset}/peaks`,controller.signal)).json();
    if(epoch!==generation)return;
    draw(overview.peaks);login.hidden=true;editor.hidden=false;audition.disabled=false;
    status.textContent=`Ready · ${fixture.frames/48000} seconds · ${fixture.bytes} source bytes`;
  } catch(error) {if(epoch===generation){reset();status.textContent=error.message;}}
  finally {if(pending===controller)pending=null;}
};
// Fetch cancellation cannot cancel decodeAudioData. A single pump decodes one
// bounded complete WAV at a time; only the latest desired audition can start.
// Sources: https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData
// https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch#canceling_a_request
async function pump() {
  if(busy)return;busy=true;
  try {
    while(wanted) {
      const job=wanted;wanted=null;
      const currentContext=context, controller=new AbortController();pending=controller;
      try {
        const response=await api(`/probe/audio/${asset}/window?start_frame=${job.start}&frames=240000`,controller.signal);
        const bytes=await response.arrayBuffer();
        const encodedBytes=bytes.byteLength; // Decoding can detach the input buffer.
        if(job.epoch!==generation)continue;
        const decoded=await currentContext.decodeAudioData(bytes);
        if(job.epoch!==generation)continue;
        const playing=currentContext.createBufferSource();
        playing.buffer=decoded;playing.connect(currentContext.destination);source=playing;
        playing.onended=()=> {if(source===playing){playing.disconnect();source=null;}};
        playing.start();
        status.dataset.startFrame=String(job.start);
        status.dataset.decodedFrames=String(decoded.length);
        status.dataset.contextState=currentContext.state;
        status.dataset.latencyMs=String(performance.now()-job.clicked);
        status.textContent=`Playing five seconds from ${job.start/48000}s · ${encodedBytes} bytes fetched`;
      } catch(error) {if(job.epoch===generation)status.textContent=error.message;}
      finally {if(pending===controller)pending=null;}
    }
  } finally {busy=false;}
}
audition.onclick=async()=> {
  const seconds=Number(document.querySelector('#start').value);
  if(!Number.isInteger(seconds)||seconds<0||seconds>3595){status.textContent='Choose 0–3595 seconds.';return;}
  cancel();const epoch=generation, clicked=performance.now();
  context??=new AudioContext({sampleRate:48000});
  try {
    await context.resume(); // Resume within the actual button gesture.
    if(epoch!==generation)return;
    wanted={epoch,start:seconds*48000,clicked};status.textContent='Loading a bounded window…';
    void pump();
  } catch(error) {if(epoch===generation)status.textContent=error.message;}
};
document.querySelector('#stop').onclick=()=>{cancel();status.textContent='Audition stopped.';};
document.querySelector('#logout').onclick=()=> {
  const access=token, refresh=refreshToken;reset();status.textContent='Signed out.';
  if(access)void fetch('/v1/auth/logout',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${access}`},
    body:JSON.stringify({refresh_token:refresh})}).catch(()=>{});
};
window.addEventListener('pagehide',reset);
</script></html>'''


def write_fixture(path):
    """Write a real 691 MB WAV in small blocks; six distinct ten-minute bands."""
    blocks = []
    for band in range(6):
        samples = array.array('h')
        for frame in range(RATE):
            for frequency in (220 + band * 60, 330 + band * 60):
                samples.append(round(8000 * math.sin(2 * math.pi * frequency * frame / RATE)))
        if sys.byteorder != 'little':
            samples.byteswap()
        blocks.append(samples.tobytes())
    with wave.open(str(path), 'wb') as target:
        target.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        for second in range(SECONDS):
            target.writeframesraw(blocks[second // 600])
    # Every generated one-second block has these extrema. This is fixture peak
    # data, not a production waveform extractor for arbitrary recordings.
    return [[-8000, 8000] for _ in range(SECONDS)]


def serve(directory):
    from fastapi import Depends, HTTPException, Query
    from fastapi.responses import HTMLResponse, JSONResponse, Response
    from sqlalchemy.orm import Session
    import uvicorn
    from app.auth import get_current_user
    from app.audio import asset_path
    from app.db import get_db
    from app.main import app
    from app.models import AudioAsset, User
    from app.routers.audio import owned_asset

    fixture = directory / 'hour.wav'
    peaks = write_fixture(fixture)
    with fixture.open('rb') as audio:
        checksum = hashlib.file_digest(audio, 'sha256').hexdigest()

    @app.middleware('http')
    async def private_probe_headers(request, call_next):
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'private, no-store'
        return response

    @app.get('/favicon.ico')
    def favicon():
        return Response(status_code=204)

    @app.get('/probe/', response_class=HTMLResponse)
    def page():
        nonce = secrets.token_urlsafe(24)
        return HTMLResponse(PAGE.replace('__NONCE__', nonce), headers={
            'Content-Security-Policy': f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'",
        })

    @app.post('/probe/fixture')
    def own_fixture(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
        asset = db.query(AudioAsset).filter_by(user_id=user.id, filename='probe-hour.wav').one_or_none()
        if asset is None:
            asset = AudioAsset(id=str(uuid.uuid4()), user_id=user.id, filename='probe-hour.wav',
                source_format='wav', original_bytes=fixture.stat().st_size, original_sha256=checksum,
                checksum_sha256=checksum, status='ready', duration_seconds=SECONDS, source_channels=2,
                created_at=datetime.now(UTC))
            canonical = asset_path(user.id, asset.id, 'canonical.wav')
            canonical.parent.mkdir(parents=True, exist_ok=True)
            os.link(fixture, canonical)  # One disposable fixture, real per-account ownership.
            db.add(asset)
            db.commit()
        return {'id': asset.id, 'frames': SECONDS * RATE, 'bytes': fixture.stat().st_size}

    @app.get('/probe/audio/{asset_id}/window')
    def window(asset_id: str, start_frame: int = Query(ge=0), frames: int = Query(ge=1, le=WINDOW_FRAMES),
               user: User = Depends(get_current_user), db: Session = Depends(get_db)):
        asset = owned_asset(db, user.id, asset_id)
        with wave.open(str(asset_path(user.id, asset.id, 'canonical.wav')), 'rb') as audio:
            if start_frame + frames > audio.getnframes():
                raise HTTPException(422, 'Window must be within the recording.')
            audio.setpos(start_frame)
            pcm = audio.readframes(frames)
        output = io.BytesIO()
        with wave.open(output, 'wb') as audio:
            audio.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
            audio.writeframes(pcm)
        return Response(output.getvalue(), media_type='audio/wav', headers=PRIVATE)

    @app.get('/probe/audio/{asset_id}/peaks')
    def overview(asset_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
        owned_asset(db, user.id, asset_id)
        return JSONResponse({'frames': SECONDS * RATE, 'frames_per_peak': RATE, 'peaks': peaks}, headers=PRIVATE)

    uvicorn.run(app, host='127.0.0.1', port=18021, access_log=False)


def main():
    root = Path(__file__).resolve().parents[1]
    python = os.environ.get('NEUROTUNE_BACKEND_PYTHON', str(root / 'backend/.venv/bin/python'))
    if Path(python).exists() and Path(sys.executable) != Path(python):
        os.execv(python, [python, str(Path(__file__).resolve())])
    def stop(_signal, _frame):
        raise KeyboardInterrupt

    # Uvicorn restores and re-raises the previous signal handler after shutdown.
    # Convert termination to unwinding so the large disposable fixture is removed.
    signal.signal(signal.SIGTERM, stop)
    with tempfile.TemporaryDirectory(prefix='neurotune-audio-probe-') as temporary:
        directory = Path(temporary)
        os.environ.update({
            'DATABASE_URL': f'sqlite:///{directory}/probe.sqlite',
            'AUDIO_DATA_DIR': str(directory / 'audio'), 'RAW_DATA_DIR': str(directory / 'raw'),
            'JWT_SECRET': secrets.token_urlsafe(32), 'ENVIRONMENT': 'development',
            'EDITOR_DIST_DIR': str(root / 'web/dist'),
            'CONTRACTS_PATH': str(root / 'contracts/default_experiment.json'),
        })
        sys.path.insert(0, str(root / 'backend'))
        subprocess.run([sys.executable, '-m', 'alembic', 'upgrade', 'head'], cwd=root / 'backend', check=True)
        try:
            serve(directory)
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
