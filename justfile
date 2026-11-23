# Resolve dependencies for the package and its example.
get:
    flutter pub get
    cd example && flutter pub get

# Verify Dart formatting, including the example and desktop smoke test.
format-check:
    dart format --line-length=120 --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test

# Analyze the package and example.
analyze:
    flutter analyze --no-pub
    cd example && flutter analyze --no-pub

# Run monitor, example UI, and HTTP adapter tests.
test:
    flutter test --no-pub
    cd example && flutter test --no-pub

# Run the package's local CI checks.
precommit: get format-check analyze test
