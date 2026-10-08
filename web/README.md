# Personal audio editor

The backend serves the production editor at `/editor/`. The Docker build runs
`npm ci` and `npm run build`; the same image includes FFmpeg for the worker.
For local development, run `npm ci` then `npm run dev` here, with the API at
localhost:8000. Build before serving through the local backend.

Sign in with an existing neuroTune account. Tokens are held in memory: reload
requires sign-in. Upload a mono/stereo WAV, MP3, M4A/AAC, or FLAC, up to 100 MiB
and ten minutes. Uploads survive closing the page; pending imports resume after
worker lease expiry. Preview requires clicking the ready recording's button.

API: `POST /v1/audio/assets` streams the file body as `application/octet-stream`.
Set `X-Audio-Filename` to its URL-encoded original filename. A 202 response
contains an asset ID and `pending` status. `GET /v1/audio/assets` lists owned
assets; `GET /v1/audio/assets/{id}` polls metadata; `/download` returns canonical
48 kHz stereo PCM16 WAV only when ready. Every route requires a bearer token.
Import failures are durable metadata with an actionable error. Upload a corrected
source to retry. Original SHA-256 and canonical SHA-256 are distinct fields.

`AUDIO_DATA_DIR` holds originals and renders in generated account/asset
subdirectories. API and worker must share it (Compose's dedicated `audio`
volume). Each probe and decode has a 120 second timeout, configurable with
`AUDIO_PROCESS_TIMEOUT_SECONDS`; worker leases allow both commands plus margin.
Only approved demuxers and local file/pipe protocols are enabled.

Checks: `npm run build`; `npx playwright install chromium` then `npm test`.
Browser tests exercise visible controls at the HTTP boundary; backend tests use
real short codec fixtures and the durable worker.
