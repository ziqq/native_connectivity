# Native Connectivity Example

Run `flutter pub get` in this directory and select a supported device with `flutter run -d <device>`.

Disconnect and reconnect the device's network to see the banner respond while the app stays open. Choose **Dio** or
**HTTP**, enter a URL, and select **Send request** to see the response or transport error. The example sends a request
only when you select the button.

- [Dio adapter](lib/connectivity_http_client_adapter.dart) captures the path at send time and reports headers before decoding the response body.
  Place it on a transport that returns real responses when assembling a client with caching or synthetic responses.
- [HTTP middleware](lib/connectivity_middleware.dart) wraps the actual `package:http` client and reports a response
  as soon as its headers arrive.

Both adapters record the path generation before transport and report it with the response. A server response such as
`503` keeps its HTTP meaning while supplying evidence that the server answered.

Run `flutter test` here for the UI and loopback transport tests. On a desktop with a default network, run the native
channel smoke test with the matching device identifier.

```sh
flutter test integration_test/native_connectivity_test.dart -d macos
```

On a test device, add `--dart-define=VERIFY_NETWORK_SWITCH=true` to verify banner recovery. Disconnect the network
when the test prints `native_connectivity_test: disconnect`, then reconnect at `native_connectivity_test: reconnect`.
The test checks both transitions within the same running app.
