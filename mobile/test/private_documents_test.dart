import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/api/api_endpoints.dart';

class AuditAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  int statusCode = 200;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromBytes([1, 2, 3], statusCode);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Trust is limited to exact API origin', () {
    final base = Uri.parse(ApiEndpoints.me);
    expect(ApiEndpoints.isTrustedUri(base), isTrue);
    for (final uri in [
      base.replace(host: 'outside.example'),
      base.replace(host: '${base.host}.outside.example'),
      base.replace(userInfo: 'synthetic'),
      base.replace(port: base.port + 1),
      base.replace(scheme: base.scheme == 'https' ? 'http' : 'https'),
    ]) {
      expect(ApiEndpoints.isTrustedUri(uri), isFalse, reason: uri.toString());
    }
  });

  test('External document rejected before any request or token refresh',
      () async {
    final adapter = AuditAdapter();
    var refreshes = 0;
    final api = ApiClient(
        token: 'synthetic-token',
        httpClientAdapter: adapter,
        refreshToken: () async {
          refreshes++;
          return 'synthetic-new-token';
        });
    await expectLater(api.downloadBytes('https://outside.example/identity.jpg'),
        throwsArgumentError);
    expect(adapter.lastRequest, isNull);
    expect(refreshes, 0);
  });

  test('Authenticated download includes token and does not follow redirects',
      () async {
    final adapter = AuditAdapter();
    final api = ApiClient(token: 'synthetic-token', httpClientAdapter: adapter);
    final url = ApiEndpoints.resolve('/api/users/owner/kyc/id_card');
    expect(await api.downloadBytes(url), [1, 2, 3]);
    expect(adapter.lastRequest!.headers['Authorization'],
        'Bearer synthetic-token');
    expect(adapter.lastRequest!.followRedirects, isFalse);
  });

  test('Redirect to external site is never followed', () async {
    final adapter = AuditAdapter()..statusCode = 302;
    final api = ApiClient(token: 'synthetic-token', httpClientAdapter: adapter);
    await expectLater(
        api.downloadBytes(ApiEndpoints.resolve('/api/users/owner/kyc/id_card')),
        throwsA(isA<DioException>()));
    expect(adapter.lastRequest!.followRedirects, isFalse);
  });
}
