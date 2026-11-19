import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/native_sha256_sink.dart';

void main() {
  test('אותו digest כמו package:crypto, גם בהזרמה בחלקים', () {
    final random = Random(7);
    final data = Uint8List.fromList(
        List.generate(3 * 1024 * 1024 + 17, (_) => random.nextInt(256)));
    late Digest digest;
    final sink = NativeSha256Sink(
        ChunkedConversionSink<Digest>.withCallback((d) => digest = d.single));
    for (var i = 0; i < data.length; i += 65536) {
      sink.add(data.sublist(i, min(i + 65536, data.length)));
    }
    sink.close();
    sink.close();

    expect(digest, sha256.convert(data));
  });
  test('hash קובץ ב-isolate שווה ל-package:crypto', () async {
    final dir = await Directory.systemTemp.createTemp('native-sha-file-');
    addTearDown(() => dir.delete(recursive: true));
    final random = Random(11);
    final data = Uint8List.fromList(
        List.generate(2 * 1024 * 1024 + 5, (_) => random.nextInt(256)));
    final file = File('${dir.path}/data.bin')..writeAsBytesSync(data);

    expect(await nativeFileSha256(file.path), sha256.convert(data).toString());
  });
  test('נפילת הספרייה הנייטיבית חוזרת ל-Dart טהור', () async {
    final dir = await Directory.systemTemp.createTemp('native-sha-fallback-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/d.bin')..writeAsBytesSync([1, 2, 3, 4]);
    final original = nativeSha256Impl;
    addTearDown(() => nativeSha256Impl = original);
    nativeSha256Impl = (_) => throw ArgumentError('no lib');

    expect(
      await nativeFileSha256(file.path),
      sha256.convert([1, 2, 3, 4]).toString(),
    );
  });
}
