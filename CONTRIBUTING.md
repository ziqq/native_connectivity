# Contributing

Install the Flutter and Just versions in `mise.toml`, then run `just precommit` from the package root.

Use the [example](example/README.md) to verify a platform change. Check that losing the active route shows the offline
banner and restoring it clears the banner in the same app session. Verify that an ordinary HTTP response still passes
through with its original status and that a response from an older route cannot clear a current loss.

A publication tag must match the version in `pubspec.yaml` and the first release heading in `CHANGELOG.md`.
