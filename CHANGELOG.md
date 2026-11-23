# Changelog

## Unreleased
- **FIXED**: Android and Windows retry a failed network callback registration once while the subscription is active.
- **FIXED**: The Dio example reports real response headers before decoding and captures the path when the request is sent.

## 0.0.1
- **ADDED**: Native network path observation on Android, iOS, macOS, Linux, and Windows, with offline banner state
  and recovery from current-path HTTP responses.
- **ADDED**: A runnable example with Dio and `package:http` adapters.
