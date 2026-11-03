import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every package pins the same library updater engine commit', () {
    final pins = <String, String?>{
      for (final path in const [
        'pubspec.yaml',
        'library_manager/pubspec.yaml',
        'launcher_app/pubspec.yaml',
        'tool/download_bench/pubspec.yaml',
      ])
        path: RegExp(r'seforim_library_updater:[\s\S]*?ref:\s*([0-9a-f]{40})')
            .firstMatch(File(path).readAsStringSync())
            ?.group(1),
    };

    expect(pins.values.toSet(), hasLength(1), reason: '$pins');
    expect(pins.values.first, isNotNull, reason: '$pins');
  });
}
