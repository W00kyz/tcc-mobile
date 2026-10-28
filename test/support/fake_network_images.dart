import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Makes every `NetworkImage` load inside [body] resolve to [bytes] instead
/// of hitting the real (fake-400-under-`flutter_test`) network — installed
/// via Flutter's own `debugNetworkImageHttpClientProvider` test hook. Reset
/// happens in a `finally`, synchronously before this function returns —
/// `addTearDown` runs too late here: the binding asserts every debug
/// variable is back to null right after the test body returns.
Future<void> withMockedNetworkImages(
  Uint8List bytes,
  Future<void> Function() body,
) async {
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(bytes);
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._bytes);
  final Uint8List _bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._bytes);
  final Uint8List _bytes;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._bytes);
  final Uint8List _bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
