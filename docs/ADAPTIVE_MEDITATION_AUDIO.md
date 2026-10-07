# Adaptivt meditationsljud i neuroTune

Målet är att skapa och organisera bakgrundsljud i en webbapp som är ansluten
till backenden och välja ljudprofiler från en lista i neuroTune. Mobilappen
genererar binaurala toner, blandar dem med den nedladdade bakgrunden och ska
på sikt anpassa tonerna efter personliga EEG-mönster. Den önskade upplevelsen
är mindre upptagenhet av tankar och mer
avslappning. Personliga samband undersöks genom kalibrering och återkoppling
efter meditationen.

Detta är den överenskomna målbilden från samtalet den 7 oktober 2026.
Webbeditor, ljudbibliotek, kalibrering, bakgrundsmix och personlig
EEG-styrning är planerad utveckling.

## Beslut för första versionen

| Område | Beslut |
| --- | --- |
| Ljudgenerering | Tonerna skapas direkt i neuroTune. |
| Bakgrund | Användarens egna musikfiler eller naturljudsfiler. |
| Ljudskapande | En webbeditor för uppladdning, blandning och provlyssning. |
| Ljudbibliotek | Backenden lagrar bakgrundsfiler och versionerade ljudprofiler. |
| Val i mobilappen | Lista med ljudprofiler, förhandslyssning och nedladdning. |
| Profilens innehåll | Bakgrundsljud plus ett separat tonrecept. |
| Uppspelning | Lokal uppspelning och tonblandning efter nedladdning, även utan nät. |
| Volymer | Fast tonvolym och fast bakgrundsvolym under sessionen. |
| Kalibrering | Tio sessioner på cirka tio minuter vardera. |
| Toninställningar | Frekvensskillnaderna 0, 6, 8, 10 och 12 Hz. |
| Fördelning | Varje inställning provas två gånger i slumpad ordning. |
| Presentation | Frekvensetiketten är dold under kalibreringen. |
| Inom en kalibreringssession | Samma frekvensskillnad hela sessionen. |
| Återkoppling | Endast efter meditationen. |
| Senare anpassning | Utvärdering ungefär varje minut och mjuka frekvensövergångar. |
| Osäkert underlag | Behåll den föredragna fasta toninställningen och samla mer data. |
| Dålig EEG-kvalitet | Behåll ljudinställningen och avstå från inlärning för perioden. |

## Webbeditor och ljudbibliotek

Webbappen används för att ladda upp egen musik och egna naturljud, blanda
dem till ett bakgrundsljud, provlyssna och spara en ljudprofil. Backenden
lagrar bakgrundsfilen, profilens inställningar och versioner i ett personligt
ljudbibliotek.

Varje profil består av en bakgrundsfil och ett separat tonrecept. Tonreceptet
anger bland annat bärfrekvens och tonvolym; profilen innehåller också
bakgrundsvolym. Frekvensskillnaden väljs av kalibreringsprotokollet eller
den senare personliga EEG-styrningen.

En profil kan exempelvis heta ”Regn och ambientmusik” och innehålla en
blandning av dessa bakgrundsljud, fasta volymnivåer och bärfrekvens 220 Hz.
Tonerna genereras och blandas in i mobilappen under sessionen.

En färdig ljudfil med inbakade toner låser frekvensskillnaden. För att ändra
den under uppspelning skulle flera synkroniserade filversioner och övergångar
mellan dem behövas. Separat bakgrund och tonrecept låter samma bakgrund
fortsätta medan neuroTune ändrar tonerna mjukt.

| Del | Ansvar |
| --- | --- |
| Webbappen | Uppladdning av musik och naturljud, bakgrundsmix, provlyssning och skapande av ljudprofiler. |
| Backenden | Personligt ljudbibliotek, bakgrundsfiler, profilinställningar och versioner. |
| neuroTune | Lista, förhandslyssning, nedladdning, lokal uppspelning, tonblandning och EEG-styrt frekvensval. |

Mobilappen laddar ned vald bakgrund före sessionen och spelar den lokalt.
Pågående uppspelning och ljudanpassning ska fungera utan nätanslutning.

```text
Egen musik och naturljud → webbeditor → bakgrundsfil och tonrecept
                                                ↓
                                  ljudbibliotek i backenden
                                                ↓
                              profilval och nedladdning i neuroTune
                                                ↓
                       lokal bakgrund + genererade toner → hörlurar
```

## Binaurala toner och frekvensskillnad

Två närliggande toner presenteras separat för öronen. Exempelvis kan
200 Hz i vänster öra och 206 Hz i höger öra ge en upplevd rytm på 6 Hz.
Tonerna är jämna; volymen behöver inte pulseras för att skapa den binaurala
rytmen. Hörlurar bevarar separationen mellan öronen.
[Studie om binaurala slag](https://pmc.ncbi.nlm.nih.gov/articles/PMC3243787/).

neuroTune använder en bärfrekvens som ligger mitt mellan tonerna:

```text
Vänster frekvens = bärfrekvens − frekvensskillnad / 2
Höger frekvens   = bärfrekvens + frekvensskillnad / 2
```

Med appens nuvarande standardbärare på 220 Hz blir tonparen:

| Frekvensskillnad | Vänster öra | Höger öra |
| --- | --- | --- |
| 0 Hz | 220 Hz | 220 Hz |
| 6 Hz | 217 Hz | 223 Hz |
| 8 Hz | 216 Hz | 224 Hz |
| 10 Hz | 215 Hz | 225 Hz |
| 12 Hz | 214 Hz | 226 Hz |

Bärfrekvensen påverkar tonhöjden. Frekvensskillnaden bestämmer den binaurala
rytmen. Kontrollinställningen har samma ton i båda öronen, med samma bakgrund
och volymer som de andra inställningarna.

Hemi-Sync beskriver produktioner med flera lager av binaurala signaler,
musik, brus och ibland verbal guidning. Egna binaurala tonpar använder samma
grundprincip, men motsvarar inte ett fullständigt recept för en produktion
från Hemi-Sync. [Hemi-Syncs processbeskrivning](https://hemi-sync.com/research-papers/the-hemi-sync-process/).

## Blandning med musik och naturljud

En stereomixer kombinerar tonerna och bakgrunden separat för varje kanal:

```text
Vänster ut = tonvolym × vänster ton + bakgrundsvolym × vänster bakgrund
Höger ut   = tonvolym × höger ton   + bakgrundsvolym × höger bakgrund
```

En stereofil behåller sina två kanaler. Ett monoljud kan läggas lika i båda
kanalerna. De binaurala tonerna ska fortfarande ligga i varsin kanal.

Volymfaktorerna styr signalernas amplitud. Summan behöver hållas inom det
digitala ljudets maxnivå för att undvika kapade vågtoppar och distorsion.
Bakgrunden kan maskera tonerna, så balansen behöver provlyssnas.

Bakgrunden fortsätter när frekvensskillnaden ändras. Ett byte från 6 till
10 Hz med bärare 220 Hz innebär att tonparet ändras från 217/223 till
215/225 Hz, med mjuk övergång och fasta volymnivåer.

## Personlig kalibrering

Varje kalibreringssession använder en fast frekvensskillnad. Det gör att
återkopplingen efter sessionen kan kopplas till en bestämd toninställning.
Om flera inställningar provas under samma session kan en enda efterbedömning
inte direkt ange vilken inställning som hjälpte.

Under kalibreringen används samma bakgrundsljud, fasta volymer och ungefär
samma sessionslängd. De fem inställningarna provas två gånger vardera i
slumpad ordning. Kontrollsessionerna hjälper till att undersöka om
frekvensskillnaden tillför något till upplevelsen.

Efter varje meditation skattar användaren:

- Hur upptagen av tankar användaren var under sessionen.
- Hur avslappnad användaren kände sig under sessionen.

Inga skattningar begärs före eller under meditationen i första versionen.
Skalornas utformning och hur de två bedömningarna vägs samman är ännu inte
beslutade.

Tio sessioner är ett första underlag. Fler kan behövas om resultaten varierar
mycket eller EEG inte visar ett användbart samband med upplevelsen.

## Anpassning efter kalibrering

Appen ska undersöka vilka EEG-mönster som följer användarens upplevelse av
mindre mental upptagenhet och mer avslappning. Mer theta är inte ett
universellt mått på meditationsdjup; en studie fann lägre theta vid högre
självrapporterat djup. [Studien om EEG och meditationsdjup](https://pubmed.ncbi.nlm.nih.gov/34858638/).

När kalibreringen ger tillräckligt stöd för ett personligt styrmått kan
appen börja anpassa frekvensskillnaden inom sessionen. Utvärderingen sker
ungefär varje minut och tonerna ändras med mjuka övergångar. Bakgrunden och
volymerna ligger kvar.

```text
EEG → kvalitetskontroll → personligt styrmått → frekvensval
                                                  ↓
Egen musik eller naturljud + binaurala toner → stereomixer → hörlurar
```

Vid osäkert kalibreringsunderlag används den föredragna fasta inställningen
och mer data samlas in. Vid dålig EEG-kvalitet under en adaptiv session
behåller appen ljudinställningen och avstår från att lära av perioden.

EEG-mått, modell, kriterier för tillräckligt underlag och utvärdering av
anpassningens nytta återstår att bestämma. Ingen viss frekvensskillnad har
pekats ut som generellt bäst för meditation.

## Utgångspunkt i befintlig kod

- [BinauralSynth](../packages/neurotune_core/lib/src/audio.dart) genererar
  separata stereotoner och har mjuka amplitudövergångar vid frekvensbyte.
- [StimulusAction och ExperimentConfig](../packages/neurotune_core/lib/src/models.dart)
  innehåller de fem toninställningarna och standardbäraren 220 Hz.
- [SessionController](../app/lib/session/session_controller.dart) skickar
  genererade toner som PCM till Android. Sessionsflödet har ännu ingen mixer
  för egna musikfiler eller naturljudsfiler.
- [SessionEngine](../packages/neurotune_core/lib/src/engine.dart) använder
  idag baslinjenormaliserad rå intensitet från yttre NIR-kanaler som belöning.
  EEG-mått loggas, men styr inte den nuvarande belöningen. Den önskade
  personliga EEG-styrningen kräver därför en ändring av styrmått och inlärning.

## Fortsatt utveckling

Första upplägget är att bygga en enkel webbeditor, ett personligt
ljudbibliotek i backenden och profilval med förhandslyssning och nedladdning
i mobilen. Lokal uppspelning och stereomix behöver kopplas till den
befintliga tongeneratorn.

Filformat, import i webbeditor, profilens exakta datamodell, loopning av
bakgrundsljud och eventuell baslinjemätning inom sessionens tio minuter
återstår att specificera. EEG-måtten och deras koppling till
efterbedömningarna behöver också bestämmas innan personlig EEG-styrning
aktiveras.
