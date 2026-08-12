import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'launcher_release.dart';
import 'launcher_release_client.dart';

/// גרסת לאנצ'ר שיושבת מוכנה בתיקייה שלצד התוכנה: המטא-דאטה שלה, וקובץ
/// ההרצה שכבר הורד.
class MirroredLauncherRelease {
  const MirroredLauncherRelease(
      {required this.release, required this.filePath});

  final LauncherRelease release;

  /// נתיב מלא לקובץ בדיסק — ההתקנה קוראת מכאן, בלי רשת.
  final String filePath;
}

/// המראה המקומית של **הלאנצ'ר עצמו** — `mirror/launcher/`, לצד המראות של
/// אוצריא, הספרייה והתוספים.
///
/// אותה חלוקה כמו בכל השאר: [sync] היא הפעולה היחידה שנוגעת ברשת, ו-[load]
/// עונה מהדיסק — כך גם המחשב המנותק יכול להתקין את הגרסה שהורדה במחשב
/// המקוון, בלי לחזור לרשת.
class LauncherUpdateMirror {
  LauncherUpdateMirror({
    required this.mirrorDir,
    http.Client? httpClient,
    this.connectTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  /// `<dataDir>/mirror/launcher` — נוסע עם התוכנה על הכונן הנייד.
  final String mirrorDir;

  Duration connectTimeout;
  Duration stallTimeout;

  final http.Client _httpClient;

  static const String _metadataFileName = 'latest-release.json';
  static const String _filesDirName = 'files';
  static const int _schemaVersion = 1;

  /// כמה בייטים מותר לצבור ב-`IOSink` לפני שממתינים לכתיבה בפועל — `add`
  /// אינו מפעיל לחץ-נגד, וכונן USB איטי היה מצטבר ב-RAM.
  static const int _writeBufferBytes = 4 << 20;

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  /// הגרסה שיושבת במראה, או `null` כשאין: אין קובץ מטא-דאטה, הוא פגום, או
  /// שהקובץ שהוא מצביע עליו חסר/בגודל שגוי (הורדה שנקטעה). בכל המקרים
  /// התשובה הנכונה זהה — "צריך להוריד".
  Future<MirroredLauncherRelease?> load() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final LauncherRelease release;
    final String filePath;
    try {
      final raw = decoded['release'];
      if (raw is! Map<String, dynamic>) return null;
      release = LauncherRelease.fromJson(raw);

      final relative = decoded['filePath'];
      if (relative is! String || relative.isEmpty) return null;
      // המראה נכתבת ב-POSIX ונקראת גם בווינדוס, כמו `installerPath` של
      // `OtzariaAppMirror`; `\` היסטורי עדיין נתמך.
      filePath = p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);
    } catch (_) {
      return null;
    }

    final downloaded = File(filePath);
    if (!await downloaded.exists()) return null;
    if (await downloaded.length() != release.sizeBytes) return null;

    return MirroredLauncherRelease(release: release, filePath: filePath);
  }

  /// מוריד את [release] אל המראה וכותב את המטא-דאטה. **הפעולה היחידה כאן
  /// שדורשת אינטרנט.**
  ///
  /// המטא-דאטה נכתבת רק אחרי שהקובץ כולו בדיסק, ולכן [load] לא רואה מראה
  /// חצי-מוכנה. קובץ שכבר קיים בגודל הנכון אינו יורד שוב.
  Future<MirroredLauncherRelease> sync(
    LauncherRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final releaseDir = p.join(mirrorDir, _filesDirName, release.tagName);
    final filePath = p.join(releaseDir, release.assetName);
    final file = File(filePath);

    final alreadyThere =
        await file.exists() && await file.length() == release.sizeBytes;
    if (!alreadyThere) {
      await Directory(releaseDir).create(recursive: true);
      await _download(
        url: release.downloadUrl,
        destinationPath: filePath,
        expectedSizeBytes: release.sizeBytes,
        onProgress: onProgress,
      );
    }

    await _writeMetadata(release: release, filePath: filePath);
    await _pruneExcept(release.tagName);
    return MirroredLauncherRelease(release: release, filePath: filePath);
  }

  /// גרסאות לאנצ'ר קודמות אינן שוות מקום על הכונן — הגרסה שרצה כבר על
  /// הדיסק בתור קובץ ההרצה עצמו.
  Future<void> _pruneExcept(String keepTagName) async {
    final dir = Directory(p.join(mirrorDir, _filesDirName));
    if (!await dir.exists()) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is Directory && p.basename(entry.path) != keepTagName) {
          await entry.delete(recursive: true);
        }
      }
    } catch (_) {
      // ניקוי best-effort — כישלון כאן לא פוסל הורדה שהצליחה.
    }
  }

  Future<void> _writeMetadata({
    required LauncherRelease release,
    required String filePath,
  }) async {
    await Directory(mirrorDir).create(recursive: true);
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'syncedAt': DateTime.now().toIso8601String(),
      'release': release.toJson(),
      // **תמיד עם `/`** — מראה שנבנתה בווינדוס נפתחת גם ב-macOS.
      'filePath': p.relative(filePath, from: mirrorDir).replaceAll(r'\', '/'),
    };

    // כתיבה אטומית — הפסקת חשמל לא תשאיר JSON חצי-כתוב.
    final temp = File('$_metadataPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await temp.rename(_metadataPath);
  }

  Future<void> _download({
    required String url,
    required String destinationPath,
    required int expectedSizeBytes,
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request).timeout(connectTimeout);

    if (response.statusCode != 200) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.downloadFailed(response.statusCode),
      );
    }

    final sink = File(destinationPath).openWrite();
    var received = 0;
    var buffered = 0;
    try {
      // `timeout` על הזרם ולא רק על ה-send: חיבור שנפתח ואז נשתק היה תוקע
      // את ההורדה בלי גבול.
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        buffered += chunk.length;
        onProgress?.call(received, expectedSizeBytes);
        if (buffered >= _writeBufferBytes) {
          buffered = 0;
          await sink.flush();
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // קובץ חלקי חייב להיעלם: הריצה הבאה בודקת "כבר יש?" לפי גודל. סוגרים
      // לפני המחיקה — בווינדוס handle פתוח חוסם אותה.
      try {
        await sink.close();
      } catch (_) {}
      try {
        await File(destinationPath).delete();
      } catch (_) {}
      rethrow;
    }

    if (expectedSizeBytes > 0 && received != expectedSizeBytes) {
      try {
        await File(destinationPath).delete();
      } catch (_) {}
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate
            .sizeMismatch(received, expectedSizeBytes),
      );
    }
  }

  void close() => _httpClient.close();
}
