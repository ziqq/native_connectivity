import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:native_connectivity/native_connectivity.dart';
import 'package:native_connectivity_example/connectivity_http_client_adapter.dart';
import 'package:native_connectivity_example/connectivity_middleware.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final monitor = ConnectivityMonitor.instance
    ..start(
      onError: (error, stackTrace) => FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace, library: 'native_connectivity'),
      ),
    );
  runApp(ConnectivityExample(monitor: monitor));
}

enum _Transport { dio, http }

/// Demonstrates native status and user-initiated requests through either adapter.
class ConnectivityExample extends StatefulWidget {
  const ConnectivityExample({required this.monitor, super.key});

  final IConnectivityMonitor monitor;

  @override
  State<ConnectivityExample> createState() => _ConnectivityExampleState();
}

class _ConnectivityExampleState extends State<ConnectivityExample> {
  static const _requestTimeout = Duration(seconds: 10);

  final _url = TextEditingController(text: 'https://example.com');
  late final _dio = _createDio();
  late final _http = ConnectivityMiddleware(http.Client(), widget.monitor);

  _Transport _transport = .dio;
  Future<String>? _result;

  Dio _createDio() {
    final dio = Dio(
      BaseOptions(connectTimeout: _requestTimeout, receiveTimeout: _requestTimeout, validateStatus: (_) => true),
    );
    return dio..httpClientAdapter = ConnectivityHttpClientAdapter(dio.httpClientAdapter, widget.monitor);
  }

  @override
  void dispose() {
    _url.dispose();
    _dio.close(force: true);
    _http.close();
    super.dispose();
  }

  void _send() {
    final uri = Uri.tryParse(_url.text.trim());
    setState(() {
      _result = uri != null && uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https')
          ? _request(uri, _transport)
          : Future.value('Enter a valid HTTP or HTTPS URL.');
    });
  }

  Future<String> _request(Uri uri, _Transport transport) async {
    try {
      final status = switch (transport) {
        .dio => (await _dio.getUri<Object?>(uri)).statusCode,
        .http => (await _http.get(uri).timeout(_requestTimeout)).statusCode,
      };
      return 'HTTP $status';
    } on Object catch (error) {
      return 'Request failed. $error';
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Native Connectivity',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: Scaffold(
      appBar: AppBar(title: const Text('Native Connectivity')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ValueListenableBuilder<ConnectivityStatus>(
                valueListenable: widget.monitor.controller,
                builder: (context, status, _) => switch (status) {
                  .online => const ListTile(leading: Icon(Icons.wifi), title: Text('Online')),
                  .offline => Semantics(
                    liveRegion: true,
                    child: ListTile(
                      tileColor: Theme.of(context).colorScheme.errorContainer,
                      leading: const Icon(Icons.wifi_off),
                      title: const Text('No internet connection'),
                    ),
                  ),
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Request URL', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_Transport>(
                segments: const [
                  ButtonSegment(value: .dio, label: Text('Dio')),
                  ButtonSegment(value: .http, label: Text('HTTP')),
                ],
                selected: {_transport},
                onSelectionChanged: (selection) => setState(() => _transport = selection.single),
              ),
              const SizedBox(height: 16),
              FutureBuilder<String>(
                future: _result,
                builder: (context, snapshot) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton(
                      onPressed: snapshot.connectionState == .waiting ? null : _send,
                      child: const Text('Send request'),
                    ),
                    if (snapshot.connectionState == .waiting) const LinearProgressIndicator(),
                    if (snapshot.data case String result) SelectableText(result),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
