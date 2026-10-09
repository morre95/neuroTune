# Meditation med eget ljud och personlig EEG-anpassning

Implementationen följer [spec #1](https://github.com/morre95/neuroTune/issues/1).
Meditation är huvudflödet i ett bygge med `MEDITATION_ENABLED=true`; annars
öppnas det befintliga experimentflödet. Flaggan är avstängd som standard tills
[Android/Muse-acceptansen](MEDITATION_ACCEPTANCE.md) är dokumenterad och godkänd.

## Skapa en ljudprofil

1. Öppna backendens `/editor/` och logga in med samma konto som i Android-appen.
   Skapa vid behov kontot i appen. Webbsidan håller tokens i minnet; efter
   omladdning behöver du logga in igen.
2. Ladda upp egna musik- eller naturljudsfiler: **WAV, MP3, M4A/AAC eller FLAC**,
   mono eller stereo, högst **100 MiB och 600 sekunder per källa**. Importstatus
   är pending, ready eller failed. Ett fel anger vad du behöver korrigera;
   ladda upp den korrigerade filen som en ny källa.
3. Tryck **Create profile from …** på en färdig källa. Kombinera **1–4 spår**.
   Välj källa, start/slut för trimning, fast spårgain (0–4) och loopning för varje
   spår. Alla spår börjar tillsammans. Ett spår utan loop blir tyst när dess
   valda avsnitt tar slut. Välj en bakgrundslängd på **30–600 sekunder**.
4. Tryck **Render background** och invänta ready. **Preview rendered background**
   spelar upp de första 30 sekunderna. Den använder samma renderade mix och
   normaliseringsfaktor som den sparade bakgrunden. Förhandslyssningen innehåller
   enbart bakgrund; det tilldelade tonparet genereras senare i telefonen.
5. Namnge profilen och spara bärare, tongain, bakgrundsgain samt om den färdiga
   bakgrunden ska loopa under meditation. Bäraren kan vara **100–400 Hz**,
   standard **220 Hz**. Standardgain är **0,2 ton och 0,6 bakgrund**; summan får
   vara högst **0,95**. Redigering och **Save new version** skapar en ny oföränderlig
   version; tidigare sessioner och nedladdningar behåller sin ursprungliga version.

Bakgrunden är en kanonisk **48 kHz stereo PCM16 WAV**. Mono dupliceras mellan
öronen, stereo behåller kanalerna. Rendering använder en enda fast faktor om
hela mixens topp annars överskrider maxnivån. Mobilens ton- och bakgrundsgain
ändras inte under sessionen.

## Ladda ned och meditera utan nät

I appen, öppna **Ljudprofiler**, uppdatera listan och förhandslyssna. Tryck
**Ladda ned** och invänta **Nedladdad · redo offline**. Nedladdning visar framsteg
 och kan avbrytas. Format och SHA-256 verifieras innan kopian blir spelbar;
 ofullständiga eller korrupta filer kan inte starta en meditation. Verifierade
 filer och profilmetadata finns kvar efter omstart. **Ta bort lokal kopia**
 frigör mobilens fil, men tar inte bort backendens profil.

Välj nedladdad profil, ögonläge och **Simulator** eller **Muse**. På kontaktsidan
kan du **Testa hörlurar** och sedan **Starta meditation**. Utan ett nytt eget
0/6/8/10/12 Hz-tonval används ditt sparade val, annars rekommendationen för samma
profil/ögonläge/datakälla, annars 0 Hz-kontroll. Ett giltigt, cachat EEG-underlag
för vald uppsättning aktiverar adaptation automatiskt; kalibrering förblir fast.
**Experiments** öppnar de tidigare NIR-lägena.

En session omfattar **600 sekunder faktiskt spelat ljud**, utan tyst baslinje
eller ljud/paus-block. Telefonen läser bakgrund, genererar toner, mixar, gör
adaptiva beslut och sparar inspelningen lokalt. Redan pågående HTTP-arbete
avslutas före start och uppladdningsförsök vilar tills sessionsvyn stängs.
Använd en tidigare inloggad app och en färdig nedladdning; ny inloggning och ny
nedladdning behöver nät.

Ljudavbrott pausar den aktiva klockan. **Fortsätt** återupptar samma toninställning
 och samma spelade bakgrundsposition. Tyst avbrottstid ingår inte i 600 sekunder.
 Manuellt stopp eller ett oåterställbart ljudfel sparar en stoppad session.
 Dålig/saknad EEG eller frånkopplad Muse stoppar inte meditationsljudet.
 Skärmavstängning stöds av Androids förgrundstjänst och CPU-lås; faktisk funktion
 på telefon måste verifieras i acceptansprotokollet.

Tonparet är bärare minus/plus halva frekvensskillnaden. Med 220 Hz blir
kontroll 220/220 Hz och 6/8/10/12 Hz ger 217/223, 216/224, 215/225 respektive
214/226 Hz. Hörlurar behåller vänster/höger-separation. Tonbyte glider under
**5 sekunder** med kontinuerlig fas och fast amplitud. Bakgrundsloopar överlappar
**500 ms**; start/stopp har korta amplitudramper.

## Blindad kalibrering och efter-skattningar

**Kalibrering → Ny serie · Simulator/Muse** skapar en beständig, slumpad plan
med exakt två sessioner vardera för 0, 6, 8, 10 och 12 Hz. Profilversion, bärare,
gains, längd, ögonläge och datakälla låses för hela tiosessionsserien. Ett annat
upplägg behöver en ny serie. Omstart ändrar inte tilldelningarna.

Frekvensetiketter döljs i kalibreringssessionen, historiken och uppspelningen
 tills hela serien är klar. En ofullständig serie bidrar inte till synliga
 rekommendationer eller per-tonmedelvärden; annars skulle en enskild tilldelning
 kunna avslöjas indirekt. En redan avslutad serie kan ge fast fallback under
 nästa serie. Individuellt avslutade, skattade fasta sessioners EEG-eligibilitet
 bedöms separat.

Efter en full meditation skattar du två **heltal 0–10**:

- **Mental upptagenhet:** 0 ingen, 10 extrem.
- **Avslappning:** 0 ingen, 10 fullständig.

Varje val sparas lokalt. **Slutför senare** lämnar återkopplingen tillgänglig i
Kalibrering även efter omstart. Inga skattningar begärs före eller under sessionen.
En kalibreringsplats blir klar först efter 600 aktiva sekunder **och båda
skattningarna**. Ett stoppat försök lämnar platsen öppen. Dålig EEG under en full
session hindrar inte den subjektiva jämförelsen, men kan utesluta EEG-inlärning.

Den kombinerade poängen är **(avslappning + 10 − mental upptagenhet) / 2**.
Efter en färdig serie visar **Resultat och fast ton** tilldelningar/skattningar
 och rekommenderar högst medelpoäng. Samma uppsättning används först; om den
 saknar färdiga serier används poolade färdiga serier från samma datakälla.
 Lika medelvärden bryts i ordningen **0, 6, 8, 10, 12 Hz**. Du kan spara en annan
 fast ton och välja **Samla en serie till**. Muse och simulator är separata.

## När EEG-anpassning blir tillgänglig

Modellen använder avslutade, skattade **kalibrerings- och fasta sessioner**.
Adaptiva sessioners efter-skattningar sparas för utfallsöversikt och tränar inte
modellen i denna version. Simulator, playback och Muse blandas inte.

En EEG-minut behöver minst två giltiga kanaler under **80 %** av de kvalificerade
sekunderna. De första **10 sekunderna av varje minut** utesluts för filterstart/
övergång. Log(theta/alpha) och log(beta/alpha) medelvärdesbildas över giltiga
kanaler och perioder. Varje session ger **en träningsrad**, inte en etikett per
minutfönster. Modellens kontext omfattar bakgrundsidentitet, bärare, båda gains
 och ögonläge. Ridge regression har straff 1, ostraffad intercept och
 standardisering från träningsdata.

Alla aktiveringsgränser måste klaras:

| Villkor | Gräns |
| --- | --- |
| Användbara, fulla, skattade fasta sessioner | Minst 20 |
| Leave-one-session-out MAE | Högst 2 skattningspoäng |
| Korrelation för hållna sessioner | Minst 0,5 |
| MAE-förbättring över modell med enbart kontext | Minst 20 % |
| Stöd för vald kontext | Minst 5 användbara sessioner för bakgrund/ögonläge och numeriska inställningar inom träningsintervallen |

Förbehandling anpassas inuti varje valideringsfold. För lite data, underkänd
validering, återkallad modell, inkompatibel EEG-konfiguration eller ostött kontext
behåller fast uppspelning. **Uppdatera EEG-modell** synkar underlag och hämtar
aktuell modell när appen är inaktiv. En tidigare giltig cache fungerar offline.
Modellversionen fryses för varje session.

Adaptation börjar med den föredragna fasta tonen, utvärderar var **60:e sekund**
 och använder separat epsilon-greedy-statistik (**epsilon 0,1**) per konto,
 exakt uppsättning och modellversion. Exploatering byter bara vid uppskattad
 fördel på minst **0,5 skattningspoäng**; utforskning får välja annat. Otillräcklig
 EEG håller aktuell ton och hoppar över inlärning. Beslut, kvalitet, sannolikheter,
 prediktioner, modell och övergångar sparas. Synk byter aldrig modell mitt i en
 session.

Gränserna är versionsstyrda tekniska kriterier. Prediktivt samband visar inte
att adaptiva tonbyten orsakar bättre upplevelse, och ingen frekvens är generellt
bäst. Syntetiska simulatorresultat kan inte bekräfta fysisk EEG-effekt.

## Synk och radering

Sessioner, kalibreringsplaner och återkoppling tillhör det inloggade kontot.
Nedladdningar, köer, modeller och tonstatistik är också kontoseparerade. Efter
nätåterkomst synkas först raderingar, sedan plan före tillhörande session och
återkoppling efter sessionsuppladdning. Återförsök skapar inga dubbletter.

I **Sessionshistorik**, välj sessioner och **Radera valda**, sedan bekräfta.
Rådata, återkoppling och beroende inlärningsunderlag tas bort; berörd modell/
tonstatistik ogiltigförklaras och kvarvarande underlag kan byggas om. En liten
raderingsmarkering utan signaldata hindrar fördröjda köer från att återställa
sessionen. Offline radering köas och synkstatus visar när den har bekräftats.
Detta raderar sessioner, inte ljudbibliotekets källor eller profiler.

Se [driftinstruktionerna](MEDITATION_OPERATIONS.md) för worker, migrationer,
lagring och felsökning, och [acceptansprotokollet](MEDITATION_ACCEPTANCE.md)
för ett sammanhängande editor-till-telefon-flöde och kvarvarande hårdvarukontroller.
