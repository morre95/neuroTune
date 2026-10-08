# Offline meditation adaptation v1

Meditation uses five centered differences: control0,6,8,10,12Hz. A cached owned
source-specific ready personal EEG model with supported background/eye/numeric
context and current EEG preprocessing enables adaptation directly. There is no
additional collection gate. Calibration remains fixed. Other sessions start at
the locally resolved preferred fixed action. The model, exact profile/eye/source
setup, coefficients and preprocessing remain frozen throughout the session.

## Played-time inference and selection

The controller evaluates each completed60-active-second period once, using
confirmed device consumption. Raw FeatureFrame.timeSeconds stays unchanged;
historical playback checkpoints map active endpoints. Identical active clock/head
reads add no interval. Paused/stalled/discontinuous windows remain ineligible.
The shared meditation-eeg-1 extraction excludes the first10 seconds per minute,
uses50 endpoint bins, and needs40 unique valid bins on at least2 distinct EEG
channels. Eligible scores use the frozen model without clipping. Missing/poor EEG
or unusable/nonfinite inference holds action without observation or random draw.

Statistics have means only for observed actions. After observing the current
valid minute, exploitation changes to a known action only with advantage>=0.5.
Ties follow control,6,8,10,12 order. Epsilon0.1 explores uniformly across allfive,
including the current and unobserved actions. The saved unconditional probability
map gives0.92 to the hysteresis-qualified exploitation action and0.02 to each
other action, regardless of the branch drawn. Quality holds have probability1
for the held action.

A fresh pause/finish checkpoint also evaluates newly completed periods, but does
not select or schedule future output. Minute9 at600 scores/observes once and has
selected_action=null, probabilities={}, and no transition. Wall time while
paused never adds decisions. Previously scheduled trajectory history is retained.

## Serialized PCM trajectory

The persistent WAV/mix isolate has one shared command response slot. The pump
joins prior owned render/write, takes a fresh played checkpoint and releases EEG,
then evaluates before submitting the next packet. A changed action schedules a
five-second glide at max(confirmed played frames,fully accepted frames). It never
rewrites already owned PCM or flushes to force an exact60s boundary.

The difference changes linearly; stereo phases integrate its frequency over the
absolute played-frame trajectory. With x seconds since glide start, d0->d1:
I(x)=d0*x+(d1-d0)*x*x/10 during the first5 seconds, then constant d1. Left/right
cycles add carrier*x minus/plus I(x)/2 to their accumulated anchors. This keeps
phase continuous at both ends and for control transitions. Amplitude, carrier,
profile/background gain and absolute background cursor stay fixed. Only existing
session start/stop ramps affect amplitude. History supports arbitrary packet
partition, pause flush and reread at an earlier fresh checkpoint.

## Durable statistics and provenance

Core MeditationActionStatistics contains complete model evidence separately from
exact-setup fixed seeds and adaptive observations. Each contribution has kind,
session_id,minute (0..9),action,finite score,checksum_sha256; fixed seeds additionally
retain feedback_revision. Its stable identity is kind/session_id/minute. No NIR
bandit totals, decisions or caches are used.

Live observations update session-local policy immediately. They are published
only after the raw file, stored manifest/decisions and upload queue are durable,
for both completed and stopped/error sessions with valid periods. Final checksum
is attached before publication. Disposal/persistence failure never publishes an
unreviewable orphan. Repository load/save verifies each adaptive observation
against its owned source/setup/model stored decision and raw checksum.

App MeditationActionRepository.load(owner,setup,model) and save(stats,isCurrent:)
use existing KvStore (schema6), with key:
meditation_action_stats:v1:<UUID>:<origin>:meditation-1:<exactSetupKey>:<modelVersion>.
Incoming publication uses SessionRepository.publishEvidenceCache with full model
evidence union all contribution IDs and an authentication predicate. The local
evidence epoch is publication freshness only, not cached-usability revocation.
A replacement model version starts a separate bucket; unknown means stay absent.
Targeted deletion/model revocation and remaining-data rebuild are ticket#15.

## Review metadata

Meditation manifest mode=adaptive, policyVersion=meditation-epsilon-0.1-v1 retains
initial fixed_action and adds model_id/model_version/preprocessing_version,
statistics_setup_key and adaptive_decisions. Each decision records minute,
boundary/evaluated played frames, scored action/score/quality/coverage, updated
statistics flag, reason, selected action, unconditional probabilities and selected
probability, transition start/duration/from/to difference and means/counts.
The existing NIR DecisionEvent list remains empty. Adaptive post-session ratings
are descriptive outcomes; existing upload/worker routing excludes them from
personal EEG training and NIR learning. No HTTP occurs during active or paused
meditation; all remote start work is joined before audio acquisition.
