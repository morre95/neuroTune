# ADR-0001: Autentiserade ljudfönster för lång provlyssning i webben

## Status

Beslutad väg för nästa implementationssteg efter riskprovet [#21](https://github.com/morre95/neuroTune/issues/21), inom [specifikation #20](https://github.com/morre95/neuroTune/issues/20). Provet är isolerat; den vanliga editorn har ännu inte bytt ljudleverans.

## Kontext

Den nuvarande editorn hämtar hela källan som Blob före uppspelning. Den nya editorn ska kunna välja och provlyssna på avsnitt ur entimmesfiler. En timme stereo PCM16 vid 48 kHz innehåller 691 200 000 byte ljuddata. En full float32-avkodning av båda kanalerna motsvarar 1 382 400 000 byte enbart för samples.

Vi behöver en väg som behåller befintlig bearer-autentisering och kontoägarskap, kan söka förbi minut tio och inte kräver helfilsavkodning i webbläsaren. Ett mediaelement med vanlig URL är inte ett bevis för att den befintliga fetch-klientens Authorization-header följer med.

## Beslut

Använd korta, kompletta WAV-fönster hämtade med autentiserad fetch för klipp-/skarvprovlyssning. Provet begränsar varje fönster till fem sekunder, alltså 240 000 stereo-frames vid 48 kHz. Servern läser endast det begärda PCM-intervallet och ger det en egen giltig WAV-container.

Web Audio avkodar det kompletta lilla fönstret. AudioContext startas/resumeras från användarens knapptryckning. En pump håller högst ett hämtning-/dekodningsjobb aktivt och en senaste önskad sökposition. En ny sökning eller utloggning avbryter hämtningen; generationskontroll före och efter avkodning hindrar gammalt ljud från att starta. Gamla ljudkällor stoppas och kopplas loss.

Dekodningens indata kan vara detached efter anropet. Bytesräknaren sparas därför före decodeAudioData, inte genom att läsa ArrayBuffer.byteLength i efterhand. Den visuella kontrollen fångade felet och en ny browserassertion reproducerade det innan rättningen.

Behåll bearer-token i minnet, private/no-store-svar och samma ägarvalidering som befintliga ljudkällor. Inga publika ljudfiler, tokens i URL eller ny autentiseringsmodell införs. Konto-/generationsbyte stänger även ljudkontext och nollställer ljudvågsbilden.

Välj förberäknade, kompakta peakdata för ljudvågsöversikten, med mer upplösning för zoom i C1. Riskprovet använder korrekta förberäknade ensekundspeakar för sin deterministiska fixture; det är inte en produktionsimplementation av extraktion från godtyckliga inspelningar.

### Alternativ

- **Hela Blob-filen och hel avkodning:** behålls inte som enda väg för långa källor; medför stora överföringar och samplebuffertar.
- **Privat strömning/range till mediaelement:** möjligt separat spår, men autentiserings-/codec-/sökningsbeteendet behöver egen verifiering. Det är inte vad detta prov bevisar.
- **Kompletta begränsade WAV-fönster:** valt för den första skarv-/klipplyssningen eftersom samma bearer-flöde och exakt källintervall kan verifieras utan nya beroenden.

## Reproducerbart prov

Kör från repo-roten med installerade backend- och webbutvecklingsberoenden samt Playwright Chromium:

```bash
cd web
./node_modules/.bin/playwright test -c playwright.audio-probe.config.ts
```

Manuell inspektion kan startas med `backend/.venv/bin/python scripts/probe-editor-audio.py`, följt av `http://127.0.0.1:18021/probe/`. Registrera ett tillfälligt konto via den isolerade serverns befintliga `/docs` och auth/register. Använd inte ett riktigt konto från en annan backendinstans.

Startaren väljer backendens virtualenv, eller en uttrycklig `NEUROTUNE_BACKEND_PYTHON`. Den skapar en separat temporär databas, kör befintliga migrationer och genererar en riktig entimmes-WAV i små block. Konton använder verkliga auth-rutter; fixture-filerna har verkliga ägda AudioAsset-poster och kontrollerade sökvägar.

Fixturen har sex skilda frekvensband om tio minuter. Testet verifierar faktiska samples efter minut tio. Flera kontons fixtureposter använder hardlinks till samma tillfälliga fil; data dupliceras inte per konto.

Servern binder endast 127.0.0.1:18021. JWT-nyckel, databas och filer är tillfälliga. Inga befintliga konton eller användarfiler används. Ingen worker behövs för att lyssna på den redan kanoniska fixturen.

**Importören kringgås uttryckligen för detta riskprov.** Den nuvarande importörens tiominuters-/100 MiB-gränser har inte höjts här; deras implementation och acceptans hör till B4 / #27.

Rapport och skärmbild skrivs till `web/playwright-report/audio-probe/<testnamn>/metrics.json` respektive `probe.png`. Katalogen är ignorerad av git och separat från standardsvitens testresultat. Trace är avstängd för att inte lagra autentiseringsmaterial.

Playwright använder SIGTERM med fem sekunders väntan, så att Python-startaren kan ta bort den stora fixturen vid avslut. Avslut/städning verifierades separat utan kvarlämnad ny fixturekatalog. Det krävs ungefär 660 MiB ledigt filutrymme; referensmiljöns /tmp är tmpfs, vilket även belastar värdmaskinens minne utanför browser-RSS.

## Referensmiljö och mätning

Verifierat 2026-10-16, lokal Linux utan nätverksfördröjning eller artificiell CPU-begränsning:

- AMD Ryzen 7 5800X 8-Core Processor, Linux 7.2.5-3-omarchy.
- Node v22.23.3, installerad Playwright 1.64.0 och headless Chromium 156.0.8078.4.
- Python 3.14.7, FastAPI 0.142.2, Uvicorn 0.54.0, SQLAlchemy 2.1.3.
- Fristående Chromiumprofil och tillfälliga konton. Ingen anslutning till användarens vardagsbrowser.

| Mått | Uppmätt | Beslutad gräns för detta prov |
| --- | --- | --- |
| Källfil | 691 200 044 byte, 3 600 sekunder | Verklig entimmesfixture |
| Ett femsekundersfönster | 960 044 byte | Högst 960 044 byte inklusive WAV-header |
| Sökningsprov | 20 genomförda fönster, bland annat 0, 720, 1 800 och 3 595 sekunder | Ingen helfilsbegäran behövs |
| Högsta klick-till-start | 37.0 ms | Under 2 000 ms |
| JS-heap, baseline → högsta observerade | 2.60 → 4.59 MiB | Tillväxt under 32 MiB |
| Summerad renderer-RSS, baseline → högsta observerade | 123.79 → 219.68 MiB | Tillväxt under 128 MiB |
| Peaköversikt | 3 600 peakpar | Under 100 000 byte |

JS-heap mäts med CDP Runtime.getHeapUsage; det täcker inte ensamt native AudioBuffer-minne. Därför mäts även Linux /proc/VmRSS för samtliga renderprocesser i den isolerade browsern, identifierade med CDP SystemInfo.getProcessInfo. RSS-summan kan dubbelräkna delat minne och är inte PSS eller hela maskinens minne. Ingen tvingad garbage collection används.

Detta är observerade toppar efter 20 sökningar, inte en generell garanti för obegränsat antal sökningar eller andra maskiner. Trösklarna låses i provets assertions; A3 ska föra dem vidare till en namngiven referensmiljö för produktionsflödet. Kontinuerlig uppspelning/prefetch och många samtidiga källor kräver senare prov. Uppspelningstiden mäts till source.start i en körande AudioContext, inte fysisk hörlurslatens.

## Verifiering och granskning

- Tre verkliga browser/API-prov passerar: privata fönster med frame-/bytegränser; sen sökning med resurs-/latensbudget; ny sökning och kontobyte under pågående hämtning.
- Främmande konto får 404 för ljud och peaks; utan token fås 401. Negativ/tom/för stor/för sen begäran ger 422. Sista enskilda framen går att hämta.
- Browserprovet har inga consolefel, varningar eller pageerrors. Skärmbilden är visuellt granskad.
- Byggnad: `npm --prefix web run build` passerar. Befintlig standardsvit: `npm --prefix web test`, 11 tester passerar. Den opt-in-specifika sviten körs separat.
- Mutationskontroll: inverterad källgräns gav förväntat testfel (200 förväntades, 422 erhölls); koden återställdes och den fulla probesviten passerar.
- Bytesräknarens regression reproducerades separat (0 i stället för 960 044) och passerar efter rättning.

En extra strikt TypeScript-kontroll av de nya config-/testfilerna passerade.
Standardsvitens tester ingår inte i projektets vanliga tsc-körning och Node-typer
är inte installerade i projektet. Kontrollen använde därför tillfälliga
`@types/node@22` utanför repot, utan ändrad package.json eller lockfil:

```bash
npm install --prefix /tmp/neurotune-audio-probe-types --ignore-scripts --no-audit --no-fund --no-save @types/node@22
cd web
./node_modules/.bin/tsc --noEmit --strict --target ES2022 --module NodeNext --moduleResolution NodeNext --typeRoots /tmp/neurotune-audio-probe-types/node_modules/@types --types node playwright.audio-probe.config.ts tests/audio-delivery-probe.spec.ts
```

Granskningen omfattar indata, ägarvalidering, avbrutna/sena svar, kontobyte, kodens ansvar, begränsad dataläsning och avsaknad av nya beroenden. Ingen produktionsroute, migration, CORS-regel eller auth-logik har ändrats.

## Konsekvenser och nästa implementation

C1 / #29 implementerar riktiga peakdata för godtyckliga ljud och zoomnivåer. D2 / #34 integrerar autentiserade fönster med projektets faktiska revisioner och den befintliga klientens refresh-/kontogenerationshantering.

Provet har ingen automatisk tokenförnyelse; en utgången token ger ny inloggning. Produktion ska återanvända befintlig refresh-logik, inte kopiera denna begränsning. Slutmixens normalisering, korsfade mellan klipp och överensstämmelse med färdig helrendering är senare D-ärenden.

Denna ändring visar genomförbar sökning och kort provlyssning ur en lång källa. Den levererar inte hela tidslinjeeditorn, kontinuerlig entimmesuppspelning, nya importgränser eller fysisk Android-acceptans.

## Officiella källor

Dokumentation hämtad via Context7 före implementation; CDP-/Playwrightreferenser även kontrollerade mot installerade typer/officiella sidor.

- [MDN: decodeAudioData kräver kompletta ljudfiler](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData).
- [MDN: Web Audio och användargester](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices).
- [MDN: avbryta fetch och läsning av svaret](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch#canceling_a_request).
- [MDN: detached ArrayBuffer har byteLength noll](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/ArrayBuffer/byteLength).
- [FastAPI: numeriska gränser för parametrar](https://fastapi.tiangolo.com/tutorial/path-params-numeric-validations/).
- [FastAPI: egna Response-objekt](https://fastapi.tiangolo.com/advanced/response-directly/).
- [Playwright: separat webServer och gracefulShutdown](https://playwright.dev/docs/test-webserver).
- [Playwright: Browser CDP session](https://playwright.dev/docs/api/class-browser#browser-new-browser-cdp-session).
- [CDP: SystemInfo.getProcessInfo](https://chromedevtools.github.io/devtools-protocol/tot/SystemInfo/#method-getProcessInfo).
- [CDP: Runtime.getHeapUsage](https://chromedevtools.github.io/devtools-protocol/tot/Runtime/#method-getHeapUsage).
