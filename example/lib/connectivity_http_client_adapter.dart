import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:native_connectivity/native_connectivity.dart';

/// Reports response headers for the network path on which Dio sends the request.
final class ConnectivityHttpClientAdapter implements HttpClientAdapter {
  ConnectivityHttpClientAdapter(this._delegate, this._monitor);

  final HttpClientAdapter _delegate;
  final IConnectivityMonitor _monitor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final generation = _monitor.networkGeneration;
    final response = await _delegate.fetch(options, requestStream, cancelFuture);
    if (response.statusCode >= 100 && response.statusCode <= 599) {
      _monitor.reportHTTPResponse(generation);
    }
    return response;
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
}
