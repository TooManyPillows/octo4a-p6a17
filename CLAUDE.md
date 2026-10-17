# octo4a notes

Runs OctoPrint on Android: the app downloads an Alpine Linux bootstrap and runs OctoPrint inside it with proot.

## Layout
- The Gradle project root is `app/`, not the repo root. Build with `cd app && ./gradlew assembleDebug`.
- The bootstrap (Alpine rootfs, OctoPrint venv, proot, `entrypoint.sh`) comes from a separate repo,
  feelfreelinux/octo4a-bootstrap-builder, and is downloaded at install time. `bootstrap-builder/` here
  is an old, unused builder.
- `proot/` holds our patch and build script for the proot bundled in the APK (see `proot/README.md`).

## Build environment
- Needs **JDK 11**. Gradle 7.2 doesn't run on JDK 17+, and `gradle.properties` passes
  `--illegal-access=permit`, which newer JDKs reject. Android Studio's bundled JBR won't work.
- `app/local.properties` needs `sdk.dir` with forward slashes. Backslashes are escapes in properties files.
- Android SDK platform 28, build-tools 30.0.3, NDK 21 (C/C++ libraries in `app/app/src/main/cpp`).
  The proot build script uses NDK 27.

## Deliberate choices, don't "fix" these without a plan
- **targetSdk stays 28.** At 29+ Android blocks executing files from app data (W^X), which breaks proot.
  Raising it means running proot from `nativeLibraryDir` instead of `bin/` (it honors the `PROOT_LOADER`
  env var), plus PendingIntent mutability flags and foreground service types.
- **CameraX is pinned to 1.0.0** for the Umidigi S2 Lite (see `because(...)` in `build.gradle.kts`).
- **The bundled proot is built for API 21 without `process_vm_*`**, matching the bootstrap's own proot.
  Bionic only has those calls from API 23.
- **Native libraries are packaged extracted** (`useLegacyPackaging`). `installBundledProot()` copies them
  from `nativeLibraryDir`, and it's why 16 KB *zip* alignment (AGP 8.5+) isn't needed. ELF alignment is
  set in `CMakeLists.txt` and the proot script.

## How installation works
- `isBootstrapInstalled` only means the rootfs was extracted. Setup is complete only when
  `files/bootstrap/.setup-complete` exists (or, for installs older than the marker, when the OctoPrint
  config contains `/dev/ttyOcto4a`). `beginInstallation()` finishes setup when it's missing.
- `insertInitialConfig()` merges into OctoPrint's `config.yaml` sections. Never replace whole sections:
  OctoPrint keeps `server.secretKey` and other state there.
- `installBundledProot()` runs after download and on every start. It replaces `bin/proot` and
  `libexec/proot/loader` when they differ from `jniLibs/arm64-v8a/libproot*.so`.

## Debugging on a device (Windows + Git Bash)
- adb lives in `%LOCALAPPDATA%\Android\Sdk\platform-tools` (not on PATH). In Git Bash, set
  `MSYS_NO_PATHCONV=1`, or device paths like `/data/local/tmp` get rewritten to Windows paths.
- App logs are in logcat. Tag `💻` is the app itself, `🐸` is output of commands run in proot.
  OctoPrint's own log is at `/sdcard/Android/data/com.octo4a/files/.octoprint/logs/octoprint.log`, but
  `adb shell` can only sometimes read it (it depends on how the files were created).
- `adb shell run-as com.octo4a` can run proot by hand (`cd files/bootstrap && sh entrypoint.sh root /bin/sh -c ...`),
  **but run-as can't access the app's external storage**. The `/mnt/external` bind then silently fails
  and writes land inside the rootfs instead. Anything touching OctoPrint data has to go through the app.
- Every `adb install` of a new build triggers a Play Protect prompt that someone must tap on the phone.
- `pm clear com.octo4a` gives a true fresh install (removes internal and external app data).

## History and open work
- Fixed (branch `android-11-plus-fixes`): proot failing on arm64 Android 11+ because of tagged pointers
  (`execve("/bin/sh"): Function not implemented`, `ptrace(PEEKDATA): I/O error`), interrupted installs
  never finishing setup, Extensions tab crash, 16 KB page alignment. Tested on a Pixel 6 with Android 17,
  including a print.
- Branch `builds` adds the tested APK in `dist/`. Keep binaries off the fix branch.
- **Open:** Android 12+'s phantom process killer can kill OctoPrint mid-print. Users currently need
  Developer options → "Disable child process restrictions". Idea: show this during setup on API 31+.
- **Open:** upgrading AGP 7.1 / Kotlin 1.4. The big part is moving 14 UI files off
  `kotlinx.android.synthetic` to ViewBinding; Ktor 1.5 → 2.x is breaking.
- Only arm64 gets the bundled proot. 32-bit ARM and x86 don't tag pointers, so they keep the bootstrap's.
- Don't push or open pull requests without asking the repo owner first.
