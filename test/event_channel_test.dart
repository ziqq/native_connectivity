import 'package:flutter/services.dart' show MethodChannel, StandardMethodCodec, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:native_connectivity/native_connectivity.dart';

void main() {
  testWidgets('decodes native observations and confirms loss after 500 ms', (tester) async {
    const channel = MethodChannel('github.com/ziqq/connectivity_monitor');
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> emit(String status) async {
      await messenger.handlePlatformMessage(channel.name, codec.encodeSuccessEnvelope(status), null);
      await tester.pump();
    }

    final monitor = ConnectivityMonitor.instance
      ..start()
      ..start();
    addTearDown(monitor.dispose);
    await tester.pump();
    expect(methods, ['listen']);

    await emit('satisfied');
    final availableGeneration = monitor.networkGeneration;
    expect(availableGeneration, greaterThan(0));
    await emit('unsatisfied');
    await tester.pump(const Duration(milliseconds: 499));
    expect(monitor.controller.value, ConnectivityStatus.online);

    await emit('unsatisfied');
    await tester.pump(const Duration(milliseconds: 1));
    expect(monitor.controller.value, ConnectivityStatus.offline);
    expect(monitor.networkGeneration, availableGeneration + 1);

    // An unrecognized status maps to an unknown path and clears the confirmed loss.
    await emit('unrecognized');
    expect(monitor.controller.value, ConnectivityStatus.online);
    expect(monitor.networkGeneration, availableGeneration + 2);

    monitor.dispose();
    await tester.pump();
    expect(methods, ['listen', 'cancel']);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
