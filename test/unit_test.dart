/*
 * Author: Anton Ustinoff <https://github.com/ziqq> | <a.a.ustinoff@gmail.com>
 * Date: 08 May 2026
 */

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:native_connectivity/native_connectivity.dart';

const _confirmationWindow = Duration(milliseconds: 500);

void main() => group('ConnectivityMonitor -', () {
  late StreamController<ConnectivityPathStatus> events;
  late ConnectivityMonitor monitor;
  late List<(Object, StackTrace)> errors;

  setUp(() {
    events = StreamController<ConnectivityPathStatus>(sync: true);
    errors = [];
    monitor = ConnectivityMonitor(pathChanges: events.stream)
      ..start(onError: (error, stackTrace) => errors.add((error, stackTrace)));
    addTearDown(events.close);
    addTearDown(monitor.dispose);
  });

  test('keeps the banner hidden until the platform confirms a loss', () async {
    expect(monitor.controller.value, ConnectivityStatus.online);
    events.add(.unknown);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.online);

    events.add(.unsatisfied);
    expect(monitor.controller.value, ConnectivityStatus.online);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.offline);

    events.add(.satisfied);
    expect(monitor.controller.value, ConnectivityStatus.online);
  });

  test('keeps the banner hidden through a fast handoff', () async {
    events.add(.satisfied);
    final oldGeneration = monitor.networkGeneration;

    events
      ..add(.unsatisfied)
      ..add(.satisfied);
    await Future<void>.delayed(_confirmationWindow);

    expect(monitor.controller.value, ConnectivityStatus.online);
    expect(monitor.networkGeneration, greaterThan(oldGeneration));
  });

  test('treats a replacement path as new even when both paths are available', () {
    events.add(.satisfied);
    final generation = monitor.networkGeneration;
    events.add(.satisfied);

    expect(monitor.networkGeneration, greaterThan(generation));
  });

  test('ignores a reply from the previous path and accepts a reply on the current path', () async {
    events.add(.satisfied);
    final oldGeneration = monitor.networkGeneration;
    events.add(.unsatisfied);

    monitor.reportHTTPResponse(oldGeneration);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.offline);

    monitor.reportHTTPResponse(monitor.networkGeneration);
    expect(monitor.controller.value, ConnectivityStatus.online);
  });

  test('a real response cancels pending loss and a duplicate event does not show it again', () async {
    events.add(.unsatisfied);
    monitor.reportHTTPResponse(monitor.networkGeneration);
    events.add(.unsatisfied);
    await Future<void>.delayed(_confirmationWindow);

    expect(monitor.controller.value, ConnectivityStatus.online);
  });

  test('a response preserves a new loss emitted by a status listener', () async {
    events.add(.unsatisfied);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.offline);

    monitor.controller.addListener(() {
      if (monitor.controller.value != .online) return;
      events
        ..add(.satisfied)
        ..add(.unsatisfied);
    });
    monitor.reportHTTPResponse(monitor.networkGeneration);
    expect(monitor.controller.value, ConnectivityStatus.online);

    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.offline);
  });

  test('reports observation errors and clears the banner when the stream closes', () async {
    final error = PlatformException(code: 'observation_failed');
    final stackTrace = StackTrace.current;
    events
      ..add(.unsatisfied)
      ..addError(error, stackTrace);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.online);
    expect(errors, [(error, stackTrace)]);

    events.add(.unsatisfied);
    await Future<void>.delayed(_confirmationWindow);
    expect(monitor.controller.value, ConnectivityStatus.offline);

    await events.close();
    expect(monitor.controller.value, ConnectivityStatus.online);
  });

  test('starts once and releases the subscription and pending loss on dispose', () async {
    monitor.start();
    events.add(.unsatisfied);
    final generation = monitor.networkGeneration;
    monitor
      ..dispose()
      ..reportHTTPResponse(generation);
    await Future<void>.delayed(_confirmationWindow);

    expect(events.hasListener, isFalse);
    expect(monitor.controller.value, ConnectivityStatus.online);
  });
});
