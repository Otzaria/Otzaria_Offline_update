import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;

import 'app_logger.dart';

/// `otzaria_downloads.startSha256` דרך ספריית ההצפנה של המערכת
/// (`Sha256Stream`), במקום SHA של Dart טהור על ה-UI isolate.
class NativeSha256Sink extends ByteConversionSink {
  NativeSha256Sink(this._output);

  final Sink<Digest> _output;
  final Sha256Stream _hash = Sha256Stream();
  bool _closed = false;

  @override
  void add(List<int> chunk) => _hash.add(chunk);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    _hash.addSlice(chunk, start, end);
    if (isLast) close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      final hex = _hash.close();
      _output
        ..add(Digest([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]))
        ..close();
    } finally {
      _hash.dispose();
    }
  }
}

bool _nativeHashWarned = false;

/// מוחלף בטסטים כדי לדמות ספרייה נייטיבית שלא נטענת.
Future<String> Function(String path) nativeSha256Impl = _nativeIsolateSha256;

/// אם הספרייה הנייטיבית לא נטענת, חוזרים ל-hash של Dart טהור (אזהרה פעם אחת).
Future<String> nativeFileSha256(String path) async {
  try {
    return await nativeSha256Impl(path);
  } on FileSystemException {
    rethrow;
  } catch (error) {
    if (!_nativeHashWarned) {
      _nativeHashWarned = true;
      AppLogger.maybeInstance
          ?.warn('SHA-256 נייטיבי אינו זמין, משתמש ב-Dart טהור: $error');
    }
    return Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
  }
}

/// SHA-256 של קובץ ב-isolate נפרד, דרך ספריית ההצפנה של המערכת.
Future<String> _nativeIsolateSha256(String path) => Isolate.run(() async {
      final hash = Sha256Stream();
      try {
        await for (final chunk in File(path).openRead()) {
          hash.add(chunk);
        }
        return hash.close();
      } finally {
        hash.dispose();
      }
    });
