import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  test('errno של כונן מלא מזוהה, וגישה נדחתה לא', () {
    FileSystemException fs(int code) =>
        FileSystemException('write', r'D:\x', OSError('x', code));
    expect(isStorageFull(fs(112), windows: true), isTrue);
    expect(isStorageFull(fs(39), windows: true), isTrue);
    expect(isStorageFull(fs(5), windows: true), isFalse);
    expect(isStorageFull(fs(28), windows: false), isTrue);
    expect(isStorageFull(fs(13), windows: false), isFalse);
    expect(isStorageFull(OSError('x', 112), windows: true), isTrue);
    expect(isStorageFull(const StorageFullException()), isTrue);
    expect(isStorageFull(Exception('x')), isFalse);
  });

  test('בלי needed/free ההודעה לא ממציאה מספרים', () {
    expect(
      const StorageFullException(dir: r'D:\mirror').toString(),
      isNot(contains(RegExp(r'\d'))),
    );
  });
}
