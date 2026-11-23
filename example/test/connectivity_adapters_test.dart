import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/connectivity_http_client_adapter.dart';
import 'package:native_connectivity_example/connectivity_middleware.dart';

void main() {
  late StreamController<ConnectivityPathStatus> events;
  late ConnectivityMonitor monitor;
  late Uri endpoint;
  late int requests;

  setUp(() async {
    events = StreamController<ConnectivityPathStatus>(sync: true);
    monitor = ConnectivityMonitor(pathChanges: events.stream)..start();
    addTearDown(events.close);
    addTearDown(monitor.dispose);
    events.add(.satisfied);

    requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    endpoint = Uri(scheme: 'http', host: server.address.address, port: server.port);
    server.listen((request) async {
      ++requests;
      switch (request.uri.path) {
        case '/broken-json':
          request.response.headers.contentType = ContentType.json;
          request.response.write('{broken');
        case '/unavailable':
          request.response.statusCode = HttpStatus.serviceUnavailable;
        default:
          request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
  });

  Future<void> losePath() async {
    events.add(.unsatisfied);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(monitor.controller.value, ConnectivityStatus.offline);
  }

  Dio createDio() {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    return dio..httpClientAdapter = ConnectivityHttpClientAdapter(dio.httpClientAdapter, monitor);
  }

  for (final useDio in [false, true]) {
    test('${useDio ? 'Dio' : 'HTTP'} restores connectivity after a genuine 503', () async {
      await losePath();
      final uri = endpoint.resolve('/unavailable');

      if (useDio) {
        final client = createDio();
        await expectLater(
          client.getUri<Object?>(uri),
          throwsA(isA<DioException>().having((error) => error.response?.statusCode, 'status', 503)),
        );
      } else {
        final client = ConnectivityMiddleware(http.Client(), monitor);
        addTearDown(client.close);
        expect((await client.get(uri)).statusCode, HttpStatus.serviceUnavailable);
      }

      expect(requests, 1);
      expect(monitor.controller.value, ConnectivityStatus.online);
    });
  }

  test('Dio records received headers when JSON decoding fails', () async {
    final dio = createDio();
    await losePath();

    await expectLater(
      dio.getUri<Object?>(endpoint.resolve('/broken-json')),
      throwsA(isA<DioException>().having((error) => error.error, 'error', isA<FormatException>())),
    );

    expect(requests, 1);
    expect(monitor.controller.value, ConnectivityStatus.online);
  });

  test('Dio captures the path after a deferred request reaches the transport', () async {
    final arrived = Completer<void>();
    final resume = Completer<void>();
    final dio = createDio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          arrived.complete();
          await resume.future;
          handler.next(options);
        },
      ),
    );
    final request = dio.getUri<Object?>(endpoint);
    try {
      await arrived.future;
      expect(requests, 0);
      await losePath();
    } finally {
      resume.complete();
    }

    expect((await request).statusCode, HttpStatus.noContent);
    expect(requests, 1);
    expect(monitor.controller.value, ConnectivityStatus.online);
  });
}
