# Meditation learning deletion

Deletion preserves account UUID, origin, protocol, exact setup, and opaque model
version ownership. The explicit fixed preference is independent of evidence.

## Server publication and rebuilding

The owned session deletion transaction retires feedback, request aliases, raw
recording references, and training snapshots. Every model containing a deleted
included session loses its persisted body, including models detached from jobs.
A job containing an excluded unusable row may be removed without revoking its
unaffected fitted artifact. Adaptive ratings never enter EEG fitting.

An affected learning scope gets an evidence-free latest `revoked` marker and a
durable queued job over the remaining authoritative fixed/calibration dataset.
The fingerprint remains canonical. Reusing an older identical dataset detaches
its prior job/model FK and refits into a new opaque model version. A historical
ready artifact is never selected as the replacement. Consecutive distinct
retirements replace pending rebuild intents; an empty revoked marker cannot
suppress the next rebuild. Repeating the same tombstones changes neither epoch
nor replacement intent.

The worker checks the current fingerprint and deletion epoch after fitting under
the owner lock. Changed evidence cannot publish. If only an unrelated deletion
changed the epoch, the unchanged canonical intent stays queued for a later pass;
this pass still publishes nothing. Normal sample, quality, validation, supported
context, and inclusive numeric-range rules remain unchanged.

## Device retirement and reconciliation

Local owned deletion commits tombstones and targeted cache cleanup together.
Deleted fitted evidence replaces that source's model body with a thin revoked
marker and removes all dependent statistics, even when the evidence never seeded
this exact setup. Deleting an adaptive-only session removes its contribution
records from the same valid model/version; retained tuples rebuild counts/means.
No totals move into another model version. Fixed preferences, other accounts,
other sources, and NIR learning remain independent.

Authenticated `GET /v1/meditation/deletions` returns schema version 1, the owner's
`deleted_session_ids`, and nonnegative `deletion_epoch`. Idle meditation sync
reads this ledger before raw/rating/training delivery, commits known or absent
phone evidence as durable tombstones, then cleans raw files. This discovers
already-acknowledged adaptive deletions on another device even when the ready
EEG model stays unchanged. Existing foreign/legacy local session ownership is
respected. Tombstones are idempotent and survive restart. Model provenance from
another device is accepted until explicitly revoked; absence alone is not
local deletion.

Idle sync subsequently refreshes latest models for each source. Failed,
insufficient, missing, invalid, or revoked latest artifacts replace stale
readiness and retire prior statistics. A qualified replacement starts a fresh
version bucket. Valid recorded observations from a session frozen on an older
still-valid model can be retained in that original bucket; they never seed the
new version. Old seed-only or malformed buckets cannot resurrect old readiness.

Publication checks local evidence freshness, owned tombstones, known checksums
and feedback revisions, current auth/navigation/session state, and a durable
cache compare-and-set across the HTTP wait. Transaction cancellation rolls back
retirement/publication. Epochs guard incoming publication, not blanket cached
usability. Neither remote reconciliation nor model refresh runs during an active
or paused session. Offline or unqualified learning falls back to the persisted
preferred fixed action. No additional collection gate or migration is introduced.
