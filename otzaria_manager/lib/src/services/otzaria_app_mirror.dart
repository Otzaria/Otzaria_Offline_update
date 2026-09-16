import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';
import '../models/otzaria_release_channel.dart';
import 'otzaria_asset_selector.dart';
import 'otzaria_changelog_client.dart';
import 'otzaria_installer.dart';
import 'otzaria_release_client.dart';

/// גרסת אוצריא שיושבת מוכנה בתיקייה המקומית: המטא־דאטה שלה וקובץ ההתקנה
/// שכבר הורד.
class MirroredOtzariaRelease {
  const MirroredOtzariaRelease({
    required this.release,
    required this.installerPath,
  });

  final OtzariaRelease release;

  /// נתיב מלא לקובץ ההתקנה בדיסק — ההתקנה קוראת מכאן, בלי רשת.
  final String installerPath;
}

/// הגרסאות שיושבות במראה, לפי ערוץ — ראו [OtzariaChannelPair].
typedef MirroredOtzariaReleases = OtzariaChannelPair<MirroredOtzariaRelease>;

/// המראה המקומית של **תוכנת אוצריא עצמה**: קובצי ההתקנה של הגרסאות
/// האחרונות יחד עם המטא־דאטה שלהן, בתיקייה שלצד הלאנצ'ר.
///
/// המראה מחזיקה **עד שתי גרסאות**: היציבה האחרונה, ובנוסף ה-pre-release
/// האחרון כשהוא חדש ממנה — כדי שבמחשב המנותק יהיה מה לבחור בין השתיים.
///
/// בלי המטא־דאטה המקומית, בדיקת גרסה הייתה חייבת לפנות ל-GitHub — ובמחשב
/// בלי רשת מודול התוכנה היה פשוט נכשל. עם המראה, [load] עונה מהדיסק
/// ו-[sync] היא הפעולה היחידה שנוגעת ברשת.
class OtzariaAppMirror {
  OtzariaAppMirror({
    required this.mirrorDir,
    required OtzariaReleaseClient releaseClient,
    required OtzariaInstaller installer,
    OtzariaChangelogClient? changelogClient,
    OtzariaTargetPlatform? platform,
  })  : _releaseClient = releaseClient,
        _installer = installer,
        _changelogClient = changelogClient ?? OtzariaChangelogClient(),
        _platform = platform ??
            OtzariaTargetPlatform.detectOrNull(Platform.operatingSystem);

  /// הפלטפורמה שהמראה נקראת בה — ראו [load]. `null` = פלטפורמה שאין לה
  /// מסלול התקנה (לינוקס, שם רצות הבדיקות ב-CI), ואז אין סינון בכלל.
  final OtzariaTargetPlatform? _platform;

  /// `<dataDir>/mirror/app` — נוסע עם התוכנה על הכונן הנייד.
  final String mirrorDir;

  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;
  final OtzariaChangelogClient _changelogClient;

  static const String _metadataFileName = 'latest-release.json';

  /// 2 = שתי גרסאות לפי ערוץ. גרסה 1 (רשומה בודדת בשורש) עדיין נקראת —
  /// ראו [load].
  static const int _schemaVersion = 2;

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  /// קורא את הגרסאות שיושבות במראה. ערוץ חוזר ריק כשאין לו רשומה תקינה:
  /// אין קובץ מטא־דאטה, הוא פגום, או שקובץ ההתקנה שהוא מצביע עליו חסר/
  /// בגודל שגוי (הורדה שנקטעה). בכל המקרים האלה התשובה הנכונה זהה —
  /// "צריך להוריד". כל ערוץ נבדק בנפרד, כדי שרשומה פגומה באחד לא תפסול
  /// את השני.
  Future<MirroredOtzariaReleases> load() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return const MirroredOtzariaReleases();

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return const MirroredOtzariaReleases();
    }
    if (decoded is! Map<String, dynamic>) {
      return const MirroredOtzariaReleases();
    }

    // פורמט ישן: רשומה בודדת בשורש הקובץ. משויכת לערוץ לפי הדגל שלה, כדי
    // שכונן שנוצר בגרסה קודמת של הלאנצ'ר יישאר שמיש בלי הורדה מחדש.
    if (decoded['tagName'] is String) {
      final legacy = await _entryFrom(decoded);
      if (legacy == null) return const MirroredOtzariaReleases();
      return legacy.release.isPrerelease
          ? MirroredOtzariaReleases(prerelease: legacy)
          : MirroredOtzariaReleases(stable: legacy);
    }

    return _withoutDuplicateTag(
      stable: await _entryFrom(decoded[OtzariaReleaseChannel.stable.name]),
      prerelease:
          await _entryFrom(decoded[OtzariaReleaseChannel.prerelease.name]),
    );
  }

  /// אותו תג בשני הערוצים אינו בחירה אלא רישום כפול — הרשומה הלא-יציבה
  /// יורדת.
  ///
  /// זה מה שנשאר כשגרסה שירדה כלא-יציבה סומנה אחר כך כיציבה וסנכרון אחד
  /// כתב את הערוץ היציב אך לא הספיק לרוקן את השני (הורדה שנכשלה/בוטלה
  /// באמצע). הניקוי גם בקריאה ולא רק בכתיבה, כי כונן שכבר נשא מטא־דאטה
  /// כזאת מגיע למחשב מנותק שלעולם לא יריץ שם סנכרון.
  static MirroredOtzariaReleases _withoutDuplicateTag({
    MirroredOtzariaRelease? stable,
    MirroredOtzariaRelease? prerelease,
  }) =>
      MirroredOtzariaReleases(
        stable: stable,
        prerelease: prerelease?.release.tagName == stable?.release.tagName
            ? null
            : prerelease,
      );

  /// רשומת ערוץ בודדת מתוך המטא־דאטה, או `null` אם היא חסרה/פגומה/מצביעה
  /// על קובץ התקנה שאינו שם — **או שהיא של פלטפורמה אחרת**.
  ///
  /// הכונן נוסע בין מחשבים, ומי שהוריד בווינדוס נושא עליו `.exe` של Inno.
  /// בלי הפסילה כאן מסלול ההתקנה ב-macOS היה מנסה להריץ אותו ונופל
  /// ב-ProcessException; "אין מראה — יש להריץ הורדה" היא התשובה הנכונה,
  /// והממשק כבר יודע לומר אותה.
  Future<MirroredOtzariaRelease?> _entryFrom(Object? raw) async {
    if (raw is! Map<String, dynamic>) return null;

    final OtzariaRelease release;
    final String installerPath;
    try {
      release = OtzariaRelease.fromJson(raw);
      final relative = raw['installerPath'];
      if (relative is! String || relative.isEmpty) return null;
      // המראה נכתבת ב-POSIX ונקראת גם ב-Windows; `\` היסטורי מקובץ שנכתב
      // בווינדוס עדיין נתמך כדי לא לפסול מראה קיימת.
      installerPath =
          p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);
    } catch (_) {
      return null;
    }

    final platform = _platform;
    if (platform != null && release.installerKind.targetPlatform != platform) {
      return null;
    }

    final installer = File(installerPath);
    if (!await installer.exists()) return null;
    if (await installer.length() != release.installerSizeBytes) return null;

    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
    );
  }

  /// חבילות FULL שנשארו במראה מגרסה ישנה של הלאנצ'ר, שאינה נושאת אותן
  /// יותר. הן ~2GB כל אחת, ולכן [sync] מוחקת אותן — ו-`OtzariaManager`
  /// מדווח עליהן כדי שמודול התוכנה ירוץ גם על כונן שאין בו גרסה חדשה,
  /// אחרת "אין מה להוריד" היה משאיר אותן שם לנצח.
  Future<List<String>> staleFullPackages() async {
    final root = Directory(_installer.cacheDir);
    if (!await root.exists()) return const [];
    final found = <String>[];
    try {
      await for (final entity in root.list(recursive: true)) {
        if (entity is File &&
            OtzariaAssetSelector.isFullPackage(p.basename(entity.path))) {
          found.add(entity.path);
        }
      }
    } catch (_) {
      // סריקה best-effort: כונן שנשלף באמצע אינו סיבה להפיל בדיקת גרסה.
    }
    return found;
  }

  /// מוריד את שתי הגרסאות (יציבה, ו-pre-release כשהוא חדש ממנה) אל
  /// [mirrorDir] וכותב את המטא־דאטה. **הפעולה היחידה כאן שדורשת אינטרנט.**
  ///
  /// היציבה יורדת ראשונה בכוונה: היא ברירת המחדל, וכך כישלון בהורדת
  /// ה-pre-release לא משאיר את הכונן בלי גרסה להתקין. המטא־דאטה נכתבת
  /// מחדש אחרי כל הורדה שהסתיימה, וכל פעם רק על מה שכבר בדיסק במלואו —
  /// כדי ש-[load] לא תראה אף פעם מראה חצי-מוכנה.
  ///
  /// [onChannelStart] נקרא לפני כל הורדה, כדי שה-UI יוכל לומר איזו משתיהן
  /// יורדת כרגע (מד ההתקדמות מתאפס בין השתיים).
  ///
  /// חבילת FULL שירדה בגרסה ישנה של הלאנצ'ר **נמחקת כאן** — ראו
  /// [staleFullPackages].
  Future<MirroredOtzariaReleases> sync({
    void Function(int received, int total)? onDownloadProgress,
    void Function(OtzariaReleaseChannel channel)? onChannelStart,
    bool Function()? isCancelled,
  }) async {
    final online = await _releaseClient.fetchChannelReleases();

    // מתחילים ממה שכבר על הכונן: ערוץ שההורדה שלו נכשלה חייב להישאר
    // במטא־דאטה, אחרת הורדה חלקית מוחקת בחירת ערוץ שכבר הייתה למחשב
    // הלא-מקוון בזמן שקובץ ההתקנה שלה עדיין שם.
    //
    // אבל ערוץ שקריאה **מוצלחת** לא החזירה כלל הוא סיפור אחר: הוא כבר לא
    // קיים ברשת. זה בדיוק מה שקורה כש-pre-release מסומן בהמשך כיציב —
    // הוא עובר לערוץ היציב וה-API מפסיק להחזיר לא-יציב. השארתו כאן הותירה
    // בחירת ערוץ מדומה בין שתי רשומות שמצביעות על אותו קובץ, ואת קובצי
    // ההתקנה הישנים על הכונן לנצח. איפוס כאן, ו-`pruneCacheExcept` שבסוף
    // מוחק את מה שכבר אינו מוזכר.
    final existing = await load();
    var stable = online.stable == null ? null : existing.stable;
    var prerelease = online.prerelease == null ? null : existing.prerelease;

    for (final channel in OtzariaReleaseChannel.values) {
      final release = online[channel];
      if (release == null) continue;

      onChannelStart?.call(channel);
      final mirrored = await _downloadToMirror(
        release,
        onDownloadProgress,
        isCancelled,
      );
      if (channel == OtzariaReleaseChannel.stable) {
        stable = mirrored;
        // הגרסה שהייתה לא-יציבה סומנה כיציבה: הרשומה הישנה שנשמרה מהדיסק
        // מצביעה עכשיו על אותו תג בדיוק, ובלי הניקוי היא הייתה מייצרת
        // "בחירת ערוץ" בין שתי רשומות של אותו קובץ אם הערוץ השני לא ירד.
        if (prerelease?.release.tagName == mirrored.release.tagName) {
          prerelease = null;
        }
      } else {
        prerelease = mirrored;
      }
      await _writeMetadata(stable: stable, prerelease: prerelease);
    }

    final result = _withoutDuplicateTag(stable: stable, prerelease: prerelease);
    // קובצי התקנה של גרסאות שכבר אינן במטא־דאטה אינם שווים את המקום על
    // הכונן הנייד. קבוצת שמירה ריקה, לעומת זאת, פירושה "מחק את הכול" —
    // ותשובת API ריקה (דף שכולו טיוטות) אינה עילה לרוקן כונן.
    if (result.all.isNotEmpty) {
      await _installer.pruneCacheExcept(
        keepTagNames: {for (final e in result.all) e.release.tagName},
      );
    }
    // `pruneCacheExcept` מנקה תגים שלמים בלבד, וחבילת FULL ישנה יושבת
    // דווקא בתג שנשמר — לצד המתקין הרגיל.
    for (final path in await staleFullPackages()) {
      await _deleteQuietly(path);
    }
    return result;
  }

  Future<MirroredOtzariaRelease> _downloadToMirror(
    OtzariaRelease release,
    void Function(int received, int total)? onDownloadProgress,
    bool Function()? isCancelled,
  ) async {
    final notes = await _changelogClient.notesFor(release.tagName);
    final withNotes =
        notes == null ? release : release.copyWithReleaseNotes(notes);

    final installerPath = await _installer.ensureCached(
      release: withNotes,
      onDownloadProgress: onDownloadProgress,
      isCancelled: isCancelled,
    );

    return MirroredOtzariaRelease(
      release: withNotes,
      installerPath: installerPath,
    );
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ניקוי best-effort — כישלון כאן לא אמור להפיל הורדה שהצליחה.
    }
  }

  Future<void> _writeMetadata({
    MirroredOtzariaRelease? stable,
    MirroredOtzariaRelease? prerelease,
  }) async {
    // **תמיד עם `/`** — מראה שנבנתה בווינדוס נפתחת גם ב-macOS, בדיוק כמו
    // הנתיבים בקטלוג התוספים (`PluginMirrorStore.relativePath`).
    String relative(String path) =>
        p.relative(path, from: mirrorDir).replaceAll(r'\', '/');

    Map<String, dynamic> entry(MirroredOtzariaRelease e) =>
        e.release.toJson()..['installerPath'] = relative(e.installerPath);

    await Directory(mirrorDir).create(recursive: true);
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'syncedAt': DateTime.now().toIso8601String(),
      if (stable != null) OtzariaReleaseChannel.stable.name: entry(stable),
      if (prerelease != null)
        OtzariaReleaseChannel.prerelease.name: entry(prerelease),
    };

    // כתיבה אטומית — הפסקת חשמל לא תשאיר JSON חצי־כתוב שייקרא כמראה תקינה.
    final temp = File('$_metadataPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await temp.rename(_metadataPath);
  }
}
