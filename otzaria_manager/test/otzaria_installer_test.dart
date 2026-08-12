import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _installerBytes = 'inno-setup-installer-bytes';
const String _tag = '0.9.96+736';
const String _assetName = 'otzaria-0.9.96-windows.exe';

OtzariaRelease _release({int? size}) => OtzariaRelease(
      tagName: _tag,
      name: 'Otzaria $_tag',
      isPrerelease: false,
      isDraft: false,
      publishedAt: null,
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: _assetName,
      installerDownloadUrl: 'https://example/$_assetName',
      installerSizeBytes: size ?? _installerBytes.length,
    );

void main() {
  late Directory tempDir;
  late String cacheDir;
  late int requests;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-installer-');
    cacheDir = p.join(tempDir.path, 'mirror', 'app', 'installers');
    requests = 0;
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  OtzariaInstaller installerWith(http.Client client) => OtzariaInstaller(
        cacheDir: cacheDir,
        httpClient: client,
        appLocator:
            const OtzariaAppLocator(platform: OtzariaTargetPlatform.windows),
      );

  http.Client mockDownload(String body, {int status = 200}) =>
      MockClient((_) async {
        requests++;
        return http.Response(body, status);
      });

  /// לקוח שכל פנייה אליו היא כישלון הבדיקה — כך "לא ניגשנו לרשת" נאכף.
  http.Client mustNotBeUsed() => MockClient((_) async {
        requests++;
        fail('לא הייתה אמורה להיות פנייה לרשת');
      });

  String cachedPath() => p.join(cacheDir, _tag, _assetName);

  group('OtzariaInstaller.ensureCached', () {
    test('מוריד לתת-תיקייה לפי תג, ומדווח התקדמות מול הגודל הצפוי', () async {
      final installer = installerWith(mockDownload(_installerBytes));
      addTearDown(installer.dispose);
      final progress = <(int, int)>[];

      final path = await installer.ensureCached(
        release: _release(),
        onDownloadProgress: (received, total) =>
            progress.add((received, total)),
      );

      expect(path, cachedPath());
      expect(File(path).readAsStringSync(), _installerBytes);
      expect(progress, isNotEmpty);
      expect(progress.last, (_installerBytes.length, _installerBytes.length));
      expect(requests, 1);
    });

    test('עותק תקין ב-cache נחשב hit — בלי רשת בכלל', () async {
      await Directory(p.join(cacheDir, _tag)).create(recursive: true);
      await File(cachedPath()).writeAsString(_installerBytes);
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      expect(await installer.ensureCached(release: _release()), cachedPath());
      expect(requests, 0);
    });

    // הורדה שנקטעה משאירה קובץ בגודל שגוי — חייבים להוריד שוב.
    test('קובץ ב-cache בגודל שגוי מורד מחדש', () async {
      await Directory(p.join(cacheDir, _tag)).create(recursive: true);
      await File(cachedPath()).writeAsString('חצי');
      final installer = installerWith(mockDownload(_installerBytes));
      addTearDown(installer.dispose);

      await installer.ensureCached(release: _release());

      expect(requests, 1);
      expect(File(cachedPath()).readAsStringSync(), _installerBytes);
    });

    test('גודל שונה מהמוצהר — שגיאה, והקובץ החלקי נמחק', () async {
      final installer = installerWith(mockDownload('short'));
      addTearDown(installer.dispose);

      await expectLater(
        installer.ensureCached(release: _release(size: 999)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.appDomain.installerSizeMismatch(5, 999),
          ),
        ),
      );
      expect(File(cachedPath()).existsSync(), isFalse);
    });

    test('סטטוס HTTP לא תקין — שגיאת l10n ובלי קובץ שנשאר', () async {
      final installer = installerWith(mockDownload('', status: 404));
      addTearDown(installer.dispose);

      await expectLater(
        installer.ensureCached(release: _release()),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.installerDownloadFailed(404)),
        ),
      );
      expect(File(cachedPath()).existsSync(), isFalse);
    });
  });

  group('OtzariaInstaller.pruneCacheExcept', () {
    test('משאיר רק את התגים המבוקשים', () async {
      for (final tag in ['0.9.90', '0.9.96+736', '0.9.97']) {
        await Directory(p.join(cacheDir, tag)).create(recursive: true);
      }
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      // שני הערוצים נשמרים יחד — התקנה של אחד לא מוחקת את קובץ ההתקנה של
      // השני, אחרת החלפת ערוץ הייתה דורשת חזרה לרשת.
      await installer.pruneCacheExcept(keepTagNames: {'0.9.96+736', '0.9.97'});

      final remaining = Directory(cacheDir)
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(remaining, ['0.9.96+736', '0.9.97']);
    });

    test('תיקיית cache שאינה קיימת אינה שגיאה', () async {
      final installer = installerWith(mustNotBeUsed());
      addTearDown(installer.dispose);

      await expectLater(
        installer.pruneCacheExcept(keepTagNames: const {}),
        completes,
      );
    });
  });

  // הלנדמיין מ-AGENTS.md: החתימה ה-ad-hoc של ה-.app שורדת רק חילוץ עם
  // `ditto`. אין דרך להריץ את המסלול הזה בווינדוס, ולכן נאכף על הקוד עצמו.
  group('מסלול macOS משתמש ב-ditto בלבד', () {
    final source =
        File(p.join('lib', 'src', 'services', 'otzaria_installer.dart'))
            .readAsStringSync();
    // ההערות בקובץ מזכירות את unzip דווקא כדי להסביר למה לא — לכן משווים
    // מול הקוד בלבד.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('החילוץ וההעתקה קוראים ל-/usr/bin/ditto', () {
      expect(code, contains("Process.run('/usr/bin/ditto', ["));
      expect(code, contains("'-x',"));
      expect(code, contains("'-k',"));
    });

    test('אלה הכלים החיצוניים היחידים שהמסלול מריץ', () {
      final tools = RegExp(r"Process\.run\(\s*'([^']+)'")
          .allMatches(code)
          .map((m) => m.group(1)!)
          .toSet();

      expect(tools, {'/usr/bin/ditto', '/usr/bin/hdiutil', '/usr/bin/xattr'});
    });

    test('אין שימוש ב-unzip או ב-package:archive', () {
      expect(code, isNot(contains('unzip')));
      expect(code, isNot(contains('package:archive')));
    });
  });
}
