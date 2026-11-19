import 'dart:convert';
import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

import 'serial_queue.dart';

/// עדכון מצב עזר הוא best effort; התור מכסה גם את הקריאה שלפני הכתיבה.
class JsonStateStore {
  JsonStateStore(String path) : _file = File(p.normalize(p.absolute(path)));

  final File _file;
  late final SerialQueue _queue = SerialQueue.forKey(
    Platform.isWindows ? _file.path.toLowerCase() : _file.path,
  );

  Future<Map<String, dynamic>> load() async {
    try {
      final json = jsonDecode(await _file.readAsString());
      return json is Map<String, dynamic> ? json : {};
    } catch (_) {
      return {};
    }
  }

  /// החזרת null משאירה את הקובץ ללא כתיבה.
  Future<void> update(
    Map<String, Object?>? Function(Map<String, dynamic> json) change,
  ) =>
      _queue.run(() async {
        try {
          final next = change(await load());
          if (next == null) return;
          await _file.parent.create(recursive: true);
          await writeStringAtomically(_file.path, jsonEncode(next));
        } catch (_) {
          // מצב עזר שלא נשמר ייבדק שוב בהרצה הבאה.
        }
      });
}

String stateHostName(String? given) {
  try {
    final host = given ?? Platform.localHostname;
    return host.isEmpty ? 'unknown' : host;
  } catch (_) {
    return 'unknown';
  }
}
