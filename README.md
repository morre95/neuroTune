# neuroTune

neuroTune är en Android-prototyp som spelar binaurala toner och lär sig, per person, vilken frekvens som höjer relativ theta i EEG. Under en session mäts signalen från en Muse S Athena eller från den inbyggda simulatorn. En personlig bandit väljer mellan 6, 8, 10 och 12 Hz samt en kontrollton. EEG, ljud och beslut körs på telefonen, så en påbörjad session fungerar utan nät. Konton, sessionsuppladdning och uppdaterad policy ligger i en Python-backend.

Det här är en utforskande prototyp. Måttet är baslinjenormaliserad relativ theta medan ljudet spelas, och ska inte läsas som bevis på avslappning, fokus eller behandlingseffekt. En session tar ungefär tolv minuter. För binauralt ljud bör du använda stereohörlurar; appen gör ingen automatisk kontroll av ljudutgången.

## Förutsättningar

- [Flutter](https://docs.flutter.dev/get-started/install) med Dart 3.12 eller nyare
- Android SDK, plus en telefon eller emulator
- Docker, för backend och PostgreSQL
- Interaxon libmuse Android 8.0.9 krävs för att bygga Android-appen, även om du bara använder simulatorn. Ladda ned [Android SDK-arkivet](https://drive.google.com/file/d/1l6LrH3Uy4KUlEAR0-dT-78bHAz6CDrTG/view) som länkas i [planen](docs/PLAN.md) och packa upp det från repo-roten:

  ```bash
  mkdir -p vendor/muse-android
  tar -xzf ~/Downloads/libmuse_android_8.0.9.tar.gz -C vendor/muse-android
  ```

  Kontrollera att `vendor/muse-android/libmuse_android_8.0.9/libs/libmuse_android.jar` finns efteråt. Bygget använder också `.so`-filerna i samma `libs`-katalog. SDK-katalogen är gitignorerad. En fysisk Muse S Athena behövs först när du vill använda eller verifiera hårdvaruläget.

## Backend

Från repo-roten:

```bash
docker compose up --build
```

API:t lyssnar på [http://localhost:8000](http://localhost:8000). Hälsokoll: `GET /v1/health`. PostgreSQL är bara exponerad på `127.0.0.1:5433`. Workern räknar om banditstatistiken från uppladdade block.

### Backendtester

Kör Pytest i en tillfällig Docker-container från repo-roten:

```bash
docker compose build api
docker compose run --rm --no-deps \
  -e DATABASE_URL=sqlite:// \
  -e RAW_DATA_DIR=/tmp/neurotune-raw-test \
  api sh -c 'pip install ".[dev]" && pytest -q'
```

Testerna använder en separat SQLite-databas och ändrar inte PostgreSQL-datan. `--rm` tar bort testcontainern efter körningen.

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

Byt `192.168.1.10` mot datorns LAN-adress. Skapa konto i appen, välj ögonläge och starta antingen simulatorn eller Muse. På kontaktsidan kan du trycka på **Testa hörlurar** för att spela `audio/stereo_test.wav` upprepade gånger och **Stoppa hörlurstest** när du är klar. Simulatorn räcker för att köra hela flödet utan Muse-headset.

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
