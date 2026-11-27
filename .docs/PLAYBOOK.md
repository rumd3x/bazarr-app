# Playbook

- Setup: `flutter pub get`
- Analyze/test: `flutter analyze && flutter test`
- Debug build: `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --debug` (JDK 25 breaks Gradle); then `(cd android && ./gradlew --stop)`.
- Icons: `dart run flutter_launcher_icons`; Play graphics: `python3 scripts/generate_play_assets.py`.
- Release signing and Play publishing follow the same Gradle/`key.properties` contract as sonarr-app (`updateVersion` task in `android/build.gradle.kts`).
- Keep the public support email and website in `android/app/src/main/play/contact-email.txt` and `contact-website.txt`. Jenkins checks for a nonblank email before building when listing sync runs.
- Jenkins runs `./gradlew` from the checkout's `android/` directory. Fresh checkouts include the Gradle 8.14 wrapper. Set `flutter.sdk` in `android/local.properties` before invoking Gradle directly.
- The pre-release version in `pubspec.yaml` starts at `0.0.0+0` so the first pipeline build uses `0.0.1+1`.
- Screenshots: take manually in demo mode and save in `assets/images/screenshots/`.
- Emulator: use the Bazarr-specific AVD `bazarr_pixel` (`~/.android/avd/bazarr_pixel.avd`, cloned from the sonarr_pixel config, Android 35). Start with `~/Android/Sdk/emulator/emulator -avd bazarr_pixel -no-snapshot`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk` and launch `com.rumd3x.bazarr`.
- Capture the blank setup screen before entering demo mode on `bazarr_pixel`. Save the 1080×2400 images to `assets/images/screenshots/NN-name.png`. The gallery shows 01 setup, 02 series, 03 series detail, 04 episode, 05 manual search results, 06 movies, 07 history, 08 jobs, 09 more, 10 subtitle tools, 11 subtitle sync options, and 12 subtitle preview. Capture with `adb exec-out screencap -p` after the screen settles and verify the frame before replacing the gallery image.
