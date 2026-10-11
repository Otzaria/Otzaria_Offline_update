import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:custom_apps_manager/src/services/replace_file.dart';
import 'package:otzaria_downloads/atomic_write_testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// תיקייה זמנית שנמחקת בסוף הבדיקה. הבדיקות כאן נוגעות בדיסק אמיתי
/// בכוונה — כל הערך של המרשם הוא מה שקורה לקבצים.
String tempMirrorRoot() {
  final dir = Directory.systemTemp.createTempSync('custom_apps_test_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir.path;
}

AppDescriptor descriptor({
  String id = 'org.example.app',
  String name = 'תוכנה לדוגמה',
  String? publisher,
  String? installDir,
  bool portableFile = false,
  AppDetectRules detect = const AppDetectRules(),
}) =>
    AppDescriptor(
      id: id,
      name: name,
      publisher: publisher,
      sourceKind: AppSourceKind.manual,
      installDir: installDir,
      portableFile: portableFile,
      detect: detect,
    );

/// יוצר קובץ עם תוכן נתון ומחזיר את נתיבו.
String writeFile(String path, [String content = 'x']) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return path;
}

void makeReadOnly(String dir) {
  Process.runSync('chmod', ['-R', 'a-w', dir]);
  addTearDown(() => Process.runSync('chmod', ['-R', 'u+w', dir]));
}

final Object skipWithoutChmod =
    Platform.isWindows ? 'chmod is not available on Windows' : false;

void blockAtomicWrites(String dir, List<String> fileNames) {
  final original = atomicTempPathFor;
  atomicTempPathFor = (path) => '$path.tmp';
  addTearDown(() => atomicTempPathFor = original);
  for (final name in fileNames) {
    Directory(p.join(dir, '$name.tmp')).createSync(recursive: true);
  }
}

void blockReplaceInto(String target) {
  final original = replaceFile;
  replaceFile = (from, to) async {
    if (p.equals(to, target)) throw FileSystemException('blocked', to);
    await original(from, to);
  };
  addTearDown(() => replaceFile = original);
}
