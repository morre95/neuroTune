# Acceptansprotokoll för meditation (#16)

**Allmän aktivering är ännu inte godkänd.** `MEDITATION_ENABLED` förblir avstängd
som standard. Den här filen skiljer verifierad programvara från faktiska
telefon-/Muse-resultat. Uppdatera resultat, versioner och evidens när varje kontroll
har körts. Stäng inte [#16](https://github.com/morre95/neuroTune/issues/16) eller
[föräldraspec #1](https://github.com/morre95/neuroTune/issues/1) med enbart
simulator- eller browserresultat.

## Sammanhängande editor-till-telefon-flöde

Använd ett separat testkonto och egna korta musik-/naturljudsfiler. Håll samma
konto och samma backendinstans i editor/app. Notera commit, backendmigrationsrevision, appbygge, enhet,
Android-version, headset och profilversions-ID före start.

1. Starta API, worker och migration enligt [driftinstruktionen](MEDITATION_OPERATIONS.md).
   Logga in i `/editor/`. Prova WAV, MP3, M4A/AAC och FLAC, mono och stereo.
   Bekräfta tydliga fel för korrupt/ej stödd fil och dokumenterade storleks-/tidsgränser.
2. Kombinera upp till fyra spår med olika trim/gain/loop. Rendera 30–600 s,
   förhandslyssna och spara namngiven profil med bärare/gains. Ändra och spara
   version 2. Version 1 och dess checksumma ska fortfarande finnas.
3. Öppna **Ljudprofiler** på telefonen, förhandslyssna, ladda ned och invänta
   **Nedladdad · redo offline**. Testa avbruten nedladdning och lokal borttagning;
   ladda sedan ned igen och starta om appen. Välj rätt profilversion.
4. Genomför fast meditation med valt ögonläge. Gör hårdvarukontrollerna nedan.
   Full session ska visa 600 aktiva sekunder och sparas som completed.
   Stoppad/felaktig session ska sparas som stopped och inte fylla en kalibreringsplats.
5. Skapa **Kalibrering → Ny serie · Muse** (Simulator används endast för
   programkontroller). Slutför tio hela sessioner med båda efter-skattningarna.
   Tonetiketter ska vara dolda till dess och förbli dolda vid omstart/historik/
   återuppspelning. Lämna ett feedbackutkast och återuppta det efter appomstart.
6. Börja offline, spara skattningar, återanslut och invänta synk. Kontrollera att
   upprepad synk inte dubblerar sessioner/feedback. Se **Resultat och fast ton**,
   välj en egen fast ton och kontrollera den efter omstart. En partiell ny serie
   ska inte ändra synliga per-tonresultat eller avslöja sin första tilldelning.
7. Samla ytterligare fulla, fasta skattade sessioner. **Uppdatera EEG-modell**
   ska visa insufficient/failed-validation och behålla fast ljud när gates inte
   klaras. Minst 20 användbara sessioner är nödvändigt men garanterar inte ready.
   Uppge vilken faktisk modell/källa som bedömts; fejka inte Muse-underlag för
   att få en grön status.
8. När en modell blir ready och stöder uppsättningen, starta adaptation offline.
   Versionen ska vara fryst; minutbeslut och kvalitet sparas. Försämra EEG som
   nedan och kontrollera hold/ingen inlärning. Använd inte en syntetisk
   simulatorartefakt som ersättning för fysisk Muse-modellacceptans.
9. Radera egna sessioner offline i **Sessionshistorik**, återanslut och kontrollera
   bekräftad synk, borttagen feedback, ogiltigt berört modellunderlag samt att
   fördröjt uploadförsök inte återställer sessionen. Kontrollera kontoseparation
   med ett andra testkonto. Behåll övriga historik-/NIR-sessioner.
10. Kör ett appbygge utan flaggan. Inloggning, Personlig/Jämförelse, simulator,
    historik och diagnostik ska förbli användbara; meditation/bibliotekskontroller
    ska vara dolda.

Att samla 20 verkliga sessioner är longitudinellt användararbete. En syntetisk
modell i automatiserade tester demonstrerar API/matematik/controllerbeteende,
men ersätter inte den insamlingen eller visar adaptationens effekt.

## Automatiserade kontroller

Kör från respektive katalog. Backend behöver sin installerade dev-extra och
FFmpeg; web behöver npm-dependencies och Playwright Chromium. Flutter/Dart
behöver installerad SDK och appens Androidbygge behöver libmuse.

| Katalog | Kommando |
| --- | --- |
| packages/neurotune_core | `dart test` och `dart analyze` |
| app | `flutter test` och `flutter analyze` |
| backend | `.venv/bin/python -m pytest -q` |
| web | `npm run build`, `npm test`, `npm run test:acceptance` |
| repo-roten | `docker compose up --build` med separat teststack för uppgraderingsacceptans |

`test:acceptance` startar en verklig API/worker på localhost:18016 med temporär
SQLite/datavolymer och kastbara konton. Den återanvänder ingen befintlig backend.
Vid annan Python-installation, ange `NEUROTUNE_BACKEND_PYTHON` som dokumenterat i
[webb-README](../web/README.md). Behåll Playwright-trace vid fel. Denna kontroll
slutar vid editor/backendens nedladdningsbara profil, inte vid Android AudioTrack.

| Kontrollerat beteende | Beständig regressionsevidens |
| --- | --- |
| Verklig browserlogin, WAV/FLAC-import, tvåspårsmix, ready-render/preview, sparad revision, PCM/checksumma och ägande | web/tests/acceptance.spec.ts + verklig worker/FFmpeg |
| Synliga importfel, fyrspårsrecept, progression, gain-gräns, precis trim och senare editor under pending save | web/tests/import.spec.ts, profiles.spec.ts |
| Codecs, mono/stereo, importgränser, ägande, immutable mix, worker lease/timeout | backend/tests/test_audio.py, test_profiles.py |
| Äldre migrationer, feedback/upload/deletion-ordning och NIR-bevarande | backend/tests/test_migrations.py, test_meditation_sync.py, test_meditation_deletion.py, test_learning_deletion.py; app/test/database_migration_test.dart, meditation_sync_test.dart |
| Kanonisk cache, cancel/korruption, omstart, kontoseparation och lokal borttagning | app/test/profile_library_test.dart |
| 600 aktiva sekunder, real local persistence, optics-oberoende data, signalbrist | app/test/meditation_session_test.dart med fake PCM |
| Offline UI/controller, ljudavbrott, spelad cursor, failure och watchdog | app/test/meditation_offline_test.dart, meditation_interruptions_test.dart, meditation_output_lifecycle_test.dart |
| Dold balanserad plan, låst setup, ofullständiga försök, feedback/restart | app/test/calibration_session_test.dart, calibration_ui_test.dart, calibration_reveal_test.dart |
| Fasta val, komplett-serie-resultat och ingen indirekt blindingläcka | app/test/recommendation_repository_test.dart, recommendation_ui_test.dart, calibration_recommendation_blinding_test.dart |
| Session-level modellgates, simulator/Muse-separation och Python/Dart-paritet | backend/tests/test_eeg_model_math.py, test_personal_eeg_api.py; core/app model-/cache-tester och gemensamma contracts/fixtures |
| Minutadaptation, kvalitet-hold, fryst modell, statistik/radering | app/test/meditation_adaptation_test.dart, meditation_policy_test.dart, meditation_learning_deletion_test.dart |
| Feature-default och användbara befintliga NIR-kontroller | app/test/auth_flow_test.dart |

## Resultatlogg för programvara

Baslinje **2026-10-09, ac96d0f**: core **37** och Flutter **187** tester godkända;
backend **60** godkända; båda Dart-analyser rena; webbygge och **8** browserkontroller
med HTTP-fixtures godkända. Baslinjen verifierar tidigare beteende, inte slutliga
releasefixar.

Fokuserad verifiering av #16-fixar:

- Default-disabled bibliotekskontroll: failing före fix, passing efter fix.
- Blindade delserier: repositoryregressionen failing före fix och passing efter;
  appflödet verifierar control-fallback samt complete-series-fallback/per-tonresultat.
- Tekniskt failed EEG-jobb: färsk request återköar samma dataset, repeated failure
  publicerar ny failed-artefakt och senare retry respekterar insufficient-gaten.
- Delayed-save: browserregressioner reproducerade för både success/error; ny editor
  och nya profilinställningar bevaras efter fix.
- Isolerad verklig browser/API/worker-kontroll: **1 godkänd**, FFmpeg med WAV/FLAC,
  två spår, ljudpreview, två immutable versioner och privata verifierade downloads.
- Compose migration-first och Android-APK:
  **verifierad 2026-10-09** på separat PostgreSQL 16-stack: 003→008 bevarade
  äldre sessionsdata; migrate exit 0 föregick API/worker-start. Verkliga HTTP-importer
  och en tvåspårsrender sparade en profil. Debug-APK från 6261646 byggdes och
  installerades på Samsung SM-S921B/Android 16. Dessa är bygg-/driftresultat;
  full fysisk sessionsacceptans återstår.

Programverifiering före AudioTrack-fixarna **2026-10-09, integration/adaptive-meditation 6ae2c30**:

| Kontroll | Resultat |
| --- | --- |
| Flutter, full svit | **190 godkända**, 106 s |
| Flutter-analyser | **Inga problem**, 2,5 s |
| Backend, full svit | **61 godkända**, 27,20 s; 16 befintliga Alembic-deprecationvarningar |
| Browser med HTTP-fixtures | **11 godkända**, 8,6 s |
| Verklig isolerad browser/API/worker | **1 godkänd**, 11,3 s |
| Webbygge | **Godkänt** |
| Core | **37 godkända**, ren analys på ac96d0f; core-koden oförändrad i #16 |

Appverifiering **2026-10-09, 500b0e8** efter buffert- och watchdogfixarna:
**197 Flutter-tester godkända, 104 s**. Fokuserad playback/lifecycle-regression:
**27 godkända, 11 s**; Flutter-analys ren, 0,7 s. Backend/web/core-resultaten ovan
avser sina angivna versioner; deras kod ändrades inte av dessa ljudfixar.
Debug-APK från 500b0e8 byggdes på 10,5 s och installerades på telefonen med
`MEDITATION_ENABLED=true`, `API_BASE=http://127.0.0.1:8000` och SHA-256
`c3b2b977903256bdeb182ef315d3248f16cd50469c57cd521afcb14927ff4230`.
Ett fullt fysiskt 600-sekunderspass med detta bygge är verifierat nedan;
full flygplanslägesacceptans är fortfarande pending.

Slutlig appverifiering **2026-10-09, 98d7073** efter UI-övergångsfixen:
**197 Flutter-tester godkända, 103 s**; **Flutter-analys utan problem, 1,0 s**.
Debug-APK byggd på **10,8 s** och installerad framgångsrikt på testtelefonen.
Den fysiska 600-sekundersljudverifieringen nedan gäller 500b0e8; denna senare
ändring rör enbart övergången från session till feedback.

Koppla slutliga resultat till den testade committen; lägg till antal, datum,
plattform och kvarstående fel här före release. Räkna inte en kodläsning som ett
kört test, och räkna inte fake PCM som lyssning på fysiskt Androidljud.

## Fysisk Android/Muse-acceptans

Fyll i varje rad efter faktisk kontroll. Spara sessions-ID, manifest/historik
 och tillhörande raw/decisions, relevanta loggar och lyssningsobservationer i en
 åtkomstbegränsad testjournal. Publicera inte rå persondata i en GitHub-kommentar.

Enhets-/byggrecord:

| Uppgift | Värde |
| --- | --- |
| Testdatum och testare | 2026-10-09: användarprov och ADB-observationer; partiellt pass dokumenterat nedan |
| Appcommit/APK och featureflagga | Senast installerat: 98d7073 debug, MEDITATION_ENABLED=true; verifierat 600 s-pass på 500b0e8 |
| Telefon / Android-version | Samsung SM-S921B / Android 16; full sessionsacceptans pending |
| Muse/headset/SDK | Muse S Athena ansluten / Bose QC35 II Bluetooth-hörlurar, modell observerad i telefonens Bluetooth-vy / libmuse Android 8.0.9 |
| Profilversion / checksumma / bärare / gains / ögonläge | Pending |
| Session-ID och logg/evidensplats | Pending |

Delobservation **2026-10-09 09:51 UTC**: ADB visade flygplansläge på och Bluetooth
på. Användaren rapporterade att toner och bakgrund hördes, men aktuella
ADB-skärmbilder visade inloggningsvyn. Inloggning med testkontot och verifierad
profilcache återstod; observationerna kunde inte knytas till ett sparat
meditationspass. Ingen full 600-sekunderssession eller offlineacceptans är därmed
bekräftad. Vid denna tidpunkt förblev samtliga fysiska resultatrader pending.

**Fysiskt startfel, 2026-10-09 cirka 10:05 UTC:** på Samsung SM-S921B/Android 16
med Muse och Bose Bluetooth-hörlurar stoppades meditationen på **0/600 s**
med `Audio playback stopped progressing`. Det testade debug-bygget var fcd601a
och pekade på den lokala API-instansen på port 8000. Användaren bekräftade att
Muse-sessionen inte kunde starta. Full offlineacceptans är ännu inte verifierad.

Koden begärde en 250 ms AudioTrack-buffer men matade högst 150 ms innan spelad
progress krävdes. Androids stream behöver sin starttröskel uppfylld, vars standard
är buffertkapaciteten; se [AudioTracks officiella starttröskeldokumentation](https://developer.android.com/reference/android/media/AudioTrack#getStartThresholdInFrames()).
Controllerregressionen reproducerade därför 0 spelade frames med en 250 ms sink.
Fix **18f88c3** hämtar verklig tröskel (API 31+) eller kapacitet på äldre Android,
primmar en begränsad kö och läser om tröskeln vid återupptagning/routändring.
Ett kort sluttail/stopp behöver också kunna primmas; eventuell efterföljande
nollpadding räknas aldrig som meditationsinnehåll eller aktiv tid. 200 ms-paket
och tvåsekunders watchdog behålls. Startup/resume, routändring/underrun och kort
stopp blev gröna i fokuserade fake-PCM/controller-tester.

**Fysisk omtestning av 18f88c3, cirka 10:19 UTC**, stoppades fortfarande på
**0/600 s** med samma watchdogfel. Buffertregressionen är täckt, men den kvarvarande
fysiska orsaken är ännu inte bekräftad. Debug-bygget i **eab568c** tillför endast
avgränsade AudioTrack-/controller-räknare (tröskel, accepterade/spelade frames,
kö och stalltid), utan PCM, EEG eller kontodata, för nästa omtestning. Vid detta
omtest var ingen Androidsession godkänd och inga timeoutgränser hade förlängts.

Ytterligare controllerregression visade att tvåsekundersgränsen för spelad
progress kunde löpa ut innan en större native-buffer var helt fylld, trots att
varje PCM-paket accepterades inom sin deadline. Watchdoggen armeras nu efter
uppfylld starttröskel; accepterade primmingpaket återställer dess stallklocka.
Varje render/write behåller tvåsekundersdeadline, native-tröskeln är begränsad
till en sekund och paket till 200 ms. Ett helt primmat sink utan spelad progress
stoppas fortfarande efter två sekunder. Både långsam framåtskridande primming
och detta verkliga stallkontrollfall är regressionstestade. Ett senare fullt
fysiskt pass med ändringen dokumenteras nedan.

**Partiellt fysiskt pass efter nytt försök med 18f88c3:** ADB visade **103/600 s
vid 10:25:31 UTC**, **384/600 s vid 10:30:13 UTC** och stoppat pass på **518/600 s
vid 10:33:08 UTC**. Användaren bekräftade att hen uttryckligen tryckte **Stoppa**;
resultatet är därför ett manuellt avslutat pass, inte belägg för ett misslyckat
fokusavbrott/återupptagning. Användaren hörde en stadig ton och bekräftade att
ljudet fortsatte när skärmen var släckt. Sparad inspelningscoverage under släckt
skärm har ännu inte verifierats.

Flygplansläge var **av** under detta pass och USB-reverselistan var tom. Det
bevisar varken 600 aktiva sekunder, completed eller full offlineacceptans.
Muse-EEG syntes i appen, men kontaktkvaliteten var **0/4** och inget verifierat
ready Muse-modellunderlag demonstrerades. Passet visar därför inte adaptiv
kvalitet-hold eller skipped learning. Ett nytt fullständigt offlinepass med
flygplansläge från start och Bluetooth för Muse/hörlurar återstår.

**Fullt fysiskt ljudpass med 500b0e8, cirka 10:39–10:49 UTC:** native-ljudklockan
nådde **28 800 000 spelade frames** vid 48 kHz, med **115 200 000 accepterade bytes**
och tom utgångskö vid avslut. Det motsvarar exakt **600 aktiva sekunder** av stereo
PCM16. Verklig starttröskel, kapacitet och buffer var alla **12 000 frames**
(250 ms). Användaren bekräftade att passet slutade utan ljudfel; appen visade
600 sekunder. Telefonen var släckt vid avslut och tidigare lyssning med släckt
skärm var användarbekräftad.

Den lokalt sparade sessionen är verifierad som **completed**, med duration
**600 s**, completed-fas, inget stoppskäl och 28 800 000 spelade frames i fixed-
läge. Motsvarande fulla session finns också på servern, verifierad mot samma
sessions-ID utan att publicera persondata. Den lokala feedbackraden innehåller
**båda efter-skattningarna, revision 2**. Servern har motsvarande revision med
båda skattningarna; lokalt feedback-synkjobb är **done** utan fel. Serverråfilen
finns, **3 403 234 bytes zstd-komprimerad lagrad fil**. Skopad dekomprimering
verifierade tids-/mängdmetadata nedan utan att publicera råa signalvärden.

Sparad bearbetad inspelning innehåller **596 EEG-frames**, med loggade frame-tider
**4,254–602,596 s** och största gap **4,342 s**. Det finns **11 589** spelklocke-
checkpoints och inga `audio_failed`-/`audio_interruption`-diagnostikhändelser för
passet. Detta verifierar inspelningsnärvaro och dessa tidsmått, inte att Muse-
kontakten var godkänd eller att adaptationens kvalitetsgates uppfylldes.
Serverråfilen innehåller **1 206 EEG-batcher**, **1 202 optics-batcher** och
**154 368 EEG-samples per kanal vid 256 Hz**. EEG-tidsstämplarna är monotona,
med spann **0,253978–600,455071 s** och största positiva interbatch-gap
**0,011211 s**. Detta stödjer fortsatt råinspelning över hela passet.
Batchintervall kan överlappa: summerad sampletid är 603 s medan tidsstämpelspannet
är cirka 600 s. Därför innebär dessa mått inte bevis för exakt förlustfri
realtidsinsamling. Kontakt-/signalkvalitet och koppling till ett exakt markerat
skärm-av-intervall i samma 600-sekunderspass är fortfarande inte verifierade.

Flygplansläge var **av** under detta fulla pass och USB-reverselistan var tom.
Det verifierar fullt lokalt ljud utan USB-API-förbindelse, men uppfyller inte
kravet på 600 sekunder i flygplansläge. En separat observation med flygplansläge
på och Bluetooth på föregick passet; den ska inte slås ihop med 600-sekunders-
resultatet. Ett verkligt fokusavbrott med återupptagning och adaptation med en
ready Muse-modell är fortfarande pending.

Efter passet gav **Avsluta session** en övergående röd felvy. Widgetregression
med verklig SQLite i bakgrundsisolate reproducerade null-check-felet när appen
byggdes om mellan controller-disposal och feedbackladdning. Fix **98d7073** byter
atomiskt till en inaktiv slutförandevy innan controller lämnas, håller
avslutningsspärren till feedback/fallback och blockerar bakåt under övergången.
Fullt avslutat pass, snabb dubbeltryckning, bakåt och återkopplingsrouting blev
gröna i **14 fokuserade widgettester, 38 s**, med ren analys, 0,7 s.
Fysisk omtestning av just UI-övergången återstår; ljudets verifierade
600-sekundersresultat ovan gäller 500b0e8. Debug-APK från 98d7073 byggdes på
**10,8 s** och installerades framgångsrikt på samma telefon.

| Fysisk kontroll | Förfarande och förväntat resultat | Resultat |
| --- | --- | --- |
| Full offline-session | Ladda ned online, starta om appen, sätt flygplansläge, återaktivera Bluetooth för Muse om det behövs. Kör 600 aktiva sekunder med stereohörlurar. Hör både bakgrund och lokala toner; completed och 600 s i historik. Ingen nätåtkomst behövs. | Fullt lokalt 600 s completed verifierat på 500b0e8; flygplansläge var av, full offlinekontroll pending |
| Skärm av | Släck skärmen under en väsentlig del av samma pass. Ljud och inspelning ska fortsätta; förgrundstjänsten kvarstår och sparade EEG-/tidsspår har fortsatt coverage. | Ljud användarbekräftat; fortsatt råinspelning över 500b0e8-passets 600 s verifierad. Exakt skärm-av-intervall i samma pass är inte markerat/korrelerat; full kontroll pending |
| Ljudinterruption/recovery | Använd ett verkligt fokusavbrott (t.ex. annat ljud eller samtal). Aktiv klocka pausar under tyst tid. Återuppta: samma ton och bakgrundscursor, inga hopp eller replay av gamla buffers; avsluta med 600 aktiva s. | Pending |
| Muse-kvalitetsförlust | Under ett adaptivt pass med verkligt ready Muse-underlag, försämra kontakten så minst en utvärderingsminut blir otillräcklig. Ljud och aktuell ton kvarstår; sparat beslut visar kvalitet-hold och inga nya statistikobservationer för perioden. | Pending |
| Kanal-/mixlyssning | Lyssna på vänster/höger-tonpar, bakgrundens stereokaraktär, loopskarv och minst ett mjukt tonbyte. Ingen hörbar clipping/klick eller bakgrundsreset. | Pending |
| Feedback/radering/synk efter offlinepass | Spara båda skattningarna offline, starta om, återanslut och synka. Radera ett testpass och kontrollera tombstone/beroende underlag utan återställning. | Pending |

Den första fyra-radsgruppen är uttryckliga hårdvarukrav i #16. En fysisk fixed-
session med dålig kontakt visar att ljudet fortsätter; den bevisar inte skipped
learning för en adaptiv Muse-modell. Om verkligt ready-underlag saknas, skriv den
begränsningen och lämna den adaptiva fysiska kontrollen pending.

## Releasebeslut

Kräver godkänd samlad programregression och granskning, fungerande uppgradering/
workerdrift, konkret sammanhängande användarflöde, samt alla uttryckliga fysiska
kontroller utan öppna fel. Bekräfta föregående ärendens acceptans mot deras
regressionsevidens och fysisk record. Dokumentera ansvarig, commit, datum och
resultat innan allmän featureaktivering och issue-closure. Vid kvarstående
hårdvaru- eller modellunderlag ska #16/specen förbli öppna och standardflaggan av.
