import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const scenario = String.fromEnvironment('ANDROID_PATH_TEST');

  testWidgets('recovers the same cold-start subscription after a route becomes available', (tester) async {
    final monitor = ConnectivityMonitor.instance..start();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(ConnectivityExample(monitor: monitor));
    final banner = find.text('No internet connection');

    // The host confirms the device has no default route before launching this test.
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.networkGeneration, 0);
    expect(banner, findsNothing);
    debugPrint('android_network_paths_test: restore');

    await _waitForPath(tester, monitor, after: 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(banner, findsNothing);
  }, skip: !Platform.isAndroid || scenario != 'cold-start');

  testWidgets('keeps the banner hidden during Wi-Fi to cellular handoff', (tester) async {
    final monitor = ConnectivityMonitor.instance..start();
    addTearDown(monitor.dispose);
    final states = <ConnectivityStatus>[];
    monitor.controller.addListener(() => states.add(monitor.controller.value));
    await tester.pumpWidget(ConnectivityExample(monitor: monitor));
    final banner = find.text('No internet connection');

    await _waitForPath(tester, monitor, after: 0);
    final wifiGeneration = monitor.networkGeneration;
    expect(banner, findsNothing);
    debugPrint('android_network_paths_test: switch-to-cellular');

    await _waitForPath(tester, monitor, after: wifiGeneration);
    await tester.pump(const Duration(milliseconds: 600));
    expect(states, isNot(contains(ConnectivityStatus.offline)));
    expect(banner, findsNothing);
  }, skip: !Platform.isAndroid || scenario != 'handoff');
}

Future<void> _waitForPath(WidgetTester tester, IConnectivityMonitor monitor, {required int after}) async {
  for (var attempt = 0; attempt < 150 && monitor.networkGeneration <= after; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(monitor.networkGeneration, greaterThan(after));
  expect(monitor.controller.value, ConnectivityStatus.online);
}
