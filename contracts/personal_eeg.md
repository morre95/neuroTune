# Personal meditation EEG artifacts

Preprocessing version `meditation-eeg-1`; protocol `meditation-1`;
quality `2026.3-unverified`. These are software compatibility identifiers,
not evidence of physical Muse accuracy. Muse, Simulator and Playback never pool.
The current compatible recorded configuration uses a four-second Welch window,
one-second hop, theta4–8, alpha8–13 and beta13–30 Hz. Legacy frames without an
observed active-clock mapping do not substitute source/wall time.

Confirmed active endpoints in(0,600] use second bin `ceil(t-1e-9)`, minute
`(bin-1)//60`. Only within-minute bins11–60 contribute: always50 possible bins.
Sort candidate frames by(active endpoint,source endpoint,input position) and
choose the first per bin before quality checks. Globally rejected frames,
nonvalid channels, duplicated channel names and nonfinite/nonpositive absolute
powers supply no observations. Each distinct channel needs at least40 bins;
at least two qualifying channels are required. Other channels do not contribute.
Use `log(theta)-log(alpha)` and `log(beta)-log(alpha)` without a power floor.
Average qualifying channel/bin observations per minute, then qualifying minute
pairs equally per session. Pauses, missing seconds and dense duplicates never
increase coverage. `extractMeditationMinutes` is the shared Dart live/final
extractor; future live callers must first obtain confirmed clock mapping.

One completed600-second, fully rated fixed/calibration recording gives one row,
weight1, with target `(relaxation+10-mental_busyness)/2`. Adaptive descriptive
ratings never train this model. The authoritative stored recording frames are
joined by account, source, session ID and immutable checksum, not taken from a
client-supplied training snapshot. Poor/no EEG can remain subjective comparison
evidence, while supplying no model row.

Feature order is log-theta/alpha, log-beta/alpha, carrier, tone gain, background
gain, sorted background one-hot columns, sorted eye one-hot columns. Population
standard deviation is fitted on training rows; constant columns have scale1.
Ridge minimizes sum of squared error plus1 times squared coefficients with an
unpenalized intercept. Full precision is retained. Leave-one-session-out folds
fit their own vocabularies, means, scales and ridge parameters. The context-only
comparison omits the two EEG columns. Gates require>=20 usable sessions, MAE<=2,
Pearson correlation>=.5 and MAE<=.8 times context-only MAE. Constant targets or
predictions have undefined correlation; a zero context error cannot establish
improvement. Predictions are not clipped.

`POST /v1/meditation/training/jobs` retains the stable request/revision contract;
the dedicated meditation worker consumes queued jobs independently of NIR.
`GET /v1/meditation/models/latest?origin=simulator&protocol_version=meditation-1`
returns the authenticated account/source's newest artifact, including
insufficient/failed results. A ready artifact exports ordered means, scales,
coefficients, intercept, supported background/eye counts, GLOBAL inclusive
carrier/gain training ranges and validation. A supported background/eye pair
needs>=5 usable sessions and the eye represented. Do not narrow numeric ranges
per pair. Fixed-minute scores retain session/profile/action/context provenance
for later exact-setup statistics; they are not extra labelled training rows.
Model versions are opaque preprocessing+UUID strings, never recycled after
deletion. The parser accepts older opaque version strings in shared fixtures.

A job is not readiness. Publication locks the account and rechecks its current
dataset fingerprint plus server deletion epoch. The latest endpoint checks
included evidence checksums/revisions/tombstones, rather than globally revoking
for unrelated source mutations. Deletion scrubs affected jobs/aliases; artifacts
with deleted included rows are removed. When a deleted no-EEG row was only in the
job snapshot, an unaffected artifact survives with its optional job FK detached.
Migration008 follows reviewed deletion007 and uses nullable `ON DELETE SET NULL`.

Local cache key `meditation_model:v1:<accountUUID>:<origin>:meditation-1` uses the
existing KvStore. Local evidence epoch/auth generation/owned tombstones guard
incoming publication atomically; local and server epoch integers are distinct
clocks and are never compared. Cache usability checks known local included
checksum/revision conflicts and owned tombstones. Absence of a server-included
record on this phone is not deletion: another device may have supplied it.
Ordinary new/adaptive/descriptive or unrelated-source activity does not revoke an
unaffected offline artifact. The latest failed result replaces ready cache;
malformed latest data fail closed. Refresh is an idle user action and its network
chain is joined before playback; local inference requires no session HTTP.
Readiness UI displays aggregate validation and fixed/more-data fallback without
unfinished calibration assignment/result tables.

`fixtures/personal_eeg.json` contains independently worked ratios and the ridge
example x=[1,3], y=[2,4]: mean2, scale1, coefficient2/3, intercept3, predictions
[7/3,3,11/3]. Its hypothetical ready flag supports isolated UI/cache tests.
`fixtures/synthetic_simulator_model.json` is an actual API/worker export from20
explicitly synthetic completed fixed Simulator sessions (two backgrounds, ten
paired integer rating targets0..9), consumed by Dart. Normal tests compare its
full precision math and never rewrite it. Explicit regeneration is
`UPDATE_SYNTHETIC_MODEL_FIXTURE=1 .venv/bin/python -m pytest tests/test_personal_eeg_api.py`
from backend. Neither fixture claims physical Muse measurements.
