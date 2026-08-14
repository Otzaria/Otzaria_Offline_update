import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

OtzariaRelease _release({
  String tagName = '0.9.96+736',
  bool isPrerelease = false,
  OtzariaInstallerKind kind = OtzariaInstallerKind.windowsSetupExe,
}) =>
    OtzariaRelease(
      tagName: tagName,
      name: 'Otzaria $tagName',
      isPrerelease: isPrerelease,
      isDraft: false,
      publishedAt: DateTime.utc(2026, 1, 1),
      installerKind: kind,
      installerAssetName: 'otzaria-$tagName-windows.exe',
      installerDownloadUrl: 'https://example/$tagName',
      installerSizeBytes: 42,
    );

OtzariaInstallState _state(String tag) => OtzariaInstallState(
      installedTagName: tag,
      installDir: r'C:\dir',
      launchPath: r'C:\dir\otzaria.exe',
    );

/// המטא־דאטה המינימלית ש-[OtzariaRelease.fromJson] דורשת.
Map<String, dynamic> _minimalJson() => <String, dynamic>{
      'tagName': '0.9.96',
      'installerKind': 'windowsSetupExe',
      'installerAssetName': 'otzaria-0.9.96-windows.exe',
      'installerSizeBytes': 7,
    };

void main() {
  // ההודעות נקראות דרך AppL10n, ולכן כל בדיקה שמחליפה שפה חייבת להחזיר.
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  group('normalizeVersion', () {
    test('מוריד v מוביל (גם גדולה) ואת סיומת ה-build', () {
      expect(
          OtzariaUpdateCheckResult.normalizeVersion('v0.9.96+736'), '0.9.96');
      expect(OtzariaUpdateCheckResult.normalizeVersion('V0.9.96'), '0.9.96');
      expect(OtzariaUpdateCheckResult.normalizeVersion('0.9.96+736'), '0.9.96');
    });

    test('עמיד לקלט ריק/רווחים/מנוון', () {
      expect(OtzariaUpdateCheckResult.normalizeVersion(''), '');
      expect(OtzariaUpdateCheckResult.normalizeVersion('   '), '');
      expect(OtzariaUpdateCheckResult.normalizeVersion('v'), '');
      expect(OtzariaUpdateCheckResult.normalizeVersion('+736'), '');
      expect(OtzariaUpdateCheckResult.normalizeVersion('0.9.96+'), '0.9.96');
      expect(OtzariaUpdateCheckResult.normalizeVersion('  v0.9.96+736  '),
          '0.9.96');
    });

    test('חותך ב-+ הראשון, ומוריד v אחד בלבד', () {
      expect(OtzariaUpdateCheckResult.normalizeVersion('1.2.3+7+8'), '1.2.3');
      expect(OtzariaUpdateCheckResult.normalizeVersion('vv1.2.3'), 'v1.2.3');
    });

    // ההשוואה טקסטואלית ולא סמנטית — \u200E1.2 ו-1.2.0 אינם אותו דבר.
    test('אינה משווה סמנטית בין מספרי גרסה באורך שונה', () {
      expect(
        OtzariaUpdateCheckResult.normalizeVersion('1.2'),
        isNot(OtzariaUpdateCheckResult.normalizeVersion('1.2.0')),
      );
    });
  });

  group('updateAvailable', () {
    test('התאמה אחרי נרמול — אין עדכון פנטום', () {
      for (final pair in [
        ('0.9.96', '0.9.96+736'),
        ('0.9.96', 'v0.9.96'),
        ('v0.9.96+1', '0.9.96+736'),
        (' 0.9.96 ', '0.9.96'),
      ]) {
        final result = OtzariaUpdateCheckResult(
          stableRelease: _release(tagName: pair.$2),
          currentState: _state(pair.$1),
        );
        expect(result.updateAvailable, isFalse,
            reason: 'מותקן ${pair.$1} מול תג ${pair.$2}');
      }
    });

    // ב-README מתועד release אמיתי בתג `0.9.53-pr-715-146` שה-exe שלו מדווח
    // `0.9.53`. בלי ההשוואה על הבסיס, כל התקנה מאומצת של גרסת pre-release
    // הייתה רואה "יש עדכון" ומתקינה מחדש את אותה גרסה בדיוק.
    test('התקנה מאומצת של pre-release אינה נראית כעדכון', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.53-pr-715-146'),
        currentState: _state('0.9.53'),
      );

      expect(result.updateAvailable, isFalse);
    });

    // הסיומת מושמטת רק בצד אחד — אחרת המעבר בין הערוצים היה משותק.
    test('סיומת בשני הצדדים עדיין מושווית במלואה', () {
      expect(
        OtzariaUpdateCheckResult.sameVersion('1.0.0-beta1', '1.0.0-beta2'),
        isFalse,
      );
      expect(
        OtzariaUpdateCheckResult.sameVersion('1.0.0-beta', '1.0.0-beta'),
        isTrue,
      );
    });

    test('בסיס שונה נשאר עדכון גם כשצד אחד נושא סיומת', () {
      expect(
        OtzariaUpdateCheckResult.sameVersion('0.9.53', '0.9.54-pr-1'),
        isFalse,
      );
    });

    test('normalizeVersion עצמו אינו נוגע בסיומת המקף', () {
      // הוא משמש גם לאיתור הסעיף ביומן השינויים, שם התג מופיע במלואו.
      expect(OtzariaUpdateCheckResult.normalizeVersion('0.9.53-pr-715-146'),
          '0.9.53-pr-715-146');
      expect(
          OtzariaUpdateCheckResult.normalizeVersion('v0.9.96+736'), '0.9.96');
    });

    test('גרסה מותקנת ריקה נחשבת שונה, ולכן מוצע עדכון', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.96'),
        currentState: _state(''),
      );

      expect(result.updateAvailable, isTrue);
    });

    // מעבר מהערוץ הלא-יציב חזרה ליציב הוא ירידת גרסה — וגם אותו מציעים.
    test('ירידת גרסה מוצעת כשהמשתמש ביקש את הערוץ השני', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.90'),
        prereleaseRelease: _release(tagName: '0.9.97', isPrerelease: true),
        currentState: _state('0.9.97'),
      );

      expect(result.installedIsNewer, isFalse);
      expect(result.updateAvailable, isTrue);
      expect(result.latestRelease!.tagName, '0.9.90');
    });
  });

  group('installedIsNewer', () {
    // דיווח מהשטח: 0.9.97 הותקנה ידנית, המראה החזיקה 0.9.96, והלאנצ'ר הציע
    // "עדכון" שהיה מחזיר את המשתמש אחורה.
    test('מותקן חדש מהמראה — אין הצעת התקנה', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.96+736'),
        currentState: _state('0.9.97+90970'),
      );

      expect(result.installedIsNewer, isTrue);
      expect(result.updateAvailable, isFalse);
    });

    test('המראה חדשה מהמותקן — עדכון רגיל', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.97+90970'),
        currentState: _state('0.9.96'),
      );

      expect(result.installedIsNewer, isFalse);
      expect(result.updateAvailable, isTrue);
    });

    test('אותה גרסה אינה נסיגה ואינה עדכון', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.96+741'),
        currentState: _state('0.9.96+736'),
      );

      expect(result.installedIsNewer, isFalse);
      expect(result.updateAvailable, isFalse);
    });

    test('בלי התקנה קודמת אין מול מה להשוות', () {
      final result = OtzariaUpdateCheckResult(
        stableRelease: _release(tagName: '0.9.96'),
        currentState: null,
      );

      expect(result.installedIsNewer, isFalse);
      expect(result.updateAvailable, isTrue);
    });
  });

  group('compareVersions', () {
    test('משווה כמספרים ולא כטקסט', () {
      expect(OtzariaUpdateCheckResult.compareVersions('0.9.97', '0.9.96'), 1);
      expect(OtzariaUpdateCheckResult.compareVersions('0.9.9', '0.9.10'), -1);
      expect(OtzariaUpdateCheckResult.compareVersions('0.10.0', '0.9.99'), 1);
    });

    test('מתעלם מ-v מוביל ומסיומת ה-build', () {
      expect(
          OtzariaUpdateCheckResult.compareVersions('v0.9.96+741', '0.9.96+736'),
          0);
    });

    test('חלק חסר נחשב 0', () {
      expect(OtzariaUpdateCheckResult.compareVersions('1.2', '1.2.0'), 0);
      expect(OtzariaUpdateCheckResult.compareVersions('1.2', '1.2.1'), -1);
    });

    // הסיומת מכריעה רק בתיקו, ורק כשהיא בצד אחד — שתי סיומות שונות אינן
    // ברות השוואה, ושם ההכרעה נשארת ל-updateAvailable.
    test('סיומת pre-release ותיקה מהבסיס הנקי', () {
      expect(
          OtzariaUpdateCheckResult.compareVersions('1.0.0-beta', '1.0.0'), -1);
      expect(
          OtzariaUpdateCheckResult.compareVersions('1.0.1-beta', '1.0.0'), 1);
      expect(
        OtzariaUpdateCheckResult.compareVersions('1.0.0-beta1', '1.0.0-beta2'),
        0,
      );
    });

    test('גרסה ריקה ותיקה מכל גרסה אמיתית', () {
      expect(OtzariaUpdateCheckResult.compareVersions('', '0.9.96'), -1);
    });
  });

  group('OtzariaRelease.fromJson', () {
    test('ממלא ברירות מחדל לשדות אופציונליים חסרים', () {
      final release = OtzariaRelease.fromJson(_minimalJson());

      expect(release.name, '0.9.96');
      expect(release.isPrerelease, isFalse);
      expect(release.isDraft, isFalse);
      expect(release.publishedAt, isNull);
      expect(release.installerDownloadUrl, '');
      expect(release.releaseNotes, isNull);
    });

    test('שדות null מפורשים מתנהגים כמו חסרים', () {
      final release = OtzariaRelease.fromJson(_minimalJson()
        ..addAll({
          'name': null,
          'isPrerelease': null,
          'isDraft': null,
          'publishedAt': null,
          'installerDownloadUrl': null,
          'releaseNotes': null,
        }));

      expect(release.name, '0.9.96');
      expect(release.isPrerelease, isFalse);
      expect(release.installerDownloadUrl, '');
    });

    test('שדות לא מוכרים בקובץ אינם מפילים את הקריאה', () {
      final release = OtzariaRelease.fromJson(
        _minimalJson()..addAll({'installerPath': 'installers/x.exe', 'foo': 1}),
      );

      expect(release.tagName, '0.9.96');
    });

    test('publishedAt לא חוקי הופך ל-null במקום לזרוק', () {
      final release =
          OtzariaRelease.fromJson(_minimalJson()..['publishedAt'] = 'לא תאריך');

      expect(release.publishedAt, isNull);
    });

    test('publishedAt שאינו מחרוזת מתעלמים ממנו', () {
      final release =
          OtzariaRelease.fromJson(_minimalJson()..['publishedAt'] = 17);

      expect(release.publishedAt, isNull);
    });

    test('מטא־דאטה חסרה/פגומה זורקת FormatException עם הודעת ה-l10n', () {
      final broken = <String, Map<String, dynamic>>{
        'בלי tagName': _minimalJson()..remove('tagName'),
        'בלי installerKind': _minimalJson()..remove('installerKind'),
        'installerKind לא מוכר': _minimalJson()..['installerKind'] = 'linuxDeb',
        'בלי שם אסט': _minimalJson()..remove('installerAssetName'),
        'גודל שאינו int': _minimalJson()..['installerSizeBytes'] = 1.5,
        'גודל כמחרוזת': _minimalJson()..['installerSizeBytes'] = '7',
      };

      for (final entry in broken.entries) {
        expect(
          () => OtzariaRelease.fromJson(entry.value),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              AppL10n.strings.appDomain.corruptReleaseMetadata,
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('round-trip שומר גם על releaseNotes ועל publishedAt', () {
      final original = _release().copyWithReleaseNotes('- שורה');

      expect(OtzariaRelease.fromJson(original.toJson()), original);
    });

    test('copyWithReleaseNotes מחליף רק את ההערות, וגם מנקה אותן', () {
      final withNotes = _release().copyWithReleaseNotes('חדש');

      expect(withNotes.releaseNotes, 'חדש');
      expect(withNotes.tagName, _release().tagName);
      expect(withNotes.copyWithReleaseNotes(null).releaseNotes, isNull);
      expect(withNotes.copyWithReleaseNotes(null), _release());
    });
  });

  group('OtzariaInstallState', () {
    test('חסר גם launchPath וגם exePath — זורק', () {
      expect(
        () => OtzariaInstallState.fromJson(const {
          'installedTagName': '0.9.96',
          'installDir': r'C:\dir',
        }),
        throwsA(anything),
      );
    });

    test('launchPath מנצח את exePath הישן כששניהם קיימים', () {
      final state = OtzariaInstallState.fromJson(const {
        'installedTagName': '0.9.96',
        'installDir': r'C:\dir',
        'launchPath': r'C:\dir\new.exe',
        'exePath': r'C:\dir\old.exe',
      });

      expect(state.launchPath, r'C:\dir\new.exe');
    });

    test('שוויון לפי ערך (Equatable)', () {
      expect(_state('0.9.96'), _state('0.9.96'));
      expect(_state('0.9.96'), isNot(_state('0.9.97')));
    });
  });

  group('OtzariaChannelPair', () {
    final stable = _release(tagName: '0.9.90');
    final prerelease = _release(tagName: '0.9.97', isPrerelease: true);

    test('זוג ריק', () {
      const pair = OtzariaChannelPair<OtzariaRelease>();

      expect(pair.isEmpty, isTrue);
      expect(pair.hasChoice, isFalse);
      expect(pair.all, isEmpty);
      expect(pair.select(preferPrerelease: true), isNull);
      expect(pair.selectedChannel(preferPrerelease: false), isNull);
      expect(pair[OtzariaReleaseChannel.stable], isNull);
    });

    test('גישה לפי ערוץ, ו-all לפי סדר יציב→לא יציב', () {
      final pair = OtzariaChannelPair(stable: stable, prerelease: prerelease);

      expect(pair[OtzariaReleaseChannel.stable], stable);
      expect(pair[OtzariaReleaseChannel.prerelease], prerelease);
      expect(pair.all, [stable, prerelease]);
      expect(pair.isEmpty, isFalse);
      expect(pair.hasChoice, isTrue);
    });

    // המצב שבו אין release יציב כלל בעמוד הראשון: ה-pre-release הוא הגרסה
    // היחידה, והתווית חייבת לומר שזה הערוץ הלא-יציב.
    test('pre-release בלבד נבחר גם בהעדפת יציב, ומתויג נכון', () {
      final pair = OtzariaChannelPair(prerelease: prerelease);

      expect(pair.hasChoice, isFalse);
      expect(pair.select(preferPrerelease: false), prerelease);
      expect(pair.selectedChannel(preferPrerelease: false),
          OtzariaReleaseChannel.prerelease);
    });

    test('יציב בלבד נבחר גם בהעדפת לא-יציב, ומתויג נכון', () {
      final pair = OtzariaChannelPair(stable: stable);

      expect(pair.select(preferPrerelease: true), stable);
      expect(pair.selectedChannel(preferPrerelease: true),
          OtzariaReleaseChannel.stable);
    });
  });

  group('אנומים ותוויות', () {
    test('fromPrerelease ממופה לדגל של GitHub', () {
      expect(OtzariaReleaseChannel.fromPrerelease(true),
          OtzariaReleaseChannel.prerelease);
      expect(OtzariaReleaseChannel.fromPrerelease(false),
          OtzariaReleaseChannel.stable);
    });

    test('תווית הערוץ מגיעה מ-l10n ומתחלפת עם השפה', () {
      expect(OtzariaReleaseChannel.stable.label,
          AppL10n.strings.appDomain.channelStable);

      AppL10n.use(AppLanguage.english);
      expect(OtzariaReleaseChannel.prerelease.label,
          const EnglishStrings().appDomain.channelPrerelease);
      expect(OtzariaReleaseChannel.prerelease.label,
          isNot(const HebrewStrings().appDomain.channelPrerelease));
    });

    test('isMac נכון לשלושת סוגי ההתקנה', () {
      expect(OtzariaInstallerKind.windowsSetupExe.isMac, isFalse);
      expect(OtzariaInstallerKind.macAppZip.isMac, isTrue);
      expect(OtzariaInstallerKind.macAppDmg.isMac, isTrue);
    });

    test('תוויות הפלטפורמה', () {
      expect(OtzariaTargetPlatform.windows.label, 'Windows');
      expect(OtzariaTargetPlatform.macos.label, 'macOS');
    });

    test('detect זורק עם הודעת ה-l10n של פלטפורמה לא נתמכת', () {
      expect(
        () => OtzariaTargetPlatform.detect('fuchsia'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.appDomain.unsupportedPlatform('fuchsia'),
          ),
        ),
      );
    });

    test('NoInstallerAssetException מנסחת דרך l10n', () {
      const exception = NoInstallerAssetException(
        tagName: '0.9.96',
        platform: OtzariaTargetPlatform.macos,
        expectedSuffixes: ['macos.zip', 'macos.dmg'],
      );

      expect(
        exception.toString(),
        AppL10n.strings.appDomain
            .noAssetForPlatform('0.9.96', 'macOS', ['macos.zip', 'macos.dmg']),
      );
    });
  });
}
