import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:error_reports_manager/src/report_json.dart';
import 'package:test/test.dart';

void main() {
  group('report JSON', () {
    final samples = <String, Object?>{
      'Unicode and escapes': {
        'עברית 🚀': 'שלום\n\t\r\b\f\u0000"\\',
        'surrogates': '\ud800 x \udfff \ud83d\ude80',
      },
      'nested insertion order': {
        'z': [null, true, false, -0.0, 1.25, 1e30],
        'a': {
          'second': {'y': 2, 'x': 1},
          'first': <Object?>[],
        },
      },
      'null': null,
      'empty map': <String, Object?>{},
    };
    for (final sample in samples.entries) {
      test('${sample.key}: length and hash match the previous encoder', () {
        final json = jsonEncode(sample.value);
        final expected = utf8.encode(json);
        const prefix = 'https://otzaria.org/עברית/🚀\n';

        expect(reportJsonByteLength(sample.value), expected.length);
        expect(hashReportJson(prefix, sample.value),
            sha256.convert(utf8.encode('$prefix$json')).toString());
      });
    }

    for (final size in [4095, 4096, 4097]) {
      test('counts $size bytes across the encoder buffer boundary', () {
        final value = 'a' * (size - 2);
        final sink = _CountingSink();
        writeReportJson(value, sink);

        expect(sink.length, size);
        expect(sink.largestChunk, lessThanOrEqualTo(4096));
        expect(sink.chunks, size <= 4096 ? 1 : 2);
        expect(sink.closes, 1);
        expect(reportJsonByteLength(value), size);
      });
    }

    test('size comparisons keep an inclusive limit and count UTF-8 bytes', () {
      const limit = 6;
      expect(reportJsonByteLength('אב'), limit);
      expect(reportJsonByteLength('אב') > limit, isFalse);
      expect(reportJsonByteLength('אבa') > limit, isTrue);
      expect(reportJsonByteLength('אa') > limit, isFalse);
    });

    test('large JSON streams in bounded chunks with identical bytes and hash',
        () {
      final value = {'errorLog': 'אב🚀\u0000' * (128 * 1024)};
      final expected = utf8.encode(jsonEncode(value));
      final sink = _CountingSink();
      writeReportJson(value, sink);

      expect(expected.length, greaterThan(1024 * 1024));
      expect(expected.length, lessThan(2 * 1024 * 1024));
      expect(sink.chunks, greaterThan(1));
      expect(sink.largestChunk, lessThanOrEqualTo(4096));
      expect(sink.length, expected.length);
      expect(sink.closes, 1);
      expect(reportJsonByteLength(value), expected.length);
      expect(
          hashReportJson('endpoint\n', value),
          sha256
              .convert(utf8.encode('endpoint\n${jsonEncode(value)}'))
              .toString());
    });

    test('counting still rejects an unsupported value after a large prefix',
        () {
      final value = ['a' * 65536, Object()];
      final error = throwsA(isA<JsonUnsupportedObjectError>());
      expect(() => jsonEncode(value), error);
      expect(() => reportJsonByteLength(value), error);
      expect(() => hashReportJson('endpoint\n', value), error);
    });

    test('counting still rejects non-finite numbers and cycles', () {
      final cycle = <Object?>[];
      cycle.add(cycle);
      for (final value in [double.nan, cycle]) {
        expect(() => reportJsonByteLength(value),
            throwsA(isA<JsonUnsupportedObjectError>()));
      }
    });

    test('encoding failure closes the sink without masking the original error',
        () {
      for (final closeError in [null, StateError('close failed')]) {
        final sink = _CountingSink(closeError: closeError);
        expect(() => writeReportJson(Object(), sink),
            throwsA(isA<JsonUnsupportedObjectError>()));
        expect(sink.closes, 1);
      }
    });

    test('a close failure closes the sink only once', () {
      final error = StateError('close failed');
      final sink = _CountingSink(closeError: error);
      expect(() => writeReportJson(null, sink), throwsA(same(error)));
      expect(sink.closes, 1);
    });
  });
}

class _CountingSink implements Sink<List<int>> {
  _CountingSink({this.closeError});

  final Object? closeError;
  int length = 0;
  int largestChunk = 0;
  int chunks = 0;
  int closes = 0;

  @override
  void add(List<int> bytes) {
    length += bytes.length;
    if (bytes.length > largestChunk) largestChunk = bytes.length;
    chunks++;
  }

  @override
  void close() {
    closes++;
    final error = closeError;
    if (error != null) throw error;
  }
}
