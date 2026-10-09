# Drift av ljudbibliotek och meditation

## Start och uppgradering

Följ konto/JWT-installationen i [README](../README.md). Starta hela stacken från
repo-roten med `docker compose up --build`. API:t finns på port 8000 och editorn
på `/editor/`. Docker-bygget bygger editorn och inkluderar FFmpeg. Workern behövs
för ljudimport, bakgrundsrendering, NIR-policyer och personlig EEG-träning.

Compose kör **en separat migrate-tjänst** efter PostgreSQLs hälsokontroll.
Den kör `alembic upgrade head` och måste avslutas framgångsrikt innan både API
 och worker startar. Worker får inte starta enbart för att `SELECT 1` fungerar:
 en äldre databas kan fortfarande sakna ljud- och meditationstabeller. API och
 worker kör inte Alembic parallellt i Compose. Vid migreringsfel, rätta orsaken
 i migrate-loggen och starta igen; lämna inte gamla och nya workers blandade.

Stoppa API/worker inför uppgradering av en befintlig installation och säkerhetskopiera
PostgreSQL samt filvolymerna tillsammans. Bygg/starta sedan samtliga tjänster med
migreringssteget. Behåll databasen och filerna vid byte av appversion. Att ta bort
volymer ersätter inte en migration.

| Backendrevision | Tillkommande data |
| --- | --- |
| 001–003 | Befintliga konton/sessioner/policyer, raderingsmarkeringar, aktivt experiment |
| 004_audio_library | Ägda källor, importstatus och worker leases |
| 005_audio_profiles | Renderjobb och oföränderliga profilversioner |
| 006_meditation_sync | Kalibreringsplaner, separat feedback, träningsjobb/requests |
| 007_meditation_deletions | Ägda raderingsepoker; rensar äldre raderad feedback/jobbevidens |
| 008_personal_eeg_models | Versionsstyrda personliga EEG-artefakter |

Appens lokala databas uppgraderas automatiskt till **schema 6** och bevarar
äldre sessioner/uppladdningar. Schema 3 lägger till profilers cache; 4 planer,
försök och feedback; 5 tränings-outbox; 6 beständiga sessionstombstones och
rensning av redan raderad meditationsevidens. Modell- och adaptionsstatistik
lagras i versionsstyrda, ägar-/källa-/uppsättningsscopade nycklar. Avinstallera
inte appen när kvarvarande offlineköer eller hårdvaruevidens behövs.

## Volymer och konfiguration

| Inställning / Composevolym | Användning |
| --- | --- |
| DATABASE_URL / pgdata | Konton, metadata, jobb, feedback, modeller, raderingar |
| AUDIO_DATA_DIR / audio | Originalfiler, kanoniska ljudkällor, fulla renderar och previews; gemensam för API/worker |
| RAW_DATA_DIR / raw | Komprimerade sessionsråfiler; gemensam för API/worker |
| EDITOR_DIST_DIR | Byggd editor, `/srv/web/dist` i Docker |
| CONTRACTS_PATH | Aktiv versionsstyrd NIR-konfiguration |
| AUDIO_PROCESS_TIMEOUT_SECONDS | Timeout per ljudprocess, standard 120 s |
| JWT_SECRET | Samma egen hemlighet i API/worker; minst 32 byte |
| ENVIRONMENT | production kräver annan JWT-hemlighet än utvecklingsstandard |

Compose anger ljud/rådatasökvägar explicit. För andra installationer måste API
 och worker ha samma miljö och läs-/skrivåtkomst till samma beständiga filer.
 Ljudfiler placeras i genererade ägar-/ID-sökvägar, inte i uppladdarens filnamn.
 Fil-API kräver bearer-token och lämnar inte ut filsystemsökvägar. Produktion
 behöver HTTPS för app och editor; endast Android debug tillåter klartext HTTP.

## Worker, återhämtning och lagringsdrift

Import- och renderstatus är **pending**, **ready** eller **failed**, sparad i
databasen. Workern plockar högst tio import- respektive renderjobb per pass och
poller sedan igen. Det finns expirerande leases och lease-specifika temporära
filer, så en avbruten worker lämnar ett pending-jobb som kan hämtas igen efter
leaseutgång. Standardlease är ungefär **270 s för import** och **420 s för render**
(timeout plus marginal). En gammal leaseägare får inte publicera över ett nyare
resultat. Import/render använder begränsade FFmpeg-protokoll och demuxers,
argumentlistor utan shell och process-timeout. Filer och jobbstatus måste bevaras
vid workeromstart.

Preview är de första 30 sekunderna av samma normaliserade PCM som fullrenderingen.
Det finns en enda dokumenterad statisk normaliseringsfaktor, ingen löpande
volymanpassning. Profiler sparar checksumma och oföränderligt renderrecept.
Sparade sessioner fortsätter peka på sin profilversion efter en editorändring.

Vid pending-jobb längre än leasetiden, kontrollera att workern kör, har databas/
volymåtkomst och kan exekvera FFmpeg. Vid failed-import läser användaren felet
 och laddar upp en korrigerad källa. Vid failed-render korrigeras receptet eller
 startas en ny rendering. Sessionsradering tar bort sessionens råfil och feedback;
 den är inte en allmän ljudbiblioteksrensning. Original, renderar och tidigare
 profilversioner förbrukar beständig lagring; bevaka volymutrymme. Ta inte manuellt
 bort refererade ljudfiler medan profiler/sessioner ska vara reproducerbara.

EEG-träningsjobb grupperas på konto, källa, protokoll och datasetfingerprint.
Identisk request-id levereras idempotent. Ett **nytt request-id** för samma
underlag kan återköa ett tekniskt failed-jobb; gammal failed-artefakt förblir
fail-closed tills ersättningen publiceras. Underkänd prediktiv validering är ett
resultat, inte ett tekniskt fel som kringgås av retry. Nytt eller ändrat underlag
bedöms med samma gates. Radering eller feedbackändring under träning hindrar
publicering av stale-underlag.

## API-områden och synkordning

- `/v1/auth/*`: befintlig registrering/inloggning/refresh/logout.
- `/v1/audio/assets`, `/v1/audio/renders`, `/v1/audio/profiles`: ägt bibliotek;
  se [editor/API-kontrakt](../web/README.md).
- `/v1/meditation/calibration-plans`: ägda, oföränderliga planer.
- `/v1/sessions`: ursprungligt rådata-/checksumkontrakt med optional
  meditation-snapshot. Feedback ändrar inte sessionsråfilens checksumma.
- `/v1/meditation/sessions/{id}/feedback`: separat revisionsstyrd återkoppling.
- `/v1/meditation/training/jobs` och `/v1/meditation/models/latest`: personlig
  EEG-träning/artefakter, separat från `/v1/training/jobs` och `/v1/bandit/latest`.
- `/v1/sessions/delete`: ägd radering med tombstones som avvisar senare upload.

Mobilens durable kö behandlar radering före uppladdning, kalibreringsplan före
sessionsdata, och feedback efter uppladdning innan dess träningsrequest.
Kontobyte hindrar gammalt HTTP-arbete från att publicera i nästa kontos cache.
Aktiv meditation använder lokala filer och en fryst modell; den behöver inte
worker eller API under själva uppspelningen.

## Aktivering

`MEDITATION_ENABLED` är en **Android-byggflagga**, avstängd som standard. Backendens
ljud-API/editor kan testas utan att flaggan ändras. Acceptansbyggen anger
`--dart-define=MEDITATION_ENABLED=true`; flaggan ger inte en EEG-modell godkänd
status. Modellens gates och kontextstöd gäller fortfarande.

Allmän aktivering kräver samlade programresultat, slutförd granskning och verkliga
Android/Muse-resultat enligt [acceptansprotokollet](MEDITATION_ACCEPTANCE.md).
Återgång är ett appbygge utan flaggan: befintligt NIR-flöde förblir tillgängligt.
Behåll migrerad databas och beständiga volymer; rollback av appflöde ska inte
radera inspelningar eller nedgradera databasen.
