import 'package:http/http.dart' as http;
import 'package:native_connectivity/native_connectivity.dart';

/// Wraps the real HTTP transport and reports a response as soon as headers arrive.
final class ConnectivityMiddleware extends http.BaseClient {
  ConnectivityMiddleware(this._client, this._monitor);

  final http.Client _client;
  final IConnectivityMonitor _monitor;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _monitor.networkGeneration;
    final response = await _client.send(request);
    if (response.statusCode >= 100 && response.statusCode <= 599) {
      _monitor.reportHTTPResponse(generation);
    }
    return response;
  }

  @override
  void close() => _client.close();
}
