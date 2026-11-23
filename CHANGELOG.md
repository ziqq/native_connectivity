# Changelog

## 0.0.2
- **FIXED**: Android and Windows keep monitoring the network after a transient callback registration failure by retrying
  once on the same subscription. Canceling the subscription also cancels the pending retry.
- **FIXED**: The Dio example captures the network path when the transport sends the request. Real response headers for
  the current path can clear the offline banner even if decoding the response body fails.

## 0.0.1
- **ADDED**: Native network path observation on Android, iOS, macOS, Linux, and Windows, with offline banner state
  and recovery from current-path HTTP responses.
- **ADDED**: A runnable example with Dio and `package:http` adapters.
