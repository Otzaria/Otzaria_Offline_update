import 'dart:async';

import 'package:otzaria_l10n/otzaria_l10n.dart';

/// "הכונן מלא" ב-[error] או בשרשרת הסיבות שלו, או `null`. המתאם לטקסט של
/// המנוע החיצוני הוא `storageFullFromUpstream`.
StorageFullException? findStorageFull(Object? error, {bool? windows}) =>
    _find(error, (e) => storageFullFromUpstream(e, windows: windows));

/// קובץ או כונן פגומים ב-[error] או בשרשרת הסיבות שלו, או `null`. המתאם
/// לטקסט של המנוע הוא `storageCorruptFromUpstream`.
StorageCorruptException? findStorageCorrupt(Object? error, {bool? windows}) =>
    _find(error, (e) => storageCorruptFromUpstream(e, windows: windows));

T? _find<T extends Object>(Object? error, T? Function(Object) match) {
  T? search(Object? e, int depth) {
    if (e == null || depth > 8) return null;
    if (match(e) case final found?) return found;
    final children = switch (e) {
      AsyncError(:final error) => [error],
      ParallelWaitError(:final errors) =>
        errors is Iterable ? errors : [errors],
      _ => const <Object?>[],
    };
    for (final child in children) {
      final found =
          search(child is AsyncError ? child.error : child, depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  return search(error, 0);
}
