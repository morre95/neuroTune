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

Create a profile from a ready recording. Trim it, choose a fixed source gain and
loop setting, and render 30–600 seconds. Non-looping sources end in silence.
The render is durable; status and progress survive restarting the worker. Audition
the thirty-second background preview, then name and save the profile with carrier
100–400 Hz (default 220), tone gain 0.2 and background gain 0.6. Their sum must not
exceed 0.95. Tone settings are separate from the background: the preview never
contains an assigned frequency difference. Editing creates a new immutable
version and retains the old settings and downloadable checksum.

`POST /v1/audio/renders` takes schema_version 1, duration_seconds and tracks (one
in this increment), each with asset_id, trim_start_seconds, trim_end_seconds,
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
and never expose filesystem paths. Apply Alembic migration 005_audio_profiles.
