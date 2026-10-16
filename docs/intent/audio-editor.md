# Målbild: visuell ljudredigering i neuroTune

Status: bekräftad av användaren i intervjun 2026-10-16.

## Mål och användare

Bygga om neuroTunes webbgränssnitt så att användaren kan skapa en
sammanhängande ljudfil av utvalda delar från flera ljudfiler.

Användaren vill arbeta med egna ljudfiler från datorn och med ljud som redan
finns i neuroTune, och redigera dem till ett gemensamt slutresultat.

## Bekräftat arbetsflöde

- Se ljudvågor och välja ut delar av ljudfiler.
- Dra klipp till en tidslinje och ändra deras ordning.
- Främst lägga klippen efter varandra.
- Kunna göra mjuka övergångar så att skarvarna hörs mindre tydligt.
- Provlyssna och exportera en färdig, sammanhängande ljudfil.
- Spara arbetet som ett projekt och öppna det senare med klipp och övergångar
  bevarade, så att arbetet kan fortsätta under längre tid utan att börja om.

## Avgränsning för första versionen

Avancerad flerspårsmixning, inspelning och en större uppsättning ljudeffekter
ingår inte.

## Skillnad mellan målbild och specifikation

Målbilden beskriver användarens bekräftade avsikt. Tekniska utgångsvärden
och verifieringsbehov framgår av den godkända genomförandeplanen.

## Bekräftat tillägg: projektsparande

Användaren har godkänt att projekt och tillhörande ljudfiler sparas på det
befintliga neuroTune-kontot i backend, med automatisk sparning och synlig
sparstatus. Efter ny inloggning ska projektet kunna öppnas utan att
originalfilerna väljs från datorn igen.

Specifikationen är godkänd av användaren. Kvarvarande uttryckligen öppna
tekniska frågor och standardvärden preciseras i genomförandeplanen.

## Bekräftat tillägg: slutresultatets längd

Första versionen ska stödja en färdig, sammanhängande ljudfil på upp till
och med en timme (60 minuter, 3 600 sekunder). Längden avser den färdiga
tidslinjen efter eventuella överlapp vid mjuka övergångar.

## Bekräftat tillägg: importerade filers längd

Varje importerad ljudfil får också vara upp till och med en timme
(60 minuter, 3 600 sekunder). Användaren ska kunna välja avsnitt ur hela
den importerade filen, även efter den tionde minuten.

Genom plangodkännandet är utgångsvärdena högst 1 GiB per importerad fil
och högst 100 sekventiella klipp per projekt fastställda.

## Bekräftat tillägg: exportformat och användning

Slutresultatet ska kunna exporteras och laddas ned som både WAV och MP3.
Båda formaten ska kunna delas och bearbetas vidare.

En exporterad fil kan importeras igen som en sammanhängande ljudkälla.
Det sparade projektet bevarar de enskilda klippen och övergångarna för
fortsatt redigering.

## Bekräftat tillägg: användning i appen

Samma färdiga komposition ska kunna publiceras som en ljudprofil för
meditation i neuroTune-appen och exporteras som en separat WAV- eller
MP3-fil.

Publiceringen ska utgå från samma redigerade slutresultat. Senare ändringar
i projektet får inte skriva över en redan publicerad profilversion.

## Bekräftat tillägg: fast eller valbar speltid i appen

Hela slutresultatet ska kunna spelas i appen, även när det är upp till
en timme långt. I webbgränssnittet ska användaren kunna välja mellan:

- **Fast längd:** appens planerade speltid bestäms av den färdiga ljudfilens
  längd. Användaren väljer inte en annan planerad längd i appen.
- **Valbar längd:** användaren får välja planerad speltid i appen.

Valet ska följa med det publicerade ljudet till appen. I valbart läge får
speltiden överstiga ljudfilens längd genom loopning. Exempelvis ska en
20-minutersfil kunna spelas i 40 minuter. Loopningen gäller uppspelningen;
den ändrar inte längden på den exporterade kompositionen.

Appen avslutar mjukt vid den valda aktiva speltiden, även mitt i en repetition.
Paus och manuellt stopp ska fortsatt vara möjliga i båda lägena. Fast läge
följer ljudfilens längd och förlängs inte genom loopning.

Genom plangodkännandet är valbar speltid 1–60 minuter i minutsteg, plus ett
separat val av hela filens exakta längd. Hela filens längd är förvald.

## Bekräftat tillägg: mjukt avslut i appen

Användaren upplever dagens avslut som tvärt. Appens ljud ska i stället
tonas ut mjukt till tystnad, även när vald speltid slutar mitt i en loopad
fil. Bakgrundsljud och toner ska avslutas tillsammans.

Uttoningen vid planerat slut ska rymmas inom den valda speltiden och nå
tystnad vid sluttiden. Manuellt stopp ska också avsluta mjukt innan
ljudutmatningen stängs. Uppspelningens uttoning ändrar inte de exporterade
WAV-/MP3-filerna.

Fem sekunders uttoning är godkänt utgångsvärde genom planen. Kurva och
upplevt mjukt avslut ska verifieras genom ljudtester och lyssningsprov.

## Specifikation

Enligt AGENTS.md är GitHub Issues i `morre95/neuroTune` den kanoniska platsen
för specifikationer och ärenden. Målbilden är inte en implementationplan.

Godkänd specifikation: [GitHub Issue #20](https://github.com/morre95/neuroTune/issues/20).

Godkänd genomförandeplan: [tasks/plan.md](../../tasks/plan.md).
