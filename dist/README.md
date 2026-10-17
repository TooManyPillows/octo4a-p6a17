# octo4a 2.1.0 with Android 11+ fixes (debug build)

`octo4a-2.1.0-android11-fixes-debug.apk` is built from branch `android-11-plus-fixes`
(commit b53187f) and tested on a Pixel 6 with Android 17: fresh install, OctoPrint 1.11.3,
and a print over USB OTG.

- **Debug-signed.** Android won't install it over an official octo4a release (different
  signature). Uninstall that first, which deletes its OctoPrint data.
- Play Protect warns about it because it isn't from a known developer. Choose to install anyway.
- On Android 12+, turn on Developer options → **Disable child process restrictions**, or Android
  may kill OctoPrint during long prints.

Check the download with `sha256sum -c octo4a-2.1.0-android11-fixes-debug.apk.sha256`.
