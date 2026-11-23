# Contributing

Install the Flutter and Just versions in `mise.toml`, then run `just precommit` from the package root.

Use the [example](example/README.md) to verify a platform change. Check that losing the active route shows the offline
banner and restoring it clears the banner in the same app session. Verify that an ordinary HTTP response still passes
through with its original status and that a response from an older route cannot clear a current loss.

Build the example once with `flutter build apk --debug` from `example/` to prepare the Gradle wrapper. Then run
`./gradlew :app:connectedDebugAndroidTest` from `example/android` with one connected Android device that has a default
network. The registration tests inject failures into the example's connectivity service lookup and verify successful
recovery, the retry limit, and cancellation.

Run `bash tool/test-android-path.sh DEVICE cold-start` from the package root to start the example with both radios
disabled and verify recovery in the same session. Run `bash tool/test-android-path.sh DEVICE handoff` with Wi-Fi as the
default network and an active cellular connection to verify the switch between them. Both tests restore the device's
radio settings. The Windows CI regression builds a Debug example with a single injected IP interface registration
failure and verifies that the original subscription recovers.

A publication tag must match the version in `pubspec.yaml` and the first release heading in `CHANGELOG.md`.
