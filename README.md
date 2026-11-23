# Native Connectivity

## Description

`native_connectivity` observes the system network path on Android, iOS, macOS, Linux, and Windows.
`ConnectivityMonitor` exposes read-only state for an offline banner and accepts responses to ordinary HTTP requests
as recovery evidence. The app owns the banner and its HTTP client policies.

## Setup

The package requires Dart `>=3.13.5 <4.0.0` and Flutter `>=3.47.7`. Android support starts at API 24. The Apple
implementation uses Swift Package Manager. Its native deployment targets are iOS 13 and macOS 10.15, while the
example app targets iOS 15 and macOS 12 with Flutter 3.47. Flutter registers each implementation through the
[package manifest](pubspec.yaml).

## Show the banner

Start `ConnectivityMonitor.instance` from the app's initialization code after initializing Flutter. Observe
`controller` from the widget that owns the banner. `online` means the banner stays hidden. An available path describes
the platform route. Ordinary API responses provide server-specific evidence.

```dart
import 'package:native_connectivity/native_connectivity.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final connectivity = ConnectivityMonitor.instance..start();

  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<ConnectivityStatus>(
            valueListenable: connectivity.controller,
            builder: (context, status, _) =>
                status == ConnectivityStatus.offline ? const Text('No internet connection') : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}
```

The owner starts a monitor once and calls `dispose()` when the monitor's lifetime ends. Disposal is permanent and
releases the subscription, pending banner update, and listenable. A widget borrowing the app-wide instance manages
only its own listener. Tests and custom owners can supply an ordered `Stream<ConnectivityPathStatus>` using the
`pathChanges` constructor argument.

Pass `onError` to `start()` to forward errors emitted by the observation stream and their stack traces to your own
logger or error handler. The [example](example/lib/main.dart) uses Flutter's `FlutterError.reportError`.
Flutter also reports errors while opening or closing the platform channel through `FlutterError.reportError`.
See the [EventChannel contract](https://api.flutter.dev/flutter/services/EventChannel/receiveBroadcastStream.html).

## How the banner responds

- The banner starts hidden. Android may keep the path unknown when the app starts with no default network because
  the callback reports networks it observes. On Apple platforms, a path that requires a connection counts as unknown.
- A confirmed loss must last **500 ms** before the banner becomes visible. This window gives the platform time to
  switch paths. An available path clears the banner, including after recovery on the same screen.
- A genuine HTTP response for the current path clears the banner and cancels pending loss. A monitor error or a
  closed observation stream returns the monitor to an unknown path and clears the banner.

| Platform | Native observation |
| --- | --- |
| Android | Default network callback. The plugin manifest supplies `ACCESS_NETWORK_STATE`. |
| iOS and macOS | `NWPathMonitor` from Apple's Network framework. |
| Linux | GIO `GNetworkMonitor`, which reports default route availability. |
| Windows | IP Helper notifications for routes and interfaces, checked against the active default routes. |

The shared event channel is `github.com/ziqq/connectivity_monitor`. On other platforms the monitor starts with an
empty stream and the banner stays hidden. A system route is evidence of a path. A response to an ordinary request
provides evidence that the server answered. The monitor sends no network traffic.

## Report ordinary API responses

For an actual network attempt, capture `networkGeneration` before sending. Pass that generation to
`reportHTTPResponse` when a real HTTP response arrives, including an error status such as `503`. Keep ordinary HTTP
error handling for that response. A path replacement advances the generation, even when both paths are available.
A response from the old path cannot hide a loss on the new path. Cache hits, synthetic responses, and transport
failures without HTTP headers carry no evidence of current reachability. Use the [Dio interceptor](example/lib/connectivity_interceptor.dart)
or [HTTP middleware](example/lib/connectivity_middleware.dart) as starting points for your adapters.

## Example

The bundled [example](example/README.md) runs on all five supported platforms. It shows the offline banner and lets you
send a request through either adapter. To run it on your desktop, select the relevant device from `flutter devices`.

```sh
cd example
flutter pub get
flutter run -d macos
```

Run the [monitor tests](test/unit_test.dart) with `flutter test` from the package root, and run `flutter test` inside
`example/` to verify the sample UI and both adapters.
