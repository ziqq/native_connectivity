import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const verifyNetworkSwitch = bool.fromEnvironment('VERIFY_NETWORK_SWITCH');

  testWidgets('accepts an Android subscription without requiring an initial path', (_) async {
    const channel = MethodChannel('github.com/ziqq/connectivity_monitor');
    await channel.invokeMethod<void>('listen');
    await channel.invokeMethod<void>('cancel');
  }, skip: !Platform.isAndroid || verifyNetworkSwitch);

  testWidgets('receives a native path observation', (_) async {
    const channel = EventChannel('github.com/ziqq/connectivity_monitor');
    final event = await channel.receiveBroadcastStream().timeout(const Duration(seconds: 10)).first;
    final statuses = ['satisfied', 'unsatisfied', if (Platform.isIOS || Platform.isMacOS) 'unknown'];
    expect(event, verifyNetworkSwitch ? 'satisfied' : isIn(statuses));
  }, skip: Platform.isAndroid && !verifyNetworkSwitch);

  testWidgets('clears the offline banner after a real route recovery', (tester) async {
    final monitor = ConnectivityMonitor.instance..start();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(ConnectivityExample(monitor: monitor));

    final offlineBanner = find.text('No internet connection');
    await _waitFor(tester, () => monitor.networkGeneration > 0);
    expect(offlineBanner, findsNothing);
    debugPrint('native_connectivity_test: disconnect');

    await _waitFor(tester, () => offlineBanner.evaluate().isNotEmpty);
    debugPrint('native_connectivity_test: reconnect');

    await _waitFor(tester, () => offlineBanner.evaluate().isEmpty);
    expect(find.text('Send request'), findsOneWidget);
  }, skip: !verifyNetworkSwitch);
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 150 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue);
}
