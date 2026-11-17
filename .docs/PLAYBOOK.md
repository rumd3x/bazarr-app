# Playbook

- Setup: `flutter pub get`
- Analyze/test: `flutter analyze && flutter test`
- Debug build: `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --debug` (JDK 25 breaks Gradle); then `(cd android && ./gradlew --stop)`.
- Icons: `dart run flutter_launcher_icons`; Play graphics: `python3 scripts/generate_play_assets.py`.
- Release signing and Play publishing follow the same Gradle/`key.properties` contract as sonarr-app (`updateVersion` task in `android/build.gradle.kts`).
- Screenshots: take manually in demo mode and save in `assets/images/screenshots/`.
- Emulator: use the Bazarr-specific AVD `bazarr_pixel` (`~/.android/avd/bazarr_pixel.avd`, cloned from the sonarr_pixel config, Android 35). Start with `~/Android/Sdk/emulator/emulator -avd bazarr_pixel -no-snapshot`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk` and launch `com.rumd3x.bazarr`.
- Screenshots (taken in demo mode on `bazarr_pixel`, 1080x2400) go to `assets/images/screenshots/NN-name.png`: 01 setup, 02 series, 03 series detail, 04 episode, 05 manual search, 06 movies, 07 history, 08 jobs, 09 more. Capture with `adb exec-out screencap -p`. The emulator renders lazily: after a tap, send a tiny `adb shell input swipe` nudge and wait before capturing, or the frame may be stale.
