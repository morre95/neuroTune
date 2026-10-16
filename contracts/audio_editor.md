# Audio editor: versionerade kontrakt

Status: implementerat kontraktsunderlag för A3 / [#23](https://github.com/morre95/neuroTune/issues/23), inom godkänd [specifikation #20](https://github.com/morre95/neuroTune/issues/20) och `tasks/plan.md`. Datum: 2026-10-16. Detta dokument definierar kommande beteende; det aktiverar inga API-rutter. **K1 är granskad och godkänd av användaren 2026-10-16.** Nästa genomförandesteg är projektlagringen B1 / #24.

## Gemensamma typer och gränser

Alla nya ljudpositioner är heltal **PCM-frames vid 48 000 Hz**, inte byte, MP3-paket eller avrundade sekunder. Intervall är halvöppna `[start_frame, end_frame)`. Heltal ska vara matematiskt heltal, aldrig bool, sträng eller en avrundad bråkdel. Backend och Dart ska avvisa icke-finita tal. UUID- och RFC 3339-format valideras uttryckligen; `format` är inte automatiskt en assertion i alla JSON Schema-verktyg.

| Gräns | Normativt värde |
| --- | --- |
| Källa och färdig komposition | 1–172 800 000 frames (högst 3 600 s) efter kanonisering |
| Tomt sparat projekt | Tillåtet: noll klipp och `frame_count: 0`; får inte renderas/publiceras |
| Importerad fil | Högst 1 073 741 824 byte, kontrollerat under strömmande uppladdning |
| Kanoniskt ljud och WAV-export | Stereo, 48 000 Hz, PCM16 little-endian; exakt `frame_count * 4` byte i data-chunken |
| Sekvens | Högst 100 klipp; samma källa får återanvändas med olika klipp-ID:n |
| Klippgain / profilheadroom | Klipp 0–4; profilens ton-/bakgrundsgain vardera 0–0,95 och summa högst 0,95; carrier 100–400 Hz |
| Klippövergång | Cut = 0 frames; linjär crossfade = 1–480 000 frames, aldrig oavsiktlig trippelöverlapp |
| Appens valbara mål | Hela filens exakta längd, förvalt; alternativt heltal 1–60 minuter i steg om 1 |
| Slututtoning | `min(240000, target_frames)` frames, inom vald tid, gemensam för bakgrund och toner |
| Autosparande | Samla ändringar cirka 1 s före försök; osparat/sparar/sparat/fel och synlig konflikt |

Scheman använder Draft 2020-12 och befintlig identifierarkonvention `https://neurotune.dev/contracts/`. Ladda referenser från lokalt register; schema-ID är inte en instruktion att hämta externa dokument vid validering. Okända fält avvisas i kontraktsobjekten. Schema-version 1 för **nya** `audio_sequence`/`audio_project` är skild från befintliga samtidiga mixrecept; `kind` förhindrar sammanblandning.

- `audio_sequence_recipe.schema.json`: sekvens, källreferenser, klipp, policy och publiceringsinställningar.
- `audio_project.schema.json`: sparad projektversion samt `$defs/RenderSnapshot`.
- `audio_profile_v2.schema.json`: oföränderlig profilversion samt `$defs/SessionLength` för nya pass.
- `fixtures/audio_editor.json`: gemensamma positiva/negativa exempel, inklusive semantiska fel som JSON Schema inte ensamt uttrycker.

## Projekt, sekvens och beständighet

Ett projekt har serververifierat kontoägarskap, stabilt UUID, positiv monoton `revision`, namn, recept och profilinställningar. `created_at` bevaras; servern tilldelar `updated_at`. Klienter skickar inte auktoritativ ägare, tidsstämplar eller ny revision. Projektformatet beskriver sparat svar, inte en mass-assignerbar databasrad. Import och redigering kräver inte rendering för att sparas.

`sources` innehåller stabila käll-ID:n med kanoniskt `asset_id`, exakt frameantal och SHA-256. En importerad källa har `kind: asset`. `profile_background` kräver dessutom ursprungligt `profile_version_id`: den färdiga profilbakgrunden blir en beständig källa utan inbakad binaural action. Gamla mixrecept omtolkas inte till en tidslinje. Obearbetade biblioteksfiler och tillfälliga browser-Blob-URL:er är inte beständiga referenser.

Källor i sparade projekt, renderögonblicksbilder och publicerade profiler hålls kvar med transaktionella referenser. Även en tillagd men ännu inte placerad projektkälla ska finnas kvar. Att ta bort ett klipp frigör inte ljud som fortfarande refereras någon annanstans. Filer får inte städas mellan kontroll och referensskapande; pågående jobb håller egna referenser/leases. Inga nya automatiska raderingar av refererat användarljud införs. Radering av sessions-/EEG-data följer fortsatt befintlig tombstone-/deletion-epoch-hantering.

Normativa semantiska regler, utöver JSON Schema:

| Regel | Krav |
| --- | --- |
| S1 | Käll-ID:n och klipp-ID:n är unika inom receptet. Varje klipp hittar en källa och uppfyller `0 <= start < end <= source.frame_count`. Servern kontrollerar verkligt ägarskap, ready-status, oföränderligt ljud/checksumma och eventuell profilproveniens; klientmetadata räcker inte. |
| S2 | `frame_count = sum(end-start) - sum(transition_after.frames för alla utom sista klippet)`. Resultatet ligger inom tabellens gräns. Klippens ordning bestämmer hela tidslinjen, utan separata positioner, luckor eller fria parallella spår. |
| S3 | Sista klippet har cut. För varje klipp är inkommande + utgående överlapp högst klipplängden. Därmed ryms övergången i båda grannarna och tre klipp spelar aldrig samtidigt. |
| S4 | Profilens ägare och frameantal matchar renderögonblicksbilden; profilinställningarna är exakt samma som i bilden. Profilens bakgrund kommer från den färdiga mastern med matchande checksumma. Publicering läser inte dagens redigerbara projekt. |
| S5 | Ton- och bakgrundsgain har summa högst 0,95; jämför utan binära avrundningsfel vid gränsen. |
| S6 | Sessionens mål, val, policy och faktisk spelad tid stämmer enligt sessionsreglerna nedan. Mål/policy får inte bytas under ett pass. |

För en linjär crossfade med N frames är höger vikt `i/(N-1)` och vänster `1-höger`, där `i = 0..N-1`. Vid N=1 används 0,5/0,5. Klippgain appliceras före blandning. Samma formel, intervall, statiska nivåfaktor och frameantal används för slutrendering och lyssning på dess skarvar. Ångra/gör om skapar redigeringar av projektet; det ändrar inte publicerade bilder eller profilversioner.

## Revisioner, återförsök och oföränderliga resultat

Projekt-, render-, export- och publiceringsanrop med POST/PUT har `request_id`, ett klientgenererat UUID som behålls vid nätverksretry. Servern gör ett atomiskt anspråk med unik nyckel `(owner, operation, request_id)` och binder nyckeln till resurs och hela det validerade anropet. Samma nyckel och samma payload återger det ursprungliga resultatet; annan payload eller resurs ger 409 `REQUEST_ID_REUSE`. Samtidigt identiskt anrop under arbete ger 409 `REQUEST_IN_PROGRESS`, inte ett nytt jobb. Kvittot och resultatet skrivs atomiskt; de bevaras så länge resursen finns, och en eventuell framtida radering lämnar tombstone så att gamla retries inte återskapar den.

V2-sessionsuppladdning använder i stället inspelningens beständiga `session_id` och oföränderliga innehåll: samma rådatachecksumma, manifest, beslut och frames ger samma kvittens, medan ändrat innehåll för samma ID ger 409. Feedback använder `(owner, session_id, revision)`: identiskt betyg på samma revision är retry, ändrat betyg på samma eller lägre revision ger 409. Där behövs inget extra request-ID. Tidigare v1-endpoints behåller sina befintliga retryregler.

Skapa projekt med `{request_id, project_id, name, recipe, settings}`: revision 1. Spara med `{request_id, expected_revision, name, recipe, settings}`: compare-and-set och nästa revision. Föråldrad revision ger 409 `REVISION_CONFLICT` utan skrivning. Återförsök slås upp **före** revisionskontrollen, så att en redan lyckad sparning kan kvitteras efter ett tappat svar. En kvittens för revision 2 får inte markera nya lokala redigeringar som sparade eller skriva över revision 3 i klienten. Kontobyte och generationskontroll ska skydda även fördröjda svar.

En renderbegäran anger `{request_id, expected_revision}`. Servern kontrollerar revisionen och fryser hela receptet, källornas oföränderliga referenser och publiceringsinställningarna i `RenderSnapshot` i samma transaktion. Tomt projekt ger 422. Ändringar efteråt påverkar varken jobbet, exporten eller en publicerad profil. Uppdaterade gain-/längdinställningar kräver ny projektrevision och ny bild även om ljudklippen är samma.

Jobbets muterbara hölje är `{id, snapshot, status, progress, result, error}`. `status` är `pending|running|ready|failed`; progress är 0–1 och når 1 endast vid ready. `result` är null tills verifierad master finns, därefter `{background_asset_id, frame_count, checksum_sha256, normalization_factor}`. `error` är null eller `{code, message}` utan interna filvägar. Workeråterförsök använder samma bild och lease; halvskrivna filer publiceras aldrig som ready. Klienten visar vilket projekt/revision ett resultat gäller, även efter en senare redigering.

Mastern innehåller klippens bakgrund, inte tilldelade binaurala toner eller appens slututtoning. Fast nivåpolicy: beräkna en enda faktor `min(1, 0.95 / peak)` för hela sekvensens float-mix (vid tystnad 1), efter klippgain och övergångar; applicera före deterministisk PCM16-kvantisering utan dither. Kvantisering är `clamp(round_half_away_from_zero(x * 32768), -32768, 32767)`, med exakt noll för tystnad. Publicerad `normalization_factor` beskriver redan applicerad faktor och får inte multipliceras igen i appen. Lyssningsfönster läses ur samma master. Källprov före färdig master ska tydligt beskrivas som källprov och får inte utge sig för att vara normaliserad slutmix.

## API-gränser och gamla klienter

Nya rutter nedan är kontrakt för B–E. Befintlig bearer-autentisering, konto-isolering, privata filvägar och återanvänd tokenförnyelse gäller. Inga publika ljudfiler eller beständiga tokens i URL. Saknad auth ger 401, främmande/saknad resurs 404, för stor import 413 och ogiltiga data 422.

| Rutt | Anrop/svar |
| --- | --- |
| `POST /v1/audio/projects` | Skapa enligt ovan, 201 med sparat projekt. Identisk retry återger samma projekt. |
| `GET /v1/audio/projects?cursor=&limit=20` | `{items: [project], next_cursor: string|null}`, limit 1–100; ogenomskinlig kontobunden cursor. |
| `GET /v1/audio/projects/{id}` | Sparat projekt med aktuell revision. |
| `PUT /v1/audio/projects/{id}` | Sparbegäran enligt ovan; 200 med ny sparad revision. |
| `POST /v1/audio/projects/{id}/renders` | Revisionsbunden begäran; 202 med jobbhölje och fryst bild. |
| `GET /v1/audio/project-renders/{id}` | Jobbhöljet ovan; blandas inte med gamla `/v1/audio/renders` för samtidiga mixar. |
| `GET /v1/audio/assets/{id}/window?start_frame=&frames=` | Färdig kanonisk källa, högst 240 000 frames i komplett liten WAV. |
| `GET /v1/audio/project-renders/{id}/window?start_frame=&frames=` | Ready-master, samma begränsning; 409 `RENDER_NOT_READY` före ready. |
| `GET /v1/audio/assets/{id}/peaks?frames_per_bucket=&start_bucket=&count=` | `{asset_id, frame_count, frames_per_bucket, start_bucket, peaks: [[min,max],...]}`; min/max över båda kanalerna, normaliserat till [-1,1]. Högst 3 600 par/svar; sista partiella bucket ingår. |
| `POST /v1/audio/project-renders/{id}/exports` | `{request_id, format: "wav"|"mp3"}`; endast ready-master. 202 `{id, render_id, snapshot_id, format, status, error}`. |
| `GET /v1/audio/project-exports/{id}` | Samma exporthölje, med `frame_count` (masterns), `checksum_sha256` och `bytes` när ready. |
| `GET /v1/audio/project-exports/{id}/download` | Privat nedladdning; 409 före ready. WAV använder samma masterbytes. |
| `POST /v2/audio/profiles` | `{request_id, render_id, name}`; 201 med profil v2 från den färdiga bilden. |
| `POST /v2/audio/profiles/{profile_id}/versions` | Samma begäran; ny oföränderlig version av ägd profil, inte uppdatering på plats. |
| `GET /v2/audio/profiles?cursor=&limit=20` | Paginerat `{items: [profile_v2], next_cursor}`, alla versioner, endast schema 2. |
| `GET /v2/audio/profiles/versions/{id}` | Ägd oföränderlig profil v2. |
| `GET /v2/audio/profiles/versions/{id}/download` | Hela verifierbara WAV-bakgrunden; befintligt strömmande nedladdnings-/checksummeflöde. |
| `GET /v2/audio/profiles/versions/{id}/window?start_frame=&frames=` | Privat begränsad lyssning, samma maxlängd som övriga fönster. |
| `POST /v2/sessions` | Befintligt uppladdningshölje `{manifest, raw_base64, checksum_sha256, decisions, frames}`, men separat meditation-2-validator. |
| `GET /v2/sessions` och `GET /v2/sessions/{id}` | Samma sammanfattnings-/inspelningsfält som tidigare, men endast meditation-2; listan pagineras med items/next_cursor. |
| `POST /v2/meditation/sessions/{id}/feedback` | Samma betygsfält/ägarskap/revisioner som tidigare; endast slutfört nytt pass med dess exakta låsta mål. Ingen gammal träning följer. |
| `GET /v2/meditation/sessions/{id}/feedback` | Det nya passets senast sparade betyg med revision; samma ägar-/versionsgräns som POST. |

Fönster är helt inom källan/mastern, med `frames >= 1`; ogiltig/tom/för stor begäran ger 422 och kapas inte tyst. Utdata är `audio/wav`, `Cache-Control: private, no-store`, högst 960 044 byte för enkel 44-byte-header och fem sekunder PCM. Servern tillhandahåller snapshot-ID och exakt intervall via `X-Neurotune-Snapshot-Id`, `X-Neurotune-Start-Frame`, `X-Neurotune-Frame-Count` för renderfönster. Kontobyte eller ny sökning avbryter hämtning och hindrar sena resultat från att starta ljud.

Peakparametrar är heltal: `frames_per_bucket >= 1`, `start_bucket >= 0`, `count` 1–3 600, och begärt intervall ska rymmas i `ceil(frame_count / frames_per_bucket)`. Översikt använder 48 000 frames/bucket. Min avrundas utåt nedåt och max utåt uppåt till fyra decimaler, klippt till [-1,1], så att även 3 600 par ryms under bytegränsen. Detta ändrar inte samples i lyssningsljudet. Främmande asset-ID ger 404 även för peaks.

Nya kontraktsrutters fel har `{"detail":{"code":"REVISION_CONFLICT","message":"...","project_id":"...","expected_revision":1,"current_revision":2}}`; kod/message är alltid obligatoriska, resurs-/revisionsfält används där de är relevanta, och 422 kan ange `rule: "S3"` samt fältpekare. Återförsök får inte växla till ett nytt request-ID för att kringgå konflikt. Äldre endpoints behåller sina nuvarande felhöljen.

**Separat versionsväg är vald**, inte opt-in via en ändrad schema-1-array. Gamla `/v1/audio/profiles` fortsätter returnera sin nuvarande lista av **alla** ägda schema-1-versioner. Den filtrerar bort nya versioner före schema-1-parsning, inklusive när samma profil-ID har nyare schema-2-versioner. Gamla metadata/checksummor och listans arrayform ändras inte. Gamla versions-/filrutter ger 404 för schema-2-ID:n. Uppgraderad app läser båda versionsvägarna, förenar versionerna med deras oföränderliga ID:n och skiljer deras offlinecache/validatorer.

Additivt `GET /v1/audio/capabilities` svarar `{schema_version: 1, profile_schemas: [1,2], project_schemas: [1], session_protocols: ["meditation-1","meditation-2"], export_formats: ["wav","mp3"]}` när respektive del verkligen stöds; listorna annonserar endast implementerat stöd. Äldre server som ger 404 innebär endast tidigare kontrakt. V2-uppgifter som redan sparats lokalt behålls vid servernedgradering och visas som väntande/kräver stöd, aldrig omkodade till schema 1 eller uppladdade som meditation-1. E1:s läsare behövs före E2:s publicering. Att en profil kan listas eller laddas ned betyder inte att sessionsstödet finns: appen erbjuder inte ett nytt pass innan E4/E5/E6 och annonserat meditation-2-stöd finns; profilen kan under tiden visas med att uppspelningsstöd krävs.

## Sessionslängd, avslut och EEG

Nya profil-v2-pass använder manifest `mode: meditation`, `experiment_version: meditation-2` och meditation-metadata `schema_version: 2`, `protocol_version: meditation-2`, `mode: fixed`, ägd profilkopia/versions-ID, vald action, källa och ögonstatus. Metadatafältet `length` följer `$defs/SessionLength`. `fixed` här avser icke-adaptiv action, inte profilens längdpolicy. Binaural action lagras endast i sessionen och syntetiseras i appen.

Vid start fryses `length.profile_version_id`, `playback_policy`, `source_frame_count`, `selection`, `target_frames` och `end_fade_frames`. De måste matcha den ägda oföränderliga profilen. Policy `fixed` tillåter bara `{kind: full_file}`. `selectable` tillåter samma förval eller `{kind: minutes, minutes: 1..60}`. Full-file-mål är exakt källans frameantal; minutmål är `minutes * 2 880 000`. Kortare mål stoppar mitt i filen; längre mål loopar bakgrunden. `played_frames` är monotont, 0–target, och manifestets `duration_seconds = played_frames / 48000` utan heltalsavrundning. Gränsen i detta nya schema är aldrig en utvidgning av gamla meditation-1.

End-fade består av L=`min(240000,target_frames)` frames. För frame f i avslutets intervall `[target-L,target)` är gain `(target-1-f)/(L-1)`; före intervallet är gain 1. Vid L=1 är sista framen noll. Gain appliceras på hela mixen efter bakgrund/toner och återställs inte vid loopskarv. Schemalagd fade ryms inom måltiden. Manuellt stopp börjar från aktuell hörbar nivå, tonar ut båda signalerna, behåller stopped och får inte rapportera completed. Paus, avbrott, köade frames eller startpadding lägger inte till aktiv speltid. Efter sista skrivningen krävs bekräftelse att sista målsatta bufferten spelats innan tjänster stängs.

Bakgrundens loopövergång är separat: den befintliga 500 ms överlappningen kan förbruka öppningsframes och ändra källcursorperioden. Den får inte förkorta eller förlänga sessionsmålet. Spara/mappa absolut spelad sessionstid och källcursor separat; A2:s enkla modulo-cursor är endast ett riskprov.

Gamla profil-, kalibrerings-, feedback- och sessionskontrakt behåller schema/protokoll 1 och exakt 600 aktiva sekunder för kvalificerad feedback/EEG-träning. Sparade blindade tiopassplaner förändras aldrig. V2-profiler tas inte med i det äldre kalibreringsflödet i denna leverans: visa ett begripligt val av kompatibel äldre profil, utan att kringgå fixed-policy eller tyst ändra serie. Nya vanliga pass använder inte gamla adaptiva modeller/dataset; även ett nytt pass på precis 600 s är meditation-2 och utesluts från gamla träningsjobb, NIR-worker och rekommendationsevidens. Explicit användarval av action är fortsatt tillåtet. Feedback för nya pass ger inget implicit samtycke till nytt träningsprotokoll.

E5 måste versionsseparera även offlineköer, feedbackretry, listning/läsning av feedback, sessionssammanfattning och radering. Meditationsmarkörer, ägare, rådatachecksumma och befintliga deletion/tombstone-regler följer med; en extra v2-väg får inte skapa ett parallellt raderingsregister eller låta ett tidigare raderat pass återuppstå.

V1:s sessionslista fortsätter visa dess tidigare NIR-/meditation-1-data och filtrerar bort meditation-2; v1-läsning/feedback för ett nytt sessions-ID ger 404. Uppgraderad app förenar versionsvägarna. Befintlig `POST /v1/sessions/delete` och meditations-deletion-ledger hanterar samma ägda session-ID oavsett version, med oförändrad återbyggnad av kompatibel kvarvarande evidens. Ingen ny v2-träningsrutt annonseras.

## WAV, MP3 och återimport

WAV-exporten är den exakta mastern. MP3 kodas från samma master med libmp3lame, 320 000 bit/s, stereo 48 kHz och `write_xing=1` till en **sökbar fil**, så att Xing/LAME-information om kodarfördröjning/längd finns. ID3-fält `neurotune_frame_count` anger masterns frameantal som decimalsträng. Exportmetadata/API anger alltid avsedd masterlängd, inte en spelares avrundade MP3-duration.

Låst MP3-tolerans: efter gapless-medveten avkodning får absolut skillnad mot mastern vara högst **1 152 frames (24 ms)**. Det är en separat formatkontroll, inte en tolerans för klippgränser, WAV-verifiering, sessionsmål eller entimmesgränsen i kanoniska data. Mer avvikelse är ett misslyckat exportjobb, inte ett tyst godkänt kortare/längre resultat. MP3 är förlustkomprimerat; samplevärden och filchecksummor förväntas skilja sig från WAV.

Återimport: WAV används exakt. För MP3 respekteras först normal delay-/paddingmetadata. Egen export med `neurotune_frame_count` kan sedan trimmas/paddas i slutet till N **endast** om N är ett giltigt heltal 1–172 800 000 och avvikelsen i avkodat antal är högst 1 152. Taggen är obetrodd och får inte kringgå storleks-, ägar-, codec- eller avvikelsekontroller; falsk/stor avvikelse ger 422, inte godtycklig kapning. MP3 utan denna tagg använder sitt faktiskt kanoniserade antal efter vanlig gapless-hantering och avvisas om det överskrider en timme. Därefter gäller samma exakta frame-/klippgränser för båda formaten. På så sätt kan även en export strax under entimmesgränsen återimporteras utan att codec-padding blir en falsk ny ljudlängd.

FFmpeg/ffprobe n9.0.1 på A1/A2:s Linux-referensmaskin, 2026-10-16, gav dessa verkliga resultat utan vår egna längdtagg:

| Masterframes | Avkodade MP3-frames | Skillnad |
| --- | --- | --- |
| 1 | 47 | +46 |
| 1 440 001 | 1 440 047 | +46 |
| 57 600 001 | 57 600 047 | +46 |
| 172 800 000 | 172 800 000 | 0 |

Mätvärdena finns i fixtures. De visar längd/padding för denna kodare, inte fysisk spelarkvalitet eller acceptans för ännu oimplementerad export/återimport. D4 måste verifiera taggen, änd-till-änd-återimport, kanal-/tidsalignering, flera ljudinnehåll och vald codec-version; F1/F3 tillför verklig lyssning.

Ett ytterligare isolerat filprov med längdtagg och kontrollerad `apad=whole_len=N,atrim=end_sample=N` återställde exakt 1, 1 440 001 och 172 799 999 frames. De två första krävde borttagning av 46 extra frames; det sista hade redan rätt längd. Detta verifierar den föreslagna längdregelns mekanik, inklusive strax under en timme, utan att påstå att B4/D4:s API redan finns.

## Låsta resurskontroller och återstående acceptans

Referensmiljön är AMD Ryzen 7 5800X, Linux 7.2.5-3-omarchy. A1 använder Chromium 156/Playwright 1.64, Node 22.23.3; A2 använder Dart 3.13.5 AOT. Se [ADR-0001](../docs/adr/0001-bounded-audio-windows.md) och [ADR-0002](../docs/adr/0002-audio-editor-duration.md) för exakta versioner, kommandon och begränsningar.

| Kontroll på referensmiljön | Acceptansgräns från A1/A2 |
| --- | --- |
| Webb, 20 sena sökningar i entimmeskälla, 5 s/fönster | Klick→`source.start` < 2 000 ms per sökning, inte fysisk hörlurslatens |
| Webb efter samma sökningar, ingen tvingad GC | JS-heapökning < 32 MiB och summerad renderer-RSS-ökning < 128 MiB |
| Peaköversikt för en timme | Högst 3 600 par och < 100 000 byte; zoom hämtar separat begränsat fönster |
| Appens isolerade AOT-filprov, en hel timme | PCM-paket högst 9 600 frames / 38 400 byte; både observerad RSS- och Linux VmHWM-tillväxt högst 128 MiB |

Detta låser provvillkoren, inte ett påstående att alla webbläsare/telefoner redan klarar hela editorn. A1 mätte 37 ms, heap 2,60→4,59 MiB och RSS 123,79→219,68 MiB. A2 mätte 915 ms accelererad läsning och 4,46 MiB observerad RSS-tillväxt; ingen uppspelningsdeadline följer av den accelererade siffran. Befintliga trösklar sänks inte. Import, render, export, temporära filer/lagringsbudget, långvarig EEG-insamling och fysiskt Android-avslut kräver senare verkliga B4/D4/E5/F2/F3-prov; korta fönster eller simulerad klocka ersätter dem inte.

## Kontraktsverifiering och senare paritet

Fixtures består av gemensamma `roots` och fall med JSON-pointer-ersättningar i `set`. Applicera dem på en djup kopia. `repeat_clips` appliceras därefter och klonar första klippet med UUID:n `000003e8-1111-4111-8111-111111111111`, `000003e9-...` osv. `schema_valid` och `semantic_error` är separata förväntningar. Produktionsvalidatorn måste köra både strukturell och semantisk validering, men referenskontrollen nedan bevisar inte databasägarskap, transaktioner eller installerat API-beteende.

Det nya underlaget håller sig till ärendets fem kontraktsfiler. Inga backend-/Dart-validatorer eller paketeringsberoenden ändras här. B1/B2 inför S1–S5 tillsammans med transaktionella referenser, revisionskonflikter och retryparitet. D1/D3 verifierar PCM/samma övergångsformel och nivåfaktor. E1/E4/E5 inför schema-1/v2-paritet och S6 inklusive samma nya tiominuterspass som avvisas av gamla gates. Alla berörda validatorer ska återanvända fixtures och lägga till ägda/främmande resurser, blandad profil-lista med riktig schema-1-klient, offline/servernedgradering och dubbla/fördröjda anrop. Saknade runtimevalidatorer får inte beskrivas som färdig API-acceptans.

### JSON- och schemakontroll

Kör från repo-roten; verifieringspaketen installeras endast i en tillfällig miljö, inte i appens beroenden:

```bash
python -m venv /tmp/neurotune-contract-check
/tmp/neurotune-contract-check/bin/python -m pip install 'jsonschema[format-nongpl]==4.26.0'
```

```python
# contract-fixtures: kör med miljön ovan, från repo-roten.
import copy
import json
from decimal import Decimal
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

def reject_constant(value):
    raise ValueError('Non-JSON numeric constant: ' + value)


def load_json(path):
    return json.loads(Path(path).read_text(), parse_constant=reject_constant)


paths = {
    'sequence': 'audio_sequence_recipe.schema.json',
    'project': 'audio_project.schema.json',
    'profile': 'audio_profile_v2.schema.json',
}
schemas = {key: load_json(Path('contracts') / name)
           for key, name in paths.items()}
assert {'date-time', 'uuid'} <= FormatChecker.checkers.keys()
registry = Registry().with_resources([
    (schema['$id'], Resource.from_contents(schema)) for schema in schemas.values()
])
for schema in schemas.values():
    Draft202012Validator.check_schema(schema)
validators = {
    key: Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
    for key, schema in schemas.items()
}
for key, root, definition in [('snapshot', 'project', 'RenderSnapshot'),
                              ('session_length', 'profile', 'SessionLength')]:
    validators[key] = Draft202012Validator(
        {'$ref': schemas[root]['$id'] + '#/$defs/' + definition},
        registry=registry, format_checker=FormatChecker())


def semantic_error(kind, value):
    if kind == 'session_length':
        policy, choice = value['playback_policy'], value['selection']
        target = (value['source_frame_count'] if choice['kind'] == 'full_file'
                  else choice['minutes'] * 2880000)
        if (policy['mode'] == 'fixed' and choice['kind'] != 'full_file'
                or value['target_frames'] != target
                or value['played_frames'] > target
                or value['end_fade_frames'] != min(240000, target)):
            return 'S6'
        return None
    if kind == 'sequence':
        recipe = value
    elif kind == 'profile':
        recipe = value['render_snapshot']['recipe']
    else:
        recipe = value['recipe']
    sources, clips = recipe['sources'], recipe['clips']
    source_ids = [source['id'] for source in sources]
    clip_ids = [clip['id'] for clip in clips]
    lookup = {source['id']: source for source in sources}
    if len(source_ids) != len(set(source_ids)) or len(clip_ids) != len(set(clip_ids)):
        return 'S1'
    for clip in clips:
        if (clip['source_id'] not in lookup
                or not 0 <= clip['start_frame'] < clip['end_frame']
                <= lookup[clip['source_id']]['frame_count']):
            return 'S1'
    if clips and clips[-1]['transition_after']['kind'] != 'cut':
        return 'S3'
    for index, clip in enumerate(clips):
        incoming = clips[index - 1]['transition_after']['frames'] if index else 0
        if incoming + clip['transition_after']['frames'] > clip['end_frame'] - clip['start_frame']:
            return 'S3'
    total = (sum(clip['end_frame'] - clip['start_frame'] for clip in clips)
             - sum(clip['transition_after']['frames'] for clip in clips[:-1]))
    if recipe['frame_count'] != total:
        return 'S2'
    if kind == 'profile':
        snapshot = value['render_snapshot']
        if (value['frame_count'] != recipe['frame_count']
                or value['owner_account_id'] != snapshot['owner_account_id']
                or value['settings'] != snapshot['settings']):
            return 'S4'
    if kind != 'sequence':
        settings = value['settings']
        if (Decimal(str(settings['tone_gain'])) + Decimal(str(settings['background_gain']))
                > Decimal('0.95')):
            return 'S5'
    return None


fixture = load_json('contracts/fixtures/audio_editor.json')
for case in fixture['cases']:
    value = copy.deepcopy(fixture['roots'][case['root']])
    for pointer, replacement in case['set'].items():
        keys, parent = pointer.lstrip('/').split('/'), value
        for key in keys[:-1]:
            parent = parent[int(key)] if isinstance(parent, list) else parent[key]
        key = int(keys[-1]) if isinstance(parent, list) else keys[-1]
        parent[key] = copy.deepcopy(replacement)
    if 'repeat_clips' in case:
        first, value['clips'] = value['clips'][0], []
        for index in range(case['repeat_clips']):
            clip = copy.deepcopy(first)
            clip['id'] = f'{1000 + index:08x}-1111-4111-8111-111111111111'
            value['clips'].append(clip)
    errors = list(validators[case['root']].iter_errors(value))
    assert (not errors) == case['schema_valid'], (case['name'], [e.message for e in errors][:2])
    if not errors:
        assert semantic_error(case['root'], value) == case['semantic_error'], case['name']
probe = fixture['mp3_probe']
assert probe['maximum_decoded_error_frames'] == 1152
for row in probe['observations']:
    assert abs(row['decoded_frames'] - row['master_frames']) <= 1152
for row in probe['tagged_roundtrip_observations']:
    assert int(row['tag']) == row['master_frames'] == row['restored_frames']
print(f"3 schemas and {len(fixture['cases'])} fixtures passed (structural + reference semantic rules)")
```

### Reproducera MP3-mätningen

```python
# mp3-duration-probe: kör med Python och installerad ffmpeg/ffprobe.
import json, subprocess, tempfile, wave
from pathlib import Path

def command(args):
    subprocess.run(['ffmpeg','-v','error','-nostdin','-y',*args], check=True)

rows=[]
with tempfile.TemporaryDirectory(prefix='neurotune-mp3-contract-') as folder:
    wav,mp3=Path(folder)/'master.wav',Path(folder)/'export.mp3'
    for frames in (1,1440001,57600001,172800000):
        command(['-f','lavfi','-i','sine=frequency=440:sample_rate=48000',
            '-af',f'atrim=end_sample={frames}','-ac','2','-c:a','pcm_s16le',str(wav)])
        with wave.open(str(wav)) as source:
            assert source.getnframes()==frames
        command(['-i',str(wav),'-map','0:a:0','-c:a','libmp3lame','-b:a','320k',
            '-ar','48000','-ac','2','-write_xing','1',str(mp3)])
        info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(mp3)]))['streams'][0]
        decoder=subprocess.Popen(['ffmpeg','-v','error','-nostdin','-i',str(mp3),'-f','s16le','-acodec','pcm_s16le','-'],stdout=subprocess.PIPE)
        size=0
        while chunk:=decoder.stdout.read(65536):
            size+=len(chunk)
        assert decoder.wait()==0 and size%4==0
        decoded=size//4
        row=dict(master_frames=frames,decoded_frames=decoded,decoded_error_frames=decoded-frames,
            container_frames=round(float(info['duration'])*48000),bit_rate=info['bit_rate'])
        row['container_error_frames']=row['container_frames']-frames
        rows.append(row)
        print(json.dumps(row),flush=True)
```

## Genomförd verifiering i A3

- Tre nya scheman har kontrollerad JSON-syntax och giltig Draft 2020-12-metaschema. Alla 56 fixtures passerar sina separata strukturella/semantiska förväntningar, inklusive UUID/datumformat, en frame över en timme, 100/101 klipp och gain precis på/över 0,95.
- Referenskontrollen kördes direkt ur Python-blocket i detta dokument. Tillfälliga `jsonschema[format-nongpl]` 4.26.0 behövs för formatassertioner; utan datumtillägget fångade negativ datumfixture en saknad formatkontroll. Inga appberoenden har ändrats.
- Mutationsprov: när schemats `maxItems` ändrades från 100 till 101 misslyckades fixture `hundred-and-one-clips`. Originalet återställdes och alla exempel passerar igen.
- Befintlig backendsvit: `cd backend && .venv/bin/python -m pytest -q`, 65 tester passerar. De 16 befintliga Alembic-varningarna om `path_separator` kvarstår. Gamla kontraktsfiler och produktionskod är oförändrade.
- FFmpeg-proven ovan kodade och avkodade verkliga filer; resultat och begränsningar redovisas separat från A1/A2:s tidigare resursmätningar. Äldre browser-/Android-prov har inte räknats som nya tester av dessa kontrakt.

## Källor

Besluten för begränsade ljudfönster, auth och appens exakta klocka bygger på A1/A2 och deras källor ovan. Aktuell dokumentation hämtades via Context7 före schema-/formatarbetet:

- [JSON Schema: schema-ID och referenser](https://json-schema.org/understanding-json-schema/structuring), [oneOf](https://json-schema.org/understanding-json-schema/reference/combining), [additionalProperties](https://json-schema.org/understanding-json-schema/reference/object).
- [python-jsonschema: validering](https://python-jsonschema.readthedocs.io/en/stable/validate/) och [lokalt referensregister](https://python-jsonschema.readthedocs.io/en/stable/referencing/).
- [FFmpeg: MP3-muxer och Xing/LAME](https://ffmpeg.org/ffmpeg-formats.html#mp3) och [atrim med samplegräns](https://ffmpeg.org/ffmpeg-filters.html#atrim).
