import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'declined smart-search consent does not fail an unrelated dictionary update',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'semantic-consent-gate-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        environment: const {},
      );
      addTearDown(manager.dispose);
      final db = p.join(temporary.path, 'books', 'seforim.db');
      await File(db).create(recursive: true);
      const dictionary = 'LEXICAL';
      await Directory(manager.companionsMirrorDir).create(recursive: true);
      await File(
        p.join(manager.companionsMirrorDir, 'lexical.db'),
      ).writeAsString(dictionary);
      await File(
        p.join(manager.companionsMirrorDir, 'companions.json'),
      ).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'dictionary': {
            'fileName': 'lexical.db',
            'size': dictionary.length,
            'tag': 'v2',
          },
        }),
      );
      final check = LibraryUpdateCheckResult(
        dbPath: db,
        pendingCompanions: const {CompanionAsset.dictionary},
        semanticPending: true,
        semanticConsentGranted: false,
      );
      expect(check.updateAvailable, true);
      expect(check.dbUpdateAvailable, false);
      final warnings = <String>[];
      await manager.applyUpdate(
        check,
        onCompanionWarning: (name, _) => warnings.add(name),
      );
      expect(
        await File(p.join(p.dirname(db), 'lexical.db')).readAsString(),
        dictionary,
      );
      expect(
        warnings,
        isNot(contains(AppL10n.strings.libraryDomain.companionSemanticName)),
      );
      expect(warnings, isEmpty);
      expect(
        await Directory(p.join(temporary.path, 'vectors')).exists(),
        false,
      );
      expect(
        await Directory(
          p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
        ).exists(),
        false,
      );
    },
  );
}
