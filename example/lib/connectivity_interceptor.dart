import 'package:dio/dio.dart';
import 'package:native_connectivity/native_connectivity.dart';

/// Reports real Dio transport responses for the path on which the request started.
final class ConnectivityInterceptor extends Interceptor {
  ConnectivityInterceptor(this._monitor);

  static const _generationKey = 'native_connectivity.networkGeneration';

  final IConnectivityMonitor _monitor;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_generationKey] = _monitor.networkGeneration;
    handler.next(options);
  }

  @override
  void onResponse(Response<Object?> response, ResponseInterceptorHandler handler) {
    _report(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response case Response<Object?> response) _report(response);
    handler.next(err);
  }

  void _report(Response<Object?> response) {
    if ((response.requestOptions.extra[_generationKey], response.statusCode) case (int generation, int status)
        when status >= 100 && status <= 599) {
      _monitor.reportHTTPResponse(generation);
    }
  }
}
