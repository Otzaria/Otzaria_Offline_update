import 'dart:io';

import 'app_l10n.dart';
import 'app_language.dart';
import 'storage_failure.dart';

/// "אין מספיק מקום" לפי שתי התבניות המתורגמות (הורדה למראה, וחיפוש חכם), בכל
/// השפות: מנוע שזרק טקסט בלבד, והשפה יכולה להתחלף אחרי הכשל.
({String needed, String free})? parseNotEnoughSpace(String error) {
  for (final language in AppLanguage.values) {
    final strings = AppL10n.stringsFor(language).libraryDomain;
    for (final template in [
      strings.mirrorNotEnoughDiskSpace,
      strings.notEnoughDiskSpace,
    ]) {
      final space = _parseTemplate(error, template);
      if (space != null) return space;
    }
  }
  return null;
}

({String needed, String free})? _parseTemplate(
  String error,
  String Function(String dir, String needed, String free) build,
) {
  const marks = ['\u0001', '\u0002', '\u0003'];
  var rest = build(marks[0], marks[1], marks[2]);
  final pattern = StringBuffer();
  final groups = <String>[];
  while (true) {
    ({String mark, int at})? next;
    for (final mark in marks) {
      final at = rest.indexOf(mark);
      if (at >= 0 && (next == null || at < next.at)) {
        next = (mark: mark, at: at);
      }
    }
    if (next == null) {
      pattern.write(RegExp.escape(rest));
      break;
    }
    pattern
      ..write(RegExp.escape(rest.substring(0, next.at)))
      ..write('(.+?)');
    groups.add(next.mark);
    rest = rest.substring(next.at + 1);
  }
  final match = RegExp(pattern.toString(), dotAll: true).firstMatch(error);
  if (match == null) return null;
  String? group(String mark) {
    final index = groups.indexOf(mark);
    return index < 0 ? null : match.group(index + 1);
  }

  final needed = group(marks[1]);
  final free = group(marks[2]);
  if (needed == null || free == null) return null;
  return (needed: needed, free: free);
}

/// ה-errno שבתוך טקסט של [FileSystemException] (`OS Error: ..., errno = 112`).
final _osErrno = RegExp(r'OS Error:[\s\S]*?errno = (\d+)');
final _errorPath = RegExp(r"path = '([^']*)'");

/// המתאם היחיד לכשלי אחסון ש-`seforim_library_updater` מגיש כטקסט בלבד (בלי
/// `cause`): `StateError` "אין מספיק מקום" ו-errno בתוך הודעת חריג. אחרת `null`.
StorageFullException? storageFullFromUpstream(Object? error, {bool? windows}) {
  if (error == null) return null;
  if (error is StorageFullException) return error;
  if (isStorageFull(error, windows: windows)) {
    final path = error is FileSystemException ? error.path : null;
    return StorageFullException(dir: _dirOf(path ?? ''), cause: error);
  }
  final text = error is StateError ? error.message : error.toString();
  if (parseNotEnoughSpace(text) != null) {
    return StorageFullException(message: text, cause: error);
  }
  final errno = int.tryParse(_osErrno.firstMatch(text)?.group(1) ?? '');
  if (errno != null && isStorageFullErrno(errno, windows: windows)) {
    return StorageFullException(
      dir: _dirOf(_errorPath.firstMatch(text)?.group(1) ?? ''),
      cause: error,
    );
  }
  return null;
}

String? _dirOf(String path) {
  if (path.isEmpty) return null;
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut <= 0 ? null : path.substring(0, cut);
}
