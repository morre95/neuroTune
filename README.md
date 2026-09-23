# neuroTune

neuroTune är en Android-prototyp som spelar binaurala toner och lär sig, per person, vilken frekvens som höjer relativ theta i EEG. Under en session mäts signalen från en Muse S Athena eller från den inbyggda simulatorn. En personlig bandit väljer mellan 6, 8, 10 och 12 Hz samt en kontrollton. EEG, ljud och beslut körs på telefonen, så en påbörjad session fungerar utan nät. Konton, sessionsuppladdning och uppdaterad policy ligger i en Python-backend.

Det här är en utforskande prototyp. Måttet är baslinjenormaliserad relativ theta medan ljudet spelas, och ska inte läsas som bevis på avslappning, fokus eller behandlingseffekt. En session tar ungefär tolv minuter och kräver stereohörlurar.

## Förutsättningar

- [Flutter](https://docs.flutter.dev/get-started/install) med Dart 3.12 eller nyare
- Android SDK, plus en telefon eller emulator
- Docker, för backend och PostgreSQL
- Valfritt: Muse S Athena och Interaxon libmuse Android 8.0.9, uppackad till `vendor/muse-android/libmuse_android_8.0.9` (katalogen är gitignorerad). Android-bygget länkar `libs/libmuse_android.jar` därifrån.

## Backend

Från repo-roten:

```bash
docker compose up --build
```

API:t lyssnar på [http://localhost:8000](http://localhost:8000). Hälsokoll: `GET /v1/health`. PostgreSQL är bara exponerad på `127.0.0.1:5433`. Workern räknar om banditstatistiken från uppladdade block.

## Appen

Starta backend först. I Android-emulatorn är värddatorn `10.0.2.2`, vilket också är appens standardadress.

```bash
cd app
flutter pub get
flutter run
```

På en fysisk telefon pekar du appen mot datorns adress i samma nät:

```bash
flutter run --dart-define=API_BASE=http://192.168.1.10:8000
```

Byt `192.168.1.10` mot datorns LAN-adress. Skapa konto i appen, välj ögonläge och starta antingen simulatorn eller Muse. Simulatorn räcker för att köra hela flödet utan headset.

Om `flutter run` bygger APK:n men installationen avbryts med `INSTALL_FAILED_INSUFFICIENT_STORAGE` är emulatorns datapartition nästan full. Android håller ungefär 500 MB i reserv och vägrar då installationen även när APK:n får plats i det som återstår. Sänk reserven på den körande emulatorn och kör `flutter run` igen:

```bash
adb shell settings put global sys_storage_threshold_percentage 1
adb shell settings put global sys_storage_threshold_max_bytes 52428800
```

Inställningen ligger kvar tills emulatorns data återställs. Pixel 7 Pro-avd:n i det här projektet har `disk.dataPartition.size=6G`. När ledigt utrymme tar slut igen, förstora partitionen eller avinstallera appar du inte använder.

Installera en APK:

```bash
cd app
flutter build apk --dart-define=API_BASE=http://192.168.1.10:8000
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`API_BASE` bakas in vid bygget. Samma adress gäller för `flutter run` och för APK:n.
