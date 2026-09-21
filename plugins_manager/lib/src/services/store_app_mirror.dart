import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/store_app_release.dart';
import 'plugin_store_client.dart';

/// קובץ ההרצה של תוכנת החנות שכבר יושב על הכונן, עם הגרסה שלו.
class MirroredStoreApp {
  const MirroredStoreApp({required this.release, required this.filePath});

  final StoreAppRelease release;

  /// נתיב מלא לקובץ בדיסק — הייצוא מעתיק מכאן, בלי רשת.
  final String filePath;
}

/// המראה המקומית של **תוכנת** חנות התוספים — `mirror/store-app/`, לצד
/// מראות הספרייה, התוכנה, התוספים והלאנצ'ר.
///
/// אותה חלוקה כמו בכל השאר: [sync] היא הפעולה היחידה שנוגעת ברשת, ו-[load]
/// עונה מהדיסק — כך המחשב המנותק מייצא את התוכנה שהורדה במחשב המקוון.
///
/// **הקובץ הוא ווינדוס בלבד** ואין לו מקבילה ל-macOS; שם [load] מחזיר את מה
/// שיש והממשק הוא שמסתיר את הפעולה.
class StoreAppMirror {
  StoreAppMirror({
    required this.mirrorDir,
    http.Client? httpClient,
    this.connectTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  /// `<dataDir>/mirror/store-app` — נוסע עם התוכנה על הכונן הנייד.
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

  /// מה שיושב במראה, או `null` כשאין: אין קובץ מטא-דאטה, הוא פגום, או
  /// שהקובץ שהוא מצביע עליו חסר/בגודל שגוי (הורדה שנקטעה). בכל המקרים
  /// התשובה הנכונה זהה — "צריך להוריד".
  Future<MirroredStoreApp?> load() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final release = StoreAppRelease.fromJson(decoded['release']);
    if (release == null) return null;

    final relative = decoded['filePath'];
    if (relative is! String || relative.isEmpty) return null;
    // המראה נכתבת ב-POSIX ונקראת גם בווינדוס, כמו `LauncherUpdateMirror`.
    final filePath =
        p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);

    final downloaded = File(filePath);
    if (!await downloaded.exists()) return null;
    if (await downloaded.length() != release.sizeBytes) return null;

    return MirroredStoreApp(release: release, filePath: filePath);
  }

  /// מוריד את [release] אל המראה וכותב את המטא-דאטה. **הפעולה היחידה כאן
  /// שדורשת אינטרנט.**
  ///
  /// המטא-דאטה נכתבת רק אחרי שהקובץ כולו בדיסק, ולכן [load] לא רואה מראה
  /// חצי-מוכנה. קובץ שכבר קיים בגודל הנכון אינו יורד שוב.
  Future<MirroredStoreApp> sync(
    StoreAppRelease release, {
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
    return MirroredStoreApp(release: release, filePath: filePath);
  }

  /// גרסאות קודמות של התוכנה אינן שוות מקום על הכונן — מייצאים תמיד את
  /// האחרונה.
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
    required StoreAppRelease release,
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
    final strings = AppL10n.strings.pluginsDomain;
    final response = await _httpClient
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(connectTimeout);

    if (response.statusCode != 200) {
      throw PluginStoreException(
        strings.httpStatusFor(response.statusCode, url),
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
      throw PluginStoreException(
        AppL10n.strings.appDomain
            .installerSizeMismatch(received, expectedSizeBytes),
      );
    }
  }

  void dispose() => _httpClient.close();
}
