import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
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

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  /// `true` כשיש מטא-דאטה של הורדה שהצליחה אבל הקובץ עצמו איננו.
  ///
  /// ההבחנה הזאת היא כל ההבדל בין "עוד לא הורדת" לבין "הורדת, ומשהו מחק
  /// את זה" — ובלעדיה ההודעה שלחה את המשתמש להוריד שוב אל תוך אותה מחיקה.
  Future<bool> get wasRemoved async =>
      await File(_metadataPath).exists() && await load() == null;

  /// מה שיושב במראה, או `null` כשאין: אין קובץ מטא-דאטה, הוא פגום, או
  /// שהקובץ שהוא מצביע עליו חסר/בגודל שגוי (הורדה שנקטעה, או אנטי-וירוס
  /// שמחק — ראו [wasRemoved]).
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

    final filePath = _recordedFilePath(decoded);
    if (filePath == null) return null;

    final downloaded = File(filePath);
    if (!await downloaded.exists()) return null;
    if (await downloaded.length() != release.sizeBytes) return null;

    return MirroredStoreApp(release: release, filePath: filePath);
  }

  String? _recordedFilePath(Map<dynamic, dynamic> metadata) {
    final relative = metadata['filePath'];
    if (relative is! String || relative.isEmpty) return null;
    return p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);
  }

  Future<void> _forgetMetadataPointingTo(String filePath) async {
    final file = File(_metadataPath);
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final recorded = _recordedFilePath(decoded);
      if (recorded != null && p.equals(recorded, filePath)) {
        await file.delete();
      }
    } on FileSystemException {
      return;
    } on FormatException {
      return;
    }
  }

  Future<MirroredStoreApp> sync(
    StoreAppRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final releaseDir = p.join(mirrorDir, _filesDirName, release.tagName);
    final filePath = p.join(releaseDir, release.assetName);
    final file = File(filePath);
    final expected = release.sha256;

    final alreadyThere = await file.exists() &&
        await file.length() == release.sizeBytes &&
        (expected == null || await _sha256Of(filePath) == expected);
    if (!alreadyThere) {
      await Directory(releaseDir).create(recursive: true);
      final result = await _download(
        url: release.downloadUrl,
        destinationPath: filePath,
        expectedSizeBytes: release.sizeBytes,
        calculateSha256: expected != null,
        onProgress: onProgress,
      );
      if (expected != null && result.sha256 != expected) {
        await file.delete();
        await _forgetMetadataPointingTo(filePath);
        throw PluginStoreException(
          AppL10n.strings.customAppsDomain
              .downloadDigestMismatch(release.assetName),
        );
      }
    }

    await _writeMetadata(release: release, filePath: filePath);
    await _pruneExcept(release.tagName);
    return MirroredStoreApp(release: release, filePath: filePath);
  }

  Future<bool> verify(MirroredStoreApp mirrored) async {
    final expected = mirrored.release.sha256;
    if (expected == null) return true;
    try {
      return await _sha256Of(mirrored.filePath) == expected;
    } on FileSystemException {
      return false;
    }
  }

  static Future<String> _sha256Of(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

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
      'filePath': p.relative(filePath, from: mirrorDir).replaceAll(r'\', '/'),
    };

    await writeStringAtomically(
      _metadataPath,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  Future<FileDownloadResult> _download({
    required String url,
    required String destinationPath,
    required int expectedSizeBytes,
    required bool calculateSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    return downloadFile(
      client: _httpClient,
      url: url,
      destinationPath: destinationPath,
      expectedSize: expectedSizeBytes,
      connectTimeout: connectTimeout,
      stallTimeout: stallTimeout,
      onProgress: onProgress,
      calculateSha256: calculateSha256,
      statusError: (status) => PluginStoreException(
          AppL10n.strings.pluginsDomain.httpStatusFor(status, url)),
      sizeError: (actual, expected) => PluginStoreException(
          AppL10n.strings.appDomain.installerSizeMismatch(actual, expected)),
    );
  }

  void dispose() => _httpClient.close();
}
