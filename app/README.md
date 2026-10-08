# neuroTune-appen

Flutter-klienten. Installation, backend och hur du kör appen beskrivs i [README](../README.md) i repo-roten.

Meditation is an optional primary flow (`--dart-define=MEDITATION_ENABLED=true`),
with general release defaulting to disabled until physical acceptance. Existing
NIR modes remain in **Experiments**. Select a verified downloaded profile, eye
state and fixed 0/6/8/10/12 Hz action. Session start reads the cache, joins pending
upload/library HTTP and suspends retries until the session view is closed.

Meditation plays 600 seconds confirmed by AudioTrack played-frame progress;
accepted packets alone cannot complete a session. WAV reads and stereo mixing
run in a bounded worker isolate, with fixed profile gains, carrier-centered
tones, 500 ms background loop overlap and 150 ms start/stop ramps. Missing or
poor EEG and a Muse disconnect do not stop this audio protocol.

The optional manifest `meditation` snapshot separates this protocol/profile from
NIR policies and records the EEG quality configuration. `duration_seconds` is
active played duration; raw EEG/optics and feature `time_seconds` keep their
source clock. Historical observed-time/played-frame checkpoints plus the source
offset map a feature window to optional `active_time_seconds` and
`playback_active`. A window crossing an interruption or unknown/stalled playback
coverage remains unassigned. Playback coverage is independent of EEG validity;
later learning must still apply quality checks and count missing seconds.
