# Navigeringsprestanda

## Ändring 2026-10-15

Historik och kalibrering använder nu `SessionSummary`. EEG-frames, diagnostik
och meditationens `playback_timeline` hämtas först när en fullständig inspelning
behövs. Historiken visar 50 poster åt gången med stabil sortering på datum och
sessions-ID. **Välj alla** omfattar hela det inloggade kontots historik.

Kalibreringens framsteg och väntande återkoppling beräknas från en gemensam
transaktion med metadata. Synken läser fullständiga inspelningar endast för
väntande uppladdningar. Modellernas evidenskontroller använder riktade
sammanfattningar och behåller kontroll av raderingar och återkopplingsrevisioner.

Ljudbiblioteket återanvänder verifieringsresultat inom samma appkörning när
filens identitet, storlek och tidsstämplar är oförändrade. Samtidiga kontroller
delar arbetet. Full kontrollsumme- och formatverifiering görs efter nedladdning,
vid första inläsning efter omstart, vid filförändring och före uppspelning.
Första starten kan därför fortfarande behöva läsa alla nedladdade ljudfiler.

## Lokal databas

Schema 7 lägger till `summary_json` och `decision_count`, fyller befintliga
poster och installerar triggers som håller sammanfattningen uppdaterad vid
inläggning och ändring av originalet. Index stöder kontofiltrering,
historiksortering och kalibreringsförsök. Inspelningarnas originalmanifest,
beslut, EEG-data, råfiler och kontrollsummor bevaras.

## Mätning

Syntetiska sessioner med 600 EEG-frames och fyra kanaler per frame, med en
kalibreringsserie per tio sessioner. Den nya vägen använder en gemensam
kalibreringsöversikt och historikens första sida. Nya tider är medianen av tre
varma körningar i den slutliga testsuiten på värddatorn.

| Sessioner / serier | Tidigare laddning | Ny laddning |
| --- | ---: | ---: |
| 10 / 1 | 256 ms | 3,9 ms |
| 40 / 4 | 2 361 ms | 5,6 ms |
| 80 / 8 | 8 965 ms | 8,4 ms |

Med ytterligare 12 000 uppspelningscheckpoints och 1 000 diagnostikhändelser
per session tog 80-sessionsfallet 7,4 ms. Samtliga nya fall laddade översikten
utan att anropa fullständig historik- eller detaljladdning. Tiderna avser
dataladdning i utvecklingsmiljö; telefonens totala UI-latens mäts separat.

Kör det reproducerbara försöket från `app/`:

```bash
flutter test --no-pub test/session_loading_test.dart --plain-name 'navigation workload scales without decoding EEG or timelines'
```

Automatiska tester kontrollerar arbetsmängd och funktion. Tiderna rapporteras
som mätvärden och används inte som miljöberoende testgränser.

## Verifiering

- Flutter-analys utan anmärkningar; samtliga 219 app-tester passerar.
- Regressioner för migration, sidgränser och lika datum, kontoseparering,
  urval över sidgränser, radering, blindning, modellåterkallelse och offline-synk.
- Fördröjd historikladdning kan lämnas med Androids bakåtknapp och får inte
  ersätta en senare sida eller återställa ett utloggat konto.
- Ljudtester täcker återanvändning, samtidiga kontroller, omstart och korruption
  även när storlek och ändringstid matchar den tidigare filen.
- Debug-APK byggd och installerad på ansluten Android-telefon. Verifierad
  migration 6 → 7 med godkänd `integrity_check` och identiska originalfält för
  telefonens sparade inspelning. Tidigare APK och databas finns som lokal
  säkerhetskopia i `/tmp/neurotune-before-navigation-fix/`.
