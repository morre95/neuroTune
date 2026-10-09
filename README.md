# neuroTune

neuroTune är en Android-prototyp med två separata flöden. **Experiments** använder
baslinjenormaliserad rå intensitet från de yttre NIR-kanalerna som belöning i
befintliga Personlig- och Jämförelse-sessioner. EEG-måtten loggas också, men
relativ theta är inte experimentens belöning.

**Meditation** spelar tio aktiva minuter med eget nedladdat bakgrundsljud och
lokalt genererade binaurala toner. Mobilens ljudbibliotek, blindade kalibrering,
efter-skattningar och personliga EEG-anpassning finns bakom byggflaggan
`MEDITATION_ENABLED`, som är **avstängd som standard**. Backendens ljud-API och
webbeditor är tillgängliga för utveckling oberoende av mobilflaggan. Fysisk
Android/Muse-acceptans återstår före allmän mobilaktivering; se
[acceptansprotokollet](docs/MEDITATION_ACCEPTANCE.md).

Meditation använder personliga samband mellan EEG och skattad mental
upptagenhet/avslappning. Varken NIR-belöningen eller EEG-modellens prediktion är
bevis på meditationsdjup eller behandlingseffekt. Använd stereohörlurar för att
bevara tonparet mellan öronen.

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

Vid installation, kopiera miljömallen och skapa en egen JWT-hemlighet på minst 32 byte:

```bash
cp .env.example .env
python -c 'import secrets; print(secrets.token_urlsafe(32))'
```

Klistra in det genererade värdet efter `JWT_SECRET=` i `.env`:

```text
JWT_SECRET=ditt-genererade-värde
```

`.env` är gitignorerad. Docker Compose skickar samma värde till `api` och `worker`. Starta sedan från repo-roten:

```bash
docker compose up --build
```

API:t lyssnar på [http://localhost:8000](http://localhost:8000). Hälsokoll: `GET /v1/health`. PostgreSQL är bara exponerad på `127.0.0.1:5433`. Workern importerar ljud, renderar bakgrunder, räknar om NIR-banditstatistik och tränar separata personliga EEG-modeller. Webbeditor: [http://localhost:8000/editor/](http://localhost:8000/editor/). API och worker behöver samma ljud- och rådatavolymer. Se [drift och migrationer](docs/MEDITATION_OPERATIONS.md).

Utanför utveckling sätter du även `ENVIRONMENT=production` i `.env`.

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

I historiken visas signalkvalitet per EEG-kanal och, för nya Muse-inspelningar,
batteri, störningsmarkörer, dataförlust och samtliga åtta optiska kanaler.
Se [sessionsdiagnostik](docs/SESSION_DIAGNOSTICS.md) för vilka värden som sparas
och hur tidsstämplar och saknade uppgifter ska tolkas.

Tryck **Välj** i historiken, markera sessioner (eller **Välj alla**) och tryck
**Radera valda**. Efter bekräftelsen tas de bort från mobilen. Raderingen av
backendens sessionsdata och råfiler köas beständigt om backenden inte nås,
och synkas när appen körs med kontakt igen. Historiken visar väntande synk.
Endast det inloggade kontots sessioner visas och kan raderas. Backendens
personliga statistik räknas om utan de raderade sessionerna; en liten
raderingsmarkering utan signaldata hindrar fördröjda uppladdningar från att
återställa dem. Backendens nya migration körs vid ordinarie Docker-start efter
att API och worker byggts om.

Starta backend först. I Android-emulatorn är värddatorn `10.0.2.2`, vilket också är appens standardadress.

```bash
cd app
flutter pub get
flutter run
```

På en fysisk telefon pekar du appen mot datorns adress i samma nät:

```bash
flutter run --dart-define=MEDITATION_ENABLED=true --dart-define=API_BASE=http://192.168.50.210:8000
```

Byt `192.168.50.210` mot datorns LAN-adress. Skapa konto i appen, välj ögonläge och starta antingen simulatorn eller Muse. På kontaktsidan kan du trycka på **Testa hörlurar** för att spela `audio/stereo_test.wav` upprepade gånger och **Stoppa hörlurstest** när du är klar. Simulatorn kan verifiera programflöden utan Muse-headset. Fysiska ljud-, skärm- och Muse-kontroller måste genomföras separat.

Om `flutter run` bygger APK:n men installationen avbryts med `INSTALL_FAILED_INSUFFICIENT_STORAGE` är emulatorns datapartition nästan full. Android håller ungefär 500 MB i reserv och vägrar då installationen även när APK:n får plats i det som återstår. Sänk reserven på den körande emulatorn och kör `flutter run` igen:

```bash
adb shell settings put global sys_storage_threshold_percentage 1
adb shell settings put global sys_storage_threshold_max_bytes 52428800
```

Inställningen ligger kvar tills emulatorns data återställs. Pixel 7 Pro-avd:n i det här projektet har `disk.dataPartition.size=6G`. När ledigt utrymme tar slut igen, förstora partitionen eller avinstallera appar du inte använder.

Installera en APK:

```bash
cd app
flutter build apk --debug --dart-define=API_BASE=http://192.168.50.210:8000
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`API_BASE` bakas in vid bygget. Samma adress gäller för `flutter run` och för APK:n. Bara debug-byggen får använda `http://`. Ett release-bygge kräver en `https://`-adress, eftersom lösenord, tokens och EEG annars skickas okrypterat. Inloggningen sparas krypterad med en nyckel i Androids nyckellager, och appen har säkerhetskopiering avstängd.

## Meditation och ljudbibliotek

Bygg ett särskilt acceptansbygge för Android:

```bash
cd app
flutter run --dart-define=MEDITATION_ENABLED=true --dart-define=API_BASE=http://192.168.50.210:8000
```

Utan `MEDITATION_ENABLED=true` öppnas det befintliga experimentflödet; de nya
meditations- och ljudbibliotekskontrollerna visas inte. Flaggan är en bygginställning,
inte ett serverreglage. Backendens autentiserade ljud-API och editor är fortfarande
tillgängliga för utveckling.

Logga in på `/editor/` med samma konto **och samma backend** som i appen. Vites
utvecklingseditor använder API:t på `127.0.0.1:8000`; en APK som pekar på en annan
API-instans visar den instansens bibliotek. Vid USB-utveckling kan
`adb reverse tcp:8000 tcp:8000` användas med
`--dart-define=API_BASE=http://127.0.0.1:8000` i ett debug-bygge. Ta bort reverse
med `adb reverse --remove tcp:8000` inför ett faktiskt offlineprov.

Ladda upp WAV, MP3, M4A/AAC
eller FLAC (mono/stereo, högst 100 MiB och 600 sekunder). Blanda upp till fyra
spår, rendera och förhandslyssna, och spara en namngiven profil. I appens
**Ljudprofiler**, uppdatera och ladda ned den. **Nedladdad · redo offline** betyder
att WAV-format och SHA-256 har verifierats. Välj sedan profil, ögonläge och
Simulator eller Muse. Nya profilversioner ersätter inte gamla.

En full meditation kan genomföras utan nät efter nedladdning och inloggning.
Återkoppling sparas lokalt och synkas senare. Kalibrering omfattar tio fulla,
blindade sessioner och två efter-skattningar per session. Adaptation kräver
minst tjugo användbara, skattade fasta sessioner samt godkänd prediktiv validering.
Se [användarflöde och modellregler](docs/ADAPTIVE_MEDITATION_AUDIO.md),
[editor/API](web/README.md) och [program- och hårdvaruverifiering](docs/MEDITATION_ACCEPTANCE.md).
