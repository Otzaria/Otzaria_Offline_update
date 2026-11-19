import 'dart:convert';

import 'package:crypto/crypto.dart';

final _encoder = JsonUtf8Encoder(null, null, 4 * 1024);

void writeReportJson(Object? value, Sink<List<int>> sink) {
  final output = _CloseOnceSink(sink);
  try {
    _encoder.startChunkedConversion(output)
      ..add(value)
      ..close();
  } catch (_) {
    try {
      output.close();
    } catch (_) {
      // כשל בסגירה לא יסתיר את שגיאת הקידוד המקורית.
    }
    rethrow;
  }
}

int reportJsonByteLength(Object? value) {
  final sink = _ByteCountSink();
  writeReportJson(value, sink);
  return sink.length;
}

String hashReportJson(String prefix, Object? value) {
  late Digest digest;
  final result = ChunkedConversionSink<Digest>.withCallback((digests) {
    digest = digests.single;
  });
  final sink = sha256.startChunkedConversion(result)..add(utf8.encode(prefix));
  writeReportJson(value, sink);
  return digest.toString();
}

class _ByteCountSink implements Sink<List<int>> {
  int length = 0;

  @override
  void add(List<int> bytes) => length += bytes.length;

  @override
  void close() {}
}

class _CloseOnceSink implements Sink<List<int>> {
  _CloseOnceSink(this._sink);

  final Sink<List<int>> _sink;
  bool _closed = false;

  @override
  void add(List<int> bytes) => _sink.add(bytes);

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _sink.close();
  }
}
