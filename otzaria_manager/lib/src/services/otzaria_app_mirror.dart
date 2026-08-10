import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';
import '../models/otzaria_release_channel.dart';
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
  })  : _releaseClient = releaseClient,
        _installer = installer,
        _changelogClient = changelogClient ?? OtzariaChangelogClient();

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

    return MirroredOtzariaReleases(
      stable: await _entryFrom(decoded[OtzariaReleaseChannel.stable.name]),
      prerelease:
          await _entryFrom(decoded[OtzariaReleaseChannel.prerelease.name]),
    );
  }

  /// רשומת ערוץ בודדת מתוך המטא־דאטה, או `null` אם היא חסרה/פגומה/מצביעה
  /// על קובץ התקנה שאינו שם.
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

    final installer = File(installerPath);
    if (!await installer.exists()) return null;
    if (await installer.length() != release.installerSizeBytes) return null;

    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
    );
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
  Future<MirroredOtzariaReleases> sync({
    void Function(int received, int total)? onDownloadProgress,
    void Function(OtzariaReleaseChannel channel)? onChannelStart,
  }) async {
    final online = await _releaseClient.fetchChannelReleases();

    // מתחילים ממה שכבר על הכונן: ערוץ שההורדה שלו נכשלה (או שאינו ב-API
    // כרגע) חייב להישאר במטא־דאטה, אחרת הורדה חלקית מוחקת בחירת ערוץ
    // שכבר הייתה למחשב הלא-מקוון בזמן שקובץ ההתקנה שלה עדיין שם.
    final existing = await load();
    var stable = existing.stable;
    var prerelease = existing.prerelease;

    for (final channel in OtzariaReleaseChannel.values) {
      final release = online[channel];
      if (release == null) continue;

      onChannelStart?.call(channel);
      final mirrored = await _downloadToMirror(release, onDownloadProgress);
      if (channel == OtzariaReleaseChannel.stable) {
        stable = mirrored;
      } else {
        prerelease = mirrored;
      }
      await _writeMetadata(stable: stable, prerelease: prerelease);
    }

    final result =
        MirroredOtzariaReleases(stable: stable, prerelease: prerelease);
    // קובצי התקנה של גרסאות שכבר אינן במטא־דאטה אינם שווים את המקום על
    // הכונן הנייד. קבוצת שמירה ריקה, לעומת זאת, פירושה "מחק את הכול" —
    // ותשובת API ריקה (דף שכולו טיוטות) אינה עילה לרוקן כונן.
    if (result.all.isNotEmpty) {
      await _installer.pruneCacheExcept(
        keepTagNames: {for (final e in result.all) e.release.tagName},
      );
    }
    return result;
  }

  Future<MirroredOtzariaRelease> _downloadToMirror(
    OtzariaRelease release,
    void Function(int received, int total)? onDownloadProgress,
  ) async {
    final notes = await _changelogClient.notesFor(release.tagName);
    final withNotes =
        notes == null ? release : release.copyWithReleaseNotes(notes);

    final installerPath = await _installer.ensureCached(
      release: withNotes,
      onDownloadProgress: onDownloadProgress,
    );
    return MirroredOtzariaRelease(
      release: withNotes,
      installerPath: installerPath,
    );
  }

  Future<void> _writeMetadata({
    MirroredOtzariaRelease? stable,
    MirroredOtzariaRelease? prerelease,
  }) async {
    Map<String, dynamic> entry(MirroredOtzariaRelease e) => e.release.toJson()
      // **תמיד עם `/`** — מראה שנבנתה בווינדוס נפתחת גם ב-macOS, בדיוק כמו
      // הנתיבים בקטלוג התוספים (`PluginMirrorStore.relativePath`).
      ..['installerPath'] =
          p.relative(e.installerPath, from: mirrorDir).replaceAll(r'\', '/');

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
