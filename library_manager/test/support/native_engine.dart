import 'dart:io';

import 'package:path/path.dart' as p;

/// The vector set the engine's own artifact builder produced (text 4, 11KB).
const nativeVectorSetDir = 'test/support/native_vector_set';
const _nativeVectorSetFiles = ['release.json', 'segment.oxv', 'model.json'];

/// The engine's build hook puts its library under `build/native_assets`;
/// `flutter test` runs the hook, so this is the pinned version.
/// `OTZARIA_NATIVE_ENGINE_DIR` replaces that root (a seam to rehearse absence).
String? hookEngineLibrary() {
  final name = Platform.isWindows
      ? 'search_engine.dll'
      : Platform.isMacOS
      ? 'libsearch_engine.dylib'
      : 'libsearch_engine.so';
  final root =
      Platform.environment['OTZARIA_NATIVE_ENGINE_DIR'] ??
      p.join('build', 'native_assets');
  for (final os in ['windows', 'macos', 'linux']) {
    final file = File(p.join(root, os, name));
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}

/// Why a native test cannot run (`null` = it can). With `REQUIRE_NATIVE_ENGINE=1`
/// a missing prerequisite throws instead, so CI cannot skip it silently.
String? nativeSkipReason({bool needsVectorSet = false}) {
  final missing = <String>[
    if (hookEngineLibrary() == null)
      'the native engine library under build/native_assets (run '
          '`flutter test` once so the build hook produces it)',
    if (needsVectorSet)
      for (final file in _nativeVectorSetFiles)
        if (!File(p.join(nativeVectorSetDir, file)).existsSync())
          '$nativeVectorSetDir/$file',
  ];
  if (missing.isEmpty) return null;
  final reason = 'native engine prerequisites missing: ${missing.join('; ')}';
  if (Platform.environment['REQUIRE_NATIVE_ENGINE'] == '1') {
    throw StateError('REQUIRE_NATIVE_ENGINE=1 but $reason');
  }
  return reason;
}
