# Sessionsdiagnostik

Nya Muse-inspelningar sparar diagnostik i både sessionsmanifestet och råfilen.
`diagnostics_version: 1` anger att loggningen varit aktiverad. Äldre manifest
utan fältet läses som version 0; uteblivna uppgifter visas som saknade.

## Signaler och händelser

- Batteriprocent från Muse, med en initial avläsning när den finns tillgänglig.
- SDK:ns störningspaket: `blink`, `jaw_clench` och `headband_on`. Registrering
  begärs med `ARTIFACTS`; tillgänglighet måste verifieras på Athena. Inga
  mottagna paket betyder att uppgifterna saknas, inte att inga störningar skett.
  Antalet markeringar är antalet paket med flaggan satt, inte en uppskattning
  av antalet oberoende blinkningar eller hur länge bandet varit av huvudet.
- Ansluten, frånkopplad, återansluten och inspelningens slut. Dubbla fel från
  EEG- och optikströmmen ger bara en frånkopplingshändelse.
- Datagap från batcharnas tidsstämplar, med längd och uppskattat antal saknade
  provtillfällen per ström. Ett provtillfälle omfattar samtliga kanaler.
- Ogiltiga EEG- och optikvärden räknas separat per kanal. Muse använder bland
  annat NaN som platshållare för saknade prover. Dessa kodas som JSON `null`
  i råfilen och återställs som NaN vid läsning. De räknas inte igen som datagap.
- Ogiltiga rörelsevärden räknas som rader i de rörelsedata som hålls och
  samplas om vid EEG-proverna. Det är inte antalet ursprungliga IMU-paket.
- Alla åtta optiska kanaler i befintligt preset 1034, vid 64 Hz. OPTICS1–2
  är yttre 730 nm, OPTICS3–4 yttre 850 nm, OPTICS5–6 inre 730 nm och
  OPTICS7–8 inre 850 nm enligt LibMuse 8.0.9. Både råvärden och medelvärden
  med kvalitetsbedömning per analyssteg sparas. Belöningen använder fortsatt
  de konfigurerade yttre NIR-kanalerna.

Diagnostikhändelser har `time_seconds`, `type` och `values`. Batteri,
störningsmarkörer och anslutningshändelser tidsstämplas när appen observerar
dem, med en monoton klocka från öppningen av sessionen och
`time_source: observed_monotonic`. För Muse-paketen sparas också
`muse_time_seconds`, SDK-klockan före sessionsförskjutningen. Datagap och
ogiltiga värden använder batcharnas sessionsrelativa provtidsstämplar.
Händelse- och provtider kan därför skilja något på grund av buffring;
de ska inte användas för exakt analys av fördröjning mellan signaler.

## Historik

Öppna en session för att se aktuell kanalstatus och felorsaker, optiska
kanaler, godkänd andel per EEG-kanal och diagnostiken över tid. Den godkända
andelen avser sparade analysfönster, inte hela sessionens väggklocketid.
Fönstren överlappar normalt; flera felorsaker kan gälla samma fönster.
Perioder helt utan data räknas inte in i nämnaren och redovisas separat som
datagap eller frånkoppling.

Bluetooth-RSSI samlas inte in: LibMuse-kopplingen exponerar ingen sådan
mätning här. Diagnostiken mäter EEG-kvalitet och leverans av prover.
