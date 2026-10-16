# ADR-0002: Exakt framebudget och kompatibilitet för längre meditation

Datum: 2026-10-16. Status: verifierad inriktning för A2 / [#22](https://github.com/morre95/neuroTune/issues/22). Kravkälla: [#20](https://github.com/morre95/neuroTune/issues/20), AC-07–10, och den godkända planen i `tasks/plan.md`.

## Beslut

Lås en sessions mål som ett **heltal PCM-frames vid 48 000 Hz** när uppspelningen startar. Filens exakta frameantal och sessionens mål är olika värden. Fast längd använder filens frameantal en gång; valbar längd använder valt minutantal eller det separata valet hela filen. Ett filslut mellan hela sekunder får inte avrundas. Ingen bråkdel av en enskild PCM-frame behövs.

Endast bekräftat spelade frames avancerar aktiv tid. Köade ljudpaket, start-/slutpadding och väggklockans tid under paus gör inte det. Sessionen är klar först när sista målsatta framen har spelats. Samma låsta mål ska styra rendering, sluttid, metadata, slutförandestatus och slututtoning. Källans loopcursor styr inte uttoningens klocka.

Den fem sekunder långa slututtoningen ligger inom måltiden och når noll på sista framen. I produktion ska samma gain appliceras på bakgrund och toner efter mixning. Manuellt stopp och faktiska avbrott måste behålla korrekt hörbar nivå och stoppstatus; de implementeras i E10, inte i detta prov.

### Kompatibilitetsregel

- Schema 1, dess gamla mixrecept, publicerade profilmetadata och checksummor behåller sin betydelse. Uppgraderad app ska läsa både gammalt och nytt format; befintlig cache får inte omtolkas.
- Den gamla profil-listvägen måste fortsätta ge schema-1-profiler till klienter som inte uttryckligen begär nytt format. En okänd version i dagens lista fäller hela parsningen. A3 fastställer en separat versionsväg eller explicit kapabilitetsförhandling innan nya profiler kan publiceras.
- Befintliga `meditation-1`-sessioner och blindade kalibreringsplaner behåller exakt 600 aktiva sekunder, tio platser och sina låsta profilkopior. De migreras inte i efterhand.
- Nya längdlägen för vanlig uppspelning får ett separat versionerat sessionskontrakt/protokoll. Ett nytt pass på precis tio minuter blir **inte** automatiskt ett gammalt träningspass. Behörighet till gamla träningsdata kräver även rätt protokoll, schema, profil, källa, avslut och feedback.
- Nya pass behåller uttryckliga meditation-markörer i manifestet. Uppladdning, feedback, synk, datasetbyggare, äldre NIR-worker och radering måste alla känna igen rätt flöde. Gamla träningsgates breddas inte för att få längre pass accepterade. E5 inför deras separata kompatibilitetsväg.
- Kalibrering är fortsatt ett tydligt separat tiominutersflöde. En profil som inte kan följa både sina längdregler och kalibreringskraven ska avvisas begripligt där. Den får inte tyst loopas eller kapas i strid med sin policy; sparade serier bevaras. E11 genomför detta.

Exakta fältnamn, versionsnummer och API-val beslutas i A3 / #23. Testidentifieraren `editor-duration-probe-2` är endast en avsiktligt inkompatibel fixture, inte ett nytt produktionsprotokoll.

## Kartläggning av nuvarande konsumenter

| Område | Nuvarande beteende och fortsatt ansvar |
| --- | --- |
| `packages/neurotune_core/lib/src/audio_profile.dart`, `backend/app/profiles.py`, `contracts/audio_profile_version.schema.json` och `audio_mix_recipe.schema.json` | Schema 1, heltalssekunder 30–600; receptets duration ska matcha profilen och trim slutar senast vid 600 s. A3/E1 inför separat format, inte höjda schema-1-gränser. |
| `app/lib/data/api_client.dart`, `profile_library.dart` | Hela listan parsas med schema-1-parser; samma parser läser beständig cache. Verifieringssignaturen inkluderar checksumma och heltalsduration. Ägarskap, oföränderlighet, offlinecache och avbrutna överföringar måste bevaras i E1/E3. |
| `app/lib/data/canonical_wave.dart` | Strömmande checksumma i isolate och begränsad RIFF-inspektion. `inspect(seconds: 3600)` klarar redan heltimmesfixturen utan helfils-PCM, men exakt data-storlek kräver hela sekunder. E1 ska kontrollera frameantal och behålla stöd för oskadliga RIFF-metadatachunkar. |
| `app/lib/audio/meditation_renderer.dart` | Fast mål `600 * 48000`, paket högst 9 600 frames, 24 000-frame loopövergång och begränsad filcache i isolate. Absolut tonfas och glidehistorik måste bevaras. Befintlig slut-/stoppramp är 7 200 frames (150 ms). E4/E9/E10 ersätter relevanta tidsantaganden. |
| `app/lib/session/session_controller.dart` | Pump, budget, sista buffert och stoppramp använder rendererns fasta mål. Bekräftat native playback-head skiljs redan från köade frames och padding. E4/E10 ska behålla denna skillnad och vänta på sista hörbara bufferten. |
| `packages/neurotune_core/lib/src/meditation.dart`, `models.dart` | `MeditationProtocol.totalFrames` är 28 800 000. Slutstatus och tiominuterstext är fasta. Manifestets duration är spelade frames / 48 000 och meditation-metadata schema 1/protokoll `meditation-1`. E4/E8 behöver versionerat mål och faktisk spelad tid. |
| `packages/neurotune_core/lib/src/calibration.dart`, `app/lib/data/calibration_repository.dart` | Planen kräver 600 s. Slutförda försök kräver exakt 600 s/28 800 000 frames, rätt slutstatus, schema, protokoll, ägare och profil. Detta ska inte bli en generell längdgräns för vanlig uppspelning. |
| `meditation_adaptation.dart`, `meditation_preference_repository.dart` | Adaptation behandlar tio minutgränser och ett `meditation-1`-modellformat. Rekommendationer bygger på behållen, betygsatt och kompatibel evidens. Långa pass får inte återanvända dessa antaganden utan ett nytt uttryckligt kontrakt. |
| `app/lib/data/meditation_sync_repository.dart`, `app/lib/ui/feedback_page.dart`, `meditation_home_page.dart` | Metadata, köad feedback/träningsbegäran, val och status måste följa sessionsversionen. E5/E7/E8 samordnar detta med backend. |
| `backend/app/meditation.py`, `routers/meditation.py`, `routers/sessions.py` | Uppladdning kräver schema/protokoll 1, giltig ägd profil och 0–28 800 000 frames med matchande duration. Feedback kräver exakt målet, completed och inget stoppskäl. Planer är exakt 600 s. Träningsbegäran kräver dessutom fixed/calibration, rätt feedbackrevision och kontext. |
| `backend/app/personal_eeg.py`, `meditation.training_dataset`, `worker.build_policy` | EEG-dataset filtreras på ägare/källa/protokoll, giltig full session och feedback; adaptiva pass tas inte med. NIR-worker hoppar över meditation-markörer även i återställda rader. Versioneringen måste gälla även redan lagrade data och återuppbyggnad efter radering. |

## Isolerat prov

`scripts/probe-session-duration.dart` innehåller en liten experimentell framebudget och en begränsad WAV-läsare. Den importerar den verkliga `CanonicalWave.inspect` för att verifiera nuläget. Ingen produktionsklass, profilparser eller API-route ändras.

Omfattningen är fyra nya filer: startare, kärntest, backendtest och denna ADR, samt en uppdatering av planens nästa-steg-index. Backendtestet tillkom för att verifiera verkliga konsumenter, inom ärendets gräns på fem filer.

Fixturen är en verklig stereo 48 kHz PCM16-WAV på 691 200 044 byte. Den skrivs i återanvända block om högst 384 000 byte; inga sparse-filer eller helfilsbuffertar används. Samples skiljer både på kanal, position i paket och tvåsekundersblock, så att felaktig läsning från början av filen upptäcks även långt efter minut tio.

Hela timmen läses i 18 000 paket om högst 38 400 byte. Första och sista stereosamplen i varje paket jämförs med deterministiska förväntade värden inklusive slutgain. Simulerade kvittenser avancerar sessionsklockan separat från levererade paket. Detta är ett accelererat fil-/klockprov; ingen AudioTrack eller fysisk högtalare ingår.

Kärntesterna provar också 30 s + en frame som fast mål, 20→40 min, ogiltiga/minutbaserade val, för tidig slutförandeindikering, bakåtgående/omöjlig spelposition, riktig läsning över loopskarv, sen stereoläsning, fraktionell slutsekund, noll på sista frame samt för stora fönster, fel metadata och trunkering. En 599-sekunderskälla med 600-sekundersmål visar att slutgain fortsätter sjunka över loopskarven vid sekund 599.

**Provets avgränsning:** läsaren accepterar endast fixturens 44-byte-header, använder en enkel modulo-cursor och renderar endast bakgrund med slutgain. Den ersätter inte produktionsverifierarens RIFF-/checksummehantering, rendererns tonmix eller dess 500 ms loopövergång som överlappar och förbrukar källans öppning. E1/E4/E9/E10 måste integrera dessa med låst sessionsklocka. Detta resultat är inte fysisk Android-acceptans eller ett prov av EEG-/rådatalagring under en hel timme; E5/F2/F3 återstår.

Backendprovet går genom verkliga API-rutter, SQLite-testdatabas och nuvarande validatorer/datasetbyggare. Det verifierar schema-1-listning, avvisad okänd profilschema, oförändrad kalibrering, gränsen 600 s ± en frame, separat protokoll även vid 600 s samt återställda långa/nya rader med feedback och falska NIR-belöningar. De senare kommer inte med i gamla EEG- eller NIR-träningsdata.

## Reproduktion och mätning

Från repo-roten, med befintliga backend-/Dart-/Flutter-beroenden installerade:

```bash
cd packages/neurotune_core
dart pub get
dart test
dart analyze
cd ../..
dart analyze scripts/probe-session-duration.dart
dart compile exe --packages=packages/neurotune_core/.dart_tool/package_config.json scripts/probe-session-duration.dart -o /tmp/neurotune-session-duration-probe
/tmp/neurotune-session-duration-probe
cd backend
.venv/bin/python -m pytest -q
cd ../app
flutter test --reporter compact
```

Programmet skriver JSON-mått till stdout och tar bort sin temporära fixturekatalog i `finally`, även vid provfel. Cirka 660 MiB ledigt filutrymme behövs. Referensmaskinens `/tmp` är tmpfs; källfilen belastar därför värdminnet utanför processens RSS. AOT-kompilering körs före mätningen, inte inne i mätloopen.

Referensmiljö 2026-10-16: AMD Ryzen 7 5800X, Linux 7.2.5-3-omarchy x86_64, Dart 3.13.5 AOT, Python 3.14.7. Ingen tvingad garbage collection.

| Mått | Uppmätt |
| --- | --- |
| Fil / bekräftade frames | 691 200 044 byte / 172 800 000 frames |
| Paket / största PCM-paket | 18 000 / 38 400 byte |
| Accelererad läsning inklusive samplekontroller och RSS-sampling | 915 ms |
| `ProcessInfo.currentRss`, baseline → högsta observerade | 10 670 080 → 15 347 712 byte, tillväxt 4,46 MiB |
| Linux `/proc/self/status` VmHWM, före → efter | 10 735 616 → 14 114 816 byte |
| Låst gräns för både observerad RSS-tillväxt och VmHWM-tillväxt | 128 MiB |

RSS är processens residenta minne, inte Dart-heap, PSS eller hela maskinens minne. Plattformarnas räknare har olika bokföring och Linux uppdaterar RSS asynkront; deras absoluta tal ska inte subtraheras från varandra. Rå `ProcessInfo.maxRss` var redan 727 691 264 byte före mätloopen i denna körmiljö och ändrades inte. Därför redovisas den separat i JSON, medan Linux-provet kontrollerar den egna processens VmHWM och den observerade currentRss-tillväxten. Tröskeln är ett riskprovsbudgetförslag för A3, inte en ny eller sänkt gräns i gamla tester.

## Verifiering och granskning

- RED: de nya Dart-testerna misslyckades innan provimplementationen fanns; GREEN: fyra nya tester och hela kärnsviten passerar, 44 tester totalt. Ingen befintlig testgräns ändrades.
- Mutation: inverterad paketgräns (`count > 9600` → `count < 9600`) gav förväntat testfel vid loopläsningen. Originalet återställdes och verifierades igen.
- Befintlig appsvit: 219 tester passerar, inklusive sista buffert, avbrott, offlineprofiler, feedback och kalibreringsserier.
- Backendsvit: 65 tester passerar, inklusive två nya kompatibilitetsprov. De 16 befintliga Alembic-varningarna om `path_separator` är oförändrade.
- Backendtestet initialiserar `test_api` före appens databasimport så att även en separat körning använder testdatabasen. Ett första försök med omvänd importordning skapade en lokal databas; den togs bort efter kontroll att alla dess ägare kom från just provets två fixtures. Omkörningen använder isolerat minne.
- Granskning: kontrollerade exakt slutframe, separat levererat/spelat antal, beständig framebudget, begränsade buffertar, filfel, gamla träningskonsumenter och oförändrad produktionskod. Inga nya beroenden, migrationer eller testsuppressioner.

## Officiella källor

Darts fil-API dokumenterades via Context7 före implementation. `RandomAccessFile.read` kan returnera färre byte än begärt, vilket provet kontrollerar; asynkrona operationer på samma filhandtag serialiseras. Minnesräknarna kontrollerades dessutom mot officiell Dart- och Linux-dokumentation när räknarna skilde sig åt.

- [Dart RandomAccessFile.read](https://api.dart.dev/dart-io/RandomAccessFile/read.html) och [setPosition](https://api.dart.dev/dart-io/RandomAccessFile/setPosition.html).
- [Dart ProcessInfo.currentRss](https://api.dart.dev/dart-io/ProcessInfo/currentRss.html) och [maxRss](https://api.dart.dev/dart-io/ProcessInfo/maxRss.html).
- [Dart compile exe](https://dart.dev/tools/dart-compile#exe); `--packages` kontrollerades även med installerade Dart 3.13.5:s `dart compile exe --help`.
- [Linux proc: VmHWM, VmRSS och asynkron RSS-bokföring](https://docs.kernel.org/filesystems/proc.html).

Nästa steg är A3 / #23: för in framebudget, profil-/sessionsversionering och kompatibilitetsregler i de gemensamma kontrakten, tillsammans med A1:s verifierade minnesbegränsade webblyssning från ADR-0001.
