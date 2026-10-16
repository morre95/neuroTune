# Personal audio editor

The backend serves the production editor at `/editor/`. The Docker build runs
`npm ci` and `npm run build`; the same image includes FFmpeg for the worker.
For local development, run `npm ci` then `npm run dev` here, with the API at
localhost:8000. Build before serving through the local backend.

Sign in with an existing neuroTune account, using the **same backend instance**
as the phone. The Vite development proxy targets `127.0.0.1:8000`; an Android
build pointing at another API will have a different library. Tokens are held in memory: reload
requires sign-in. Upload a mono/stereo WAV, MP3, M4A/AAC, or FLAC, up to 100 MiB
and ten minutes. Uploads survive closing the page; pending imports resume after
worker lease expiry. Preview requires clicking the ready recording's button.

Choose **Create project from …** on a ready recording to save a named source
interval without rendering. Set **Project name**, **Clip start (seconds)** and
**Clip end (seconds)**. Changes save automatically after about one second;
**Save project** saves immediately or retries a failed request. The status shows
unsaved changes, saving, saved, or an actionable error. Controls pause during a
save. A conflict preserves the local draft; close it and reopen the server
project to load the newer revision. Closing an unsaved draft asks before
discarding it.

**Editing projects** lists your account's saved projects, with **Refresh projects**
and **Load more projects** when needed. Sign in again after reloading, then use
**Open …** to restore the exact interval without selecting the original file.
Signing out clears project data and unsaved drafts from the browser. This first
project flow supports one clip from an imported recording. Visual timeline
editing, additional clips and background publication remain later work under
[specification #20](https://github.com/morre95/neuroTune/issues/20); the existing
profile mixer remains available separately.

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

Create a profile from a ready recording. Combine one to four tracks, each with
its own recording, trim, fixed source gain (0–4), and loop setting. All tracks
start together. Add/remove tracks with the visible controls and render 30–600 seconds. Non-looping sources end in silence.
The render is durable; status and progress survive restarting the worker. Audition
the thirty-second background preview, then name and save the profile with carrier
100–400 Hz (default 220), tone gain 0.2 and background gain 0.6. Their sum must not
exceed 0.95. Tone settings are separate from the background: the preview never
contains an assigned frequency difference. Editing creates a new immutable
version and retains the old settings and downloadable checksum.

`POST /v1/audio/renders` takes schema_version 1, duration_seconds and tracks (one to four), each with asset_id, trim_start_seconds, trim_end_seconds,
gain 0–4, and loop. Poll `GET /v1/audio/renders/{id}`; `/preview` is available only
when ready. Rendering uses a floating-point intermediate, scans its full-duration
peak, and records one static normalization_factor (1 unless the peak exceeds 1).
The saved PCM16 WAV and its exact thirty-second prefix use that same factor.
The worker claims bounded batches with expiring leases and writes outputs through
lease-specific temporary paths before publishing.

`POST /v1/audio/profiles` takes name, render_id, carrier_hz, tone_gain,
background_gain and saved-background loop (default true). It accepts only ready
renders. `POST /v1/audio/profiles/{profile_id}/versions` creates a new version.
`GET /v1/audio/profiles` returns all owned immutable versions. Read a version at
`/v1/audio/profiles/versions/{version_id}`, with `/preview` and `/download` for
its WAVs. Metadata includes schema_version 1, owner_account_id, profile_id,
version, background_asset_id, complete source recipe, format, duration and
SHA-256 checksums. The background_asset_id identifies the owned render; it is
separate from each source asset_id in the recipe. File routes require bearer auth
and never expose filesystem paths. The full backend requires Alembic head (008_personal_eeg_models). Compose runs
one migrate service successfully before starting API and worker; see
[operation and upgrades](../docs/MEDITATION_OPERATIONS.md).

## Isolated live browser acceptance

`npm test` runs fast browser checks through visible controls with HTTP fixtures.
`npm run test:acceptance` additionally builds the editor and starts a **real API
and worker**, with a fresh temporary SQLite database/files on localhost:18016.
It registers throwaway accounts, uploads WAV/FLAC sources, uses actual FFmpeg
rendering for a two-track mix, auditions audio, saves immutable profile versions,
verifies downloadable SHA-256/PCM preview consistency, and checks private access.
It never reuses a running development backend. Temporary data is removed after
API/worker shutdown; Playwright retains a trace only on failure.

Install backend dependencies in its virtual environment (including its dev
extra), FFmpeg and Playwright Chromium first. The launcher uses `backend/.venv`
if present, otherwise its Python interpreter; set `NEUROTUNE_BACKEND_PYTHON` to a
specific Python executable when needed. For example, from `web`:

```bash
npm ci
npx playwright install chromium
npm run test:acceptance
```

This verifies editor/API/worker integration. It does not test Android AudioTrack,
physical headphones, Muse signal quality or a full device meditation. Continue
with the separate [Android/Muse acceptance record](../docs/MEDITATION_ACCEPTANCE.md).

Project browser/API checks: `npx playwright test tests/projects.spec.ts` from
`web`, or `npm --prefix web test` from the repository root for all web regression
tests. The project suite starts its own API and worker on a temporary loopback
port, runs migrations on a temporary SQLite database, and imports a real WAV.
It requires the same backend virtual environment, FFmpeg and Chromium as the
acceptance suite. Set `NEUROTUNE_BACKEND_PYTHON` if the interpreter is elsewhere.
No developer database or existing account is used; temporary data is removed
when the fixture shuts down.
