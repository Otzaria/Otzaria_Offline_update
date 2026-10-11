import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const String pluginsRegistryFileName = 'plugins_host.db';

Map<String, String>? readInstalledPluginsRegistry(String dbPath) {
  if (!File(dbPath).existsSync()) return null;
  Database? db;
  try {
    db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    db.execute('PRAGMA busy_timeout=2000');
    final table = db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' "
      "AND name='plugin_installation'",
    );
    if (table.isEmpty) return null;
    final result = <String, String>{};
    for (final row
        in db.select('SELECT plugin_id, version FROM plugin_installation')) {
      final id = row['plugin_id'];
      final version = row['version'];
      if (id is String &&
          id.isNotEmpty &&
          version is String &&
          version.isNotEmpty) {
        result[id] = version;
      }
    }
    return result;
  } catch (_) {
    return null;
  } finally {
    db?.close();
  }
}
