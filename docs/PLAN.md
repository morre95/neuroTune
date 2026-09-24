# neuroTune: MVP med Muse, binauralt ljud och personlig bandit

## Mål och beslut

Bygg en Flutter-app för Android som tar emot EEG från Muse S Athena, beräknar spektrala mått och låter en personlig bandit välja mellan binaurala frekvenser på **6, 8, 10 och 12 Hz**, samt en kontrollsignal. Belöningen är baslinjenormaliserad relativ theta som mäts **medan ljudet spelas**. Detta är en utforskande EEG-prototyp; måttet ska inte presenteras som ett bevis på avslappning, fokus eller behandlingseffekt.

EEG-bearbetning, ljudgenerering och beslut körs på telefonen så att en session fungerar utan nätverk. En backend i Python och FastAPI ingår från början för användarkonton, sessionsuppladdning, experimentkonfiguration, modellträning och distribution av personliga banditversioner. Utvecklingen börjar med simulator; fysisk Muse-integration använder SDK-filerna länkade nedan. Första leveransen är en privat Android-prototyp.

## Flutter-app och experiment

- Bygg vyer för inloggning, Muse-anslutning eller simulator, kontaktkvalitet, baslinje, pågående session och sessionshistorik. Visa theta-, alpha- och betaeffekt, signalkvalitet och aktuell åtgärd under sessionen.
- Definiera ett gemensamt `EegSource`-gränssnitt för simulator, inspelningsuppspelning och Muse-plugin. Databatcher ska innehålla kanalnamn, enheter, samplingsfrekvens, tidsstämplar, EEG, rörelsedata och kontaktstatus. Läs faktisk samplingsfrekvens från SDK eller enhetskonfiguration; anta inte en konstant för alla enheter.
- Implementera Muse-bryggan på Android i Kotlin. Native-koden hanterar SDK-anslutning, skickar batcher via Flutter `EventChannel` och tar emot kommandon via `MethodChannel`. Kör signalberäkningar utanför Flutter-vyn i en separat Dart-isolate.
- Generera stereoljud med mittfrekvens 220 Hz. För exempelvis 6 Hz spelas 217 Hz i vänster öra och 223 Hz i höger. Kontroll har 220 Hz i båda öronen. Använd samma amplitud och mjuka övergångar för alla åtgärder. Kräva stereohörlurar för sessionen.
- Standardprotokoll: två minuters tyst baslinje följt av 15 block med 30 sekunders ljud och 10 sekunders tyst paus. Använd de sista 20 sekunderna av varje ljudblock för belöning. Användaren håller samma ögonläge under hela sessionen.
- Stoppa ljud och beslut vid manuellt stopp, förlorad ljudutgång, app i bakgrunden eller Muse-frånkoppling. Avbrutna block ger ingen belöning. Återupptagning kräver stabil signal och startar ett nytt block.

### Signalbehandling

- Använd tillståndsbevarande bandpassfilter på 1–40 Hz och notchfilter, normalt 50 Hz med konfigurerbart 60 Hz.
- Beräkna Welch-spektrum över fyrasekundersfönster varje sekund med tvåsekunders Hann-segment och 50 procents överlapp. Integrera effekten för theta 4–8 Hz, alpha 8–13 Hz och beta 13–30 Hz. Beräkna absolut bandeffekt och relativ effekt mot 1–40 Hz utan att dubbelräkna gemensamma bandgränser.
- Underkänn fönster vid dålig kontakt, paketluckor, mättnad, flatline, stora amplitudsprång eller rörelse. Versionshantera kvalitetsgränser och verifiera dem med inspelningar från fysisk Athena innan hårdvaruläget godkänns.
- Välj EEG-kanaler med god baslinjekvalitet och behåll samma kanaler genom sessionen. Kräv minst två godkända kanaler. Kräv omkalibrering om baslinjen har för lite giltig data eller nästan ingen variation.
- Normalisera relativ theta mot baslinjens medelvärde och standardavvikelse. Blockbelöningen är medelvärdet av giltiga normaliserade theta-värden, begränsat till −3 till +3. Kräv minst 80 procent giltiga fönster under mätperioden; annars uteblir bandituppdateringen. Spara även absolut theta för att kunna tolka förändringar i kvoten.

## Bandit och backend

### Personlig inlärning

- Implementera epsilon-greedy med `epsilon = 0,20`, antal observationer och medelbelöning för var och en av de fem åtgärderna.
- Börja varje session med de fem åtgärderna i slumpad ordning. Välj därefter bästa uppskattade åtgärd med 80 procents sannolikhet och en slumpmässig åtgärd med 20 procents sannolikhet.
- Spara åtgärd, valsannolikhet, belöning, kvalitet, experimentversion och policyversion för varje block. Erbjud även ett separat jämförelseläge med balanserad slumpordning.
- Håll simulatorns sessioner och bandittillstånd åtskilda från verkliga användardata.

### Backend och gränssnitt

- Använd PostgreSQL för konton, experiment, sessionsmetadata, träningsjobb och banditversioner. Lagra komprimerad rådata i en beständig datavolym.
- Använd Argon2 för lösenord, kortlivade access-token och återkallbara refresh-token. Begränsa sessioner och modeller till kontoägaren.
- Ladda upp avslutade sessioner från en beständig lokal kö. Använd sessions-ID och kontrollsumma för idempotenta återförsök.
- Kör träning i en separat Python-worker som bygger om varje användares banditstatistik från godkända uppladdade block. För MVP:n är detta uppdatering av statistik, inte träning av ett neuralt nätverk.
- Versionshantera modeller med uppgift om vilka sessioner som ingår. Telefonen byter modell mellan sessioner och spelar in lokala observationer som ännu inte ingår exakt en gång.
- Lås experimentkonfiguration och modellversion vid sessionsstart. En redan inloggad användare kan fortsätta med cachad konfiguration vid nätavbrott.

API under `/v1`:

| Område | Funktioner |
| --- | --- |
| Konton | Registrering, inloggning, tokenförnyelse, utloggning |
| Experiment | Hämta aktiv versionsmärkt konfiguration |
| Sessioner | Ladda upp metadata och rådata, lista och hämta egna sessioner |
| Träning | Skapa och följa personligt träningsjobb |
| Bandit | Hämta senaste kompatibla personliga policy |

Gemensamma datakontrakt: `ExperimentConfig`, `SessionManifest`, `FeatureFrame`, `DecisionEvent` och `BanditSnapshot`. Koppla rådata och ljudhändelser till samma monotona sessionstidslinje och dokumentera uppskattad ljudlatens.

## Genomförande och acceptans

1. Bygg datakontrakten och en reproducerbar simulator med kända EEG-frekvenser, rörelseartefakter, paketluckor och simulerade åtgärdsresponser.
2. Bygg den lokala loopen: baslinje → ljud → EEG-mått → belöning → nytt beslut. Lägg till historik och återuppspelning.
3. Bygg backend med konton, uppladdningskö, versionshanterad konfiguration, träningsworker och modellhämtning. Leverera lokal startmiljö för API, PostgreSQL och worker.
4. Granska Android-paketets version och API via SDK-länkarna nedan. Anslut fysisk Athena och verifiera tidsstämplar, enheter, signalkvalitet och samtidig ljuduppspelning.

Acceptanskriterier:

- Kända syntetiska signaler ger rätt spektrala toppar och bandeffekter. Filter och normalisering jämförs med en oberoende Python-referens.
- Artefakter och paketluckor ger ingen bandituppdatering.
- Banditen lär sig föredra en bättre simulerad åtgärd över reproducerbara försök och fortsätter utforska.
- Stereoljudets frekvensskillnad, kontrollsignal, övergångar och stoppbeteende verifieras.
- Nätavbrott, appomstart och dubbla uppladdningar förlorar eller dubbelräknar inte observationer.
- Kontoseparation och modellbyten fungerar. En fullständig session på cirka tolv minuter fungerar med fysisk Android-enhet och Athena innan hårdvarustödet räknas som klart.

## Avgränsningar och beroenden

iOS, offentlig molndrift, gemensamma modeller mellan användare och Athena-fNIRS ingår inte i första leveransen. Tillgång till Muse SDK-filerna och en fysisk Athena krävs för att slutföra och verifiera hårdvaruintegrationen. En fungerande simulator verifierar programflödet; faktisk EEG-respons kräver inspelningar från människor.

## Muse SDK-filer

- [SDK-mapp i Google Drive](https://drive.google.com/drive/folders/1ID35qK7zCvRXmQTFsbDgmPkVGhnPeCxa)
- [Android SDK-fil](https://drive.google.com/file/d/1l6LrH3Uy4KUlEAR0-dT-78bHAz6CDrTG/view)
- [iOS SDK-fil](https://drive.google.com/file/d/1CyxrYpCGOSE1b9Fj0_VSiqS-p3YePhyd/view)

Kontrollera åtkomst, version och licensvillkor när implementationen startar. iOS-länken sparas för en senare plattformsutökning.

## Källor att återvända till

- [Muse SDK FAQ](https://choosemuse.my.site.com/s/article/Muse-Software-Development-Kit-SDK-FAQs) och [Muse utvecklarsida](https://choosemuse.com/pages/developers)
- [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [FastAPI autentisering](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/)
- [Översikt av evidens för binaurala beats och EEG](https://pmc.ncbi.nlm.nih.gov/articles/PMC10198548/)
