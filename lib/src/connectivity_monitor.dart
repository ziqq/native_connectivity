/*
 * Author: Anton Ustinoff <https://github.com/ziqq> | <a.a.ustinoff@gmail.com>
 * Date: 24 December 2025
 */

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show EventChannel;

/// Read-only connectivity status used by the UI.
typedef ConnectivityStatusController = ValueListenable<ConnectivityStatus>;

/// An observation of the application's network path by the platform.
enum ConnectivityPathStatus {
  /// The platform has not confirmed whether a path is available.
  unknown,

  /// A network path is available. Repeated events can identify a different path.
  satisfied,

  /// The platform has confirmed that no network path is available.
  unsatisfied,
}

/// Connectivity status displayed by the UI.
enum ConnectivityStatus {
  /// No offline condition has been confirmed.
  online,

  /// The platform confirmed a sustained loss of the network path.
  offline,
}

/// Publishes network loss and accepts real API responses as evidence of connectivity.
abstract interface class IConnectivityMonitor {
  /// The status displayed by the connectivity banner.
  ConnectivityStatusController get controller;

  /// The generation of the currently observed path.
  int get networkGeneration;

  /// Reports a real HTTP response if [generation] still identifies the current path.
  void reportHTTPResponse(int generation);

  /// Starts listening to platform events once.
  ///
  /// [onError] receives observation errors after the path becomes unknown.
  void start({void Function(Object error, StackTrace stackTrace)? onError});

  /// Releases the event subscription and pending banner update.
  void dispose();
}

/// Updates the banner from platform events and responses to ordinary API requests.
///
/// The owner calls [start] to subscribe and [dispose] to release the subscription.
/// Until the platform confirms a loss, [controller] stays [ConnectivityStatus.online].
final class ConnectivityMonitor implements IConnectivityMonitor {
  /// Creates a monitor from ordered platform path changes.
  ConnectivityMonitor({required this._pathChanges});

  /// The app-wide monitor. Its platform stream is opened by [start].
  static final ConnectivityMonitor instance = ConnectivityMonitor(
    pathChanges: switch ((kIsWeb, defaultTargetPlatform)) {
      (false, .android || .iOS || .macOS || .linux || .windows) =>
        const EventChannel('github.com/ziqq/connectivity_monitor').receiveBroadcastStream().map<ConnectivityPathStatus>(
          (event) => switch (event) {
            'satisfied' => .satisfied,
            'unsatisfied' => .unsatisfied,
            _ => .unknown,
          },
        ),
      _ => const Stream<ConnectivityPathStatus>.empty(),
    },
  );

  /// Time allowed for the platform to switch paths before showing the banner.
  static const Duration _delay = Duration(milliseconds: 500);

  final Stream<ConnectivityPathStatus> _pathChanges;

  @override
  ConnectivityStatusController get controller => _controller;
  final ValueNotifier<ConnectivityStatus> _controller = ValueNotifier<ConnectivityStatus>(.online);

  @override
  int get networkGeneration => _networkGeneration;
  int _networkGeneration = 0;

  /// Subscription to platform path changes.
  StreamSubscription<ConnectivityPathStatus>? _subscription;

  /// Last platform observation, including a loss superseded by a real HTTP response.
  ConnectivityPathStatus _path = .unknown;

  /// Timer used to delay the confirmation of a network loss before updating the controller.
  Timer? _timer;

  bool _disposed = false;

  @override
  void start({void Function(Object error, StackTrace stackTrace)? onError}) {
    if (_disposed || _subscription != null) return;
    _subscription = _pathChanges.listen(
      _onPathChanged,
      onDone: () => _onPathChanged(.unknown),
      onError: (Object error, StackTrace stackTrace) {
        _onPathChanged(.unknown);
        onError?.call(error, stackTrace);
      },
    );
  }

  void _onPathChanged(ConnectivityPathStatus path) {
    // A replacement path can also be satisfied. Repeated loss events describe the same outage.
    if (path == _path && path != .satisfied) return;
    _path = path;
    _networkGeneration++;
    _timer?.cancel();

    if (path == .unsatisfied) {
      _timer = Timer(_delay, () => _controller.value = .offline);
    } else {
      _controller.value = .online;
    }
  }

  @override
  void reportHTTPResponse(int generation) {
    if (_disposed || generation != _networkGeneration) return;
    _controller.value = .online;
    _timer?.cancel();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _controller.dispose();
    _subscription?.cancel().ignore();
  }
}
