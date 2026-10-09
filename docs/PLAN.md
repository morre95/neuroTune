# neuroTune: aktuell leveransplan

Den ursprungliga Android-prototypen finns kvar i **Experiments**. Personlig-läget
lär en femarmad bandit från baslinjenormaliserad rå yttre NIR-intensitet
(`OPTICS3`/`OPTICS4`); Jämförelse använder balanserad slumpordning utan
policyuppdatering. EEG theta/alpha/beta är inspelade mått, inte denna belöning.
NIR är rå optisk intensitet, inte syresättning. Standardexperimentet har 120 s
tyst baslinje och 15 block med 30 s ljud samt 10 s paus; belöningen använder
blockets sista 20 s. Konfiguration och policy låses vid start.

Den separata meditationsleveransen implementerar
[spec #1](https://github.com/morre95/neuroTune/issues/1): personlig ljudeditor och
bibliotek, nedladdning, lokal stereomix, tio minuters aktiv uppspelning,
blindad kalibrering, efter-skattningar, synk/radering och en validerad personlig
EEG-modell. Den har ingen tyst baslinje och använder ett annat inlärningsflöde.

## Leveransstatus

Implementationsärendena #2–#15 är avslutade. #16 samlar helhetsgranskning,
regression, aktuell dokumentation och fysisk Android/Muse-acceptans. General
release bygger fortfarande utan `MEDITATION_ENABLED=true`; detta värde förblir
avstängt tills acceptansprotokollet visar godkända resultat. En simulator eller
syntetisk modell kan verifiera programbeteende, men godkänner inte hårdvaran.

- [Användarflöde och beslutade modellregler](ADAPTIVE_MEDITATION_AUDIO.md)
- [Backend, worker, lagring och migrationer](MEDITATION_OPERATIONS.md)
- [Reproducerbart flöde, regressionskommandon och fysisk acceptans](MEDITATION_ACCEPTANCE.md)
- [Sessionsdiagnostik och saknade värden](SESSION_DIAGNOSTICS.md)

## Muse SDK-filer

Android-bygget kräver Interaxon libmuse Android 8.0.9 i
`vendor/muse-android/libmuse_android_8.0.9/libs/`. SDK-filer är gitignorerade.
En fysisk Android-telefon och Muse S Athena behövs för återstående acceptans.

- [SDK-mapp](https://drive.google.com/drive/folders/1ID35qK7zCvRXmQTFsbDgmPkVGhnPeCxa)
- [Android SDK-arkiv](https://drive.google.com/file/d/1l6LrH3Uy4KUlEAR0-dT-78bHAz6CDrTG/view)
- [iOS SDK-arkiv för eventuell senare utveckling](https://drive.google.com/file/d/1CyxrYpCGOSE1b9Fj0_VSiqS-p3YePhyd/view)

## Avgränsning

Första meditationsversionen gäller Android, privata konton och egna ljudfiler.
Ingen allmän EEG-skala för meditationsdjup, kausal effekt av adaptation,
terapinytta, iOS-leverans, offentligt ljudbibliotek eller strömmad bakgrund ingår.
Modellens aktiveringsgränser är versionsstyrda tekniska kriterier. En randomiserad
adaptiv/fixed-jämförelse ingår inte i denna release.
