import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/main.dart';

void main() {
  testWidgets('shows route loss and clears the banner on recovery', (tester) async {
    final events = StreamController<ConnectivityPathStatus>(sync: true);
    final monitor = ConnectivityMonitor(pathChanges: events.stream)..start();
    addTearDown(events.close);
    addTearDown(monitor.dispose);

    await tester.pumpWidget(ConnectivityExample(monitor: monitor));
    expect(find.text('No internet connection'), findsNothing);

    events.add(.unsatisfied);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No internet connection'), findsOneWidget);

    events.add(.satisfied);
    await tester.pump();
    expect(find.text('No internet connection'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Send request'), findsOneWidget);
  });
}
