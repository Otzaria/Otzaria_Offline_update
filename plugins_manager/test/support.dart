import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// בונה קובץ `.otzplugin` אמיתי (ZIP) — `PluginManifestReader` קורא ארכיון
/// ממש, ולכן בדיקה עם מחרוזת מדומה לא הייתה בודקת כלום.
List<int> pluginBytes(
  String manifestText, {
  String entryName = 'manifest.json',
}) {
  final content = utf8.encode(manifestText);
  final archive = Archive()
    ..addFile(ArchiveFile(entryName, content.length, content))
    ..addFile(ArchiveFile('main.js', 3, utf8.encode('/**')));
  return ZipEncoder().encode(archive)!;
}

String writePluginFile(Directory dir, String name, String manifestText) {
  final path = p.join(dir.path, name);
  File(path).writeAsBytesSync(pluginBytes(manifestText));
  return path;
}

/// תשובת JSON כמו של האתר — בייטים ב-UTF-8, כי כל הטקסטים בעברית.
http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// תיקייה זמנית שנמחקת בסוף כל בדיקה. מחיקה שנכשלת (נעילת קובץ בווינדוס)
/// לא אמורה להפיל את הבדיקה עצמה.
Directory createTempDir() =>
    Directory.systemTemp.createTempSync('plugins_manager_');

void deleteTempDir(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}
