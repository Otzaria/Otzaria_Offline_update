import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

const _selector = OtzariaAssetSelector();

/// הבורר גנרי בכוונה — כאן הוא מקבל שמות "עירומים", בלי צורת ה-JSON של
/// GitHub, וזה בדיוק מה שמאפשר לבדוק אותו בלי רשת.
(String, OtzariaInstallerKind)? _pick(
  OtzariaTargetPlatform platform,
  List<String> names,
) =>
    _selector.select(
      platform: platform,
      assets: names,
      nameOf: (name) => name,
    );

void main() {
  _fullPackageTests();
  group('OtzariaAssetSelector (Windows)', () {
    test('בוחר את ה-installer הרגיל ולא את חבילת ה-FULL של ~2GB', () {
      final picked = _pick(OtzariaTargetPlatform.windows, [
        'otzaria-0.9.96-windows-full.exe',
        'otzaria-0.9.96-windows.exe',
      ]);

      expect(picked!.$1, 'otzaria-0.9.96-windows.exe');
      expect(picked.$2, OtzariaInstallerKind.windowsSetupExe);
    });

    test('פוסל אסטים שאינם ה-installer של ווינדוס', () {
      expect(
        _pick(OtzariaTargetPlatform.windows, [
          'app-release.apk',
          'otzaria-0.9.96-linux.deb',
          'otzaria-0.9.96-windows-full.exe',
          'otzaria-0.9.96-windows-silent.exe',
          'otzaria-windows.zip',
          'otzaria.msix',
          'otzaria-macos.zip',
          'otzaria-0.9.96-windows.exe.sha256',
        ]),
        isNull,
      );
    });

    test('ההתאמה אינה תלוית רישיות', () {
      expect(
        _pick(OtzariaTargetPlatform.windows, ['OTZARIA-0.9.96-WINDOWS.EXE'])!
            .$1,
        'OTZARIA-0.9.96-WINDOWS.EXE',
      );
    });

    test('רשימת אסטים ריקה מחזירה null', () {
      expect(_pick(OtzariaTargetPlatform.windows, const []), isNull);
    });
  });

  group('OtzariaAssetSelector (macOS)', () {
    test('zip לפני dmg, גם כשה-dmg מופיע ראשון ברשימה', () {
      final picked = _pick(OtzariaTargetPlatform.macos, [
        'otzaria-macos.dmg',
        'otzaria-macos-full.zip',
        'otzaria-macos.zip',
      ]);

      expect(picked!.$1, 'otzaria-macos.zip');
      expect(picked.$2, OtzariaInstallerKind.macAppZip);
    });

    test('נופל ל-dmg כשאין zip', () {
      final picked = _pick(OtzariaTargetPlatform.macos, [
        'otzaria-macos-full.zip',
        'otzaria-macos.dmg',
      ]);

      expect(picked!.$2, OtzariaInstallerKind.macAppDmg);
    });

    test('release של ווינדוס בלבד מחזיר null', () {
      expect(
        _pick(OtzariaTargetPlatform.macos, ['otzaria-0.9.96-windows.exe']),
        isNull,
      );
    });
  });

  test('expectedSuffixesFor מחזיר את הסיומות בסדר העדיפות', () {
    expect(
      OtzariaAssetSelector.expectedSuffixesFor(OtzariaTargetPlatform.windows),
      ['windows.exe'],
    );
    expect(
      OtzariaAssetSelector.expectedSuffixesFor(OtzariaTargetPlatform.macos),
      ['macos.zip', 'macos.dmg'],
    );
  });

  test('הבורר עובד על כל טיפוס אסט, לא רק על JSON של GitHub', () {
    final picked = _selector.select(
      platform: OtzariaTargetPlatform.windows,
      assets: const [
        {'name': 'x.apk'},
        {'name': 'otzaria-0.9.96-windows.exe'},
      ],
      nameOf: (asset) => asset['name']!,
    );

    expect(picked!.$1['name'], 'otzaria-0.9.96-windows.exe');
  });
}

void _fullPackageTests() {
  const selector = OtzariaAssetSelector();

  /// רשימת האסטים של release אמיתי (0.9.96), כולל חבילות ה-FULL.
  const assets = [
    'app-release.apk',
    'otzaria-0.9.96+90960-90960.x86_64.rpm',
    'otzaria-0.9.96+90960-linux.deb',
    'otzaria-0.9.96-windows-full.exe',
    'otzaria-0.9.96-windows.exe',
    'otzaria-android-full.zip',
    'otzaria-macos.dmg',
    'otzaria-macos.zip',
    'otzaria-windows.zip',
  ];

  (String, OtzariaInstallerKind)? full(OtzariaTargetPlatform platform) =>
      selector.selectFull(
        platform: platform,
        assets: assets,
        nameOf: (a) => a,
      );

  group('חבילת FULL — בורר נפרד, בלי לגעת ברגיל', () {
    test('בווינדוס נבחרת חבילת ה-FULL ולא המתקין הרגיל', () {
      expect(full(OtzariaTargetPlatform.windows)?.$1,
          'otzaria-0.9.96-windows-full.exe');
      expect(full(OtzariaTargetPlatform.windows)?.$2,
          OtzariaInstallerKind.windowsSetupExe);
    });

    test('הבורר הרגיל ממשיך לבחור את המתקין הקטן', () {
      final regular = selector.select(
        platform: OtzariaTargetPlatform.windows,
        assets: assets,
        nameOf: (a) => a,
      );
      expect(regular?.$1, 'otzaria-0.9.96-windows.exe');
    });

    test('ב-macOS אין FULL ב-release הזה — null, ולא אסט אנדרואיד', () {
      // `otzaria-android-full.zip` מסתיים ב-full.zip, ובלי הדרישה ל-`macos-`
      // הוא היה נבחר כחבילת ה-macOS.
      expect(full(OtzariaTargetPlatform.macos), isNull);
    });

    test('release בלי חבילת FULL מחזיר null ואינו שגיאה', () {
      expect(
        selector.selectFull(
          platform: OtzariaTargetPlatform.windows,
          assets: const ['otzaria-0.9.96-windows.exe'],
          nameOf: (a) => a,
        ),
        isNull,
      );
    });
  });
}
