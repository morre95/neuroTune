# neuroTune-appen

Flutter-klienten för Android. Installation, Muse SDK och backend beskrivs i
[README](../README.md). Meditation är ett separat huvudflöde bakom
`--dart-define=MEDITATION_ENABLED=true`, avstängt som standard före fysisk
acceptans. Utan flaggan visas det befintliga NIR-experimentflödet. Med flaggan
finns NIR-lägena kvar i **Experiments**.

Skapa en profil i backendens `/editor/` med samma konto, öppna **Ljudprofiler**,
uppdatera och ladda ned. Först **Nedladdad · redo offline** tillåter sessionsstart.
Format/checksumma verifieras före readiness och vid cacheläsning efter omstart.
Välj profil, ögonläge och Simulator/Muse; lokal förhandslyssning är 30 sekunder.
Ta bort lokal kopia för att frigöra mobilens lagring.

Meditation spelar **600 aktiva sekunder**, bekräftade av Android AudioTracks
played-frame-progress. Accepterade paket räcker inte för slutförande. WAV-läsning
 och stereomix körs i en begränsad worker-isolate, med fast gain, carriercentrerade
 toner, 500 ms bakgrundsöverlapp, fem sekunders frekvensglidning och 150 ms
 start-/stoppramper. HTTP avslutas före start; retries vilar medan sessionsvyn
 är öppen. Saknad/dålig EEG och Muse-frånkoppling stoppar inte meditationsljudet.
 Ljudavbrott pausar klockan och bevarar spelad bakgrundsposition vid återupptagning.

**Kalibrering** låser profil/ögonläge/källa i en tiopassserie, två vardera av
0/6/8/10/12 Hz. Tilldelningar är dolda tills serien är klar; en partiell serie
bidrar inte till synlig fast rekommendation eller per-tonmedelvärde. Två
0–10-skattningar sparas efter full session, även offline och över omstart.
Skattningarna synkas separat från rådata. EEG-modellen behöver minst tjugo
användbara fulla skattade fasta sessioner samt prediktiva gates/kontextstöd.
Simulator och Muse förblir separata. [Användarregler](../docs/ADAPTIVE_MEDITATION_AUDIO.md)
förklarar scoring, modell och radering.

Manifestets optional `meditation`-snapshot skiljer protokoll/profil från NIR och
sparar EEG-kvalitetskonfiguration. `duration_seconds` är aktiv spelad tid;
rå EEG/optics och feature `time_seconds` behåller källklockan. Observed-time/
played-frame-checkpoints och källoffset mappar featurefönster till optional
`active_time_seconds` och `playback_active`. Fönster som korsar avbrott eller
okänd/stannad uppspelning får ingen sådan tilldelning. Uppspelningscoverage är
separat från EEG-validitet; inlärning räknar även saknade sekunder.

Lokala migrationer går till schema 6 och bevarar äldre inspelningar och köer.
[Driftinstruktionerna](../docs/MEDITATION_OPERATIONS.md) beskriver migrationskedjan.
Kör `flutter test` och `flutter analyze`; [acceptansprotokollet](../docs/MEDITATION_ACCEPTANCE.md)
kopplar testsömmarna till editor, persistence, PCM och fysisk Android/Muse.
