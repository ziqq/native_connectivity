import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recovers on the same Windows subscription after a partial registration failure', (_) async {
    const channel = EventChannel('github.com/ziqq/connectivity_monitor');
    final receivedPath = Completer<void>();
    final observations = <Object?>[];
    final subscription = channel.receiveBroadcastStream().listen((Object? event) {
      observations.add(event);
      if (!receivedPath.isCompleted) receivedPath.complete();
    }, onError: (Object error) => observations.add(error));
    addTearDown(subscription.cancel);

    await receivedPath.future.timeout(const Duration(seconds: 10));

    expect(observations.whereType<PlatformException>(), hasLength(1));
    expect(
      observations.first,
      isA<PlatformException>()
          .having((error) => error.code, 'code', 'network_callback_failed')
          .having((error) => error.details, 'Win32 ERROR_RETRY', 1237),
    );
    expect(observations[1], isIn(['satisfied', 'unsatisfied']));
  }, skip: !Platform.isWindows);
}
