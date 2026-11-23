import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/connectivity_interceptor.dart';
import 'package:native_connectivity_example/connectivity_middleware.dart';

void main() {
  for (final useDio in [false, true]) {
    test('${useDio ? 'Dio' : 'HTTP'} restores connectivity after a genuine 503', () async {
      final events = StreamController<ConnectivityPathStatus>(sync: true);
      final monitor = ConnectivityMonitor(pathChanges: events.stream)..start();
      addTearDown(events.close);
      addTearDown(monitor.dispose);

      events.add(.unsatisfied);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(monitor.controller.value, ConnectivityStatus.offline);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      final uri = Uri(scheme: 'http', host: server.address.address, port: server.port);

      if (useDio) {
        final client = Dio()..interceptors.add(ConnectivityInterceptor(monitor));
        addTearDown(() => client.close(force: true));
        await expectLater(
          client.getUri<Object?>(uri),
          throwsA(isA<DioException>().having((error) => error.response?.statusCode, 'status', 503)),
        );
      } else {
        final client = ConnectivityMiddleware(http.Client(), monitor);
        addTearDown(client.close);
        expect((await client.get(uri)).statusCode, HttpStatus.serviceUnavailable);
      }

      expect(monitor.controller.value, ConnectivityStatus.online);
    });
  }
}
