import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'launcher_release.dart';
import 'launcher_release_client.dart';

/// גרסת לאנצ'ר שיושבת מוכנה בתיקייה שלצד התוכנה: המטא-דאטה שלה, וקובץ
/// ההרצה שכבר הורד.
class MirroredLauncherRelease {
  const MirroredLauncherRelease({
    required this.release,
    required this.filePath,
  });

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
    String? operatingSystem,
    this.connectTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client(),
       _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  /// הפלטפורמה שהמראה נקראת בה — ראו [load]. מוזרקת בבדיקות.
  final String _operatingSystem;

  /// `<dataDir>/mirror/launcher` — נוסע עם התוכנה על הכונן הנייד.
  final String mirrorDir;

  Duration connectTimeout;
  Duration stallTimeout;

  final http.Client _httpClient;

  static const String _metadataFileName = 'latest-release.json';
  static const String _filesDirName = 'files';
  static const String _platformsKey = 'platforms';
  static const int _schemaVersion = 1;

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  Future<MirroredLauncherRelease?> load() async {
    final decoded = await _readMetadata();
    if (decoded == null) return null;
    final own = _ownEntry(decoded);

    final LauncherRelease release;
    final String filePath;
    try {
      final raw = own['release'];
      if (raw is! Map<String, dynamic>) return null;
      release = LauncherRelease.fromJson(raw);

      final relative = own['filePath'];
      if (relative is! String || relative.isEmpty) return null;
      filePath = p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);
    } catch (_) {
      return null;
    }

    if (!LauncherReleaseClient.matchesPlatform(
      release.assetName,
      _operatingSystem,
    )) {
      return null;
    }

    final downloaded = File(filePath);
    if (!await downloaded.exists()) return null;
    if (await downloaded.length() != release.sizeBytes) return null;

    return MirroredLauncherRelease(release: release, filePath: filePath);
  }

  Future<MirroredLauncherRelease> sync(
    LauncherRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final releaseDir = p.join(mirrorDir, _filesDirName, release.tagName);
    final filePath = p.join(releaseDir, release.assetName);
    final file = File(filePath);
    final expected = release.sha256;

    final alreadyThere =
        await file.exists() &&
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
        throw LauncherUpdateException(
          AppL10n.strings.launcherUpdate.digestMismatch,
        );
      }
    }

    final others = _otherPlatforms(await _readMetadata());
    await _writeMetadata(release: release, filePath: filePath, others: others);
    await _pruneExcept({
      release.tagName,
      for (final entry in others.values)
        if (entry['release'] case {'tagName': final String tag}) tag,
    });
    return MirroredLauncherRelease(release: release, filePath: filePath);
  }

  Future<void> verify(MirroredLauncherRelease mirrored) async {
    final expected = mirrored.release.sha256;
    if (expected == null) return;
    if (await _sha256Of(mirrored.filePath) == expected) return;
    try {
      await File(mirrored.filePath).delete();
    } catch (_) {}
    throw LauncherUpdateException(
      AppL10n.strings.launcherUpdate.digestMismatch,
    );
  }

  static Future<String> _sha256Of(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<Map<String, dynamic>?> _readMetadata() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _ownEntry(Map<String, dynamic> decoded) {
    final platforms = decoded[_platformsKey];
    final own = platforms is Map<String, dynamic>
        ? platforms[_operatingSystem]
        : null;
    return own is Map<String, dynamic> ? own : decoded;
  }

  Map<String, Map<String, dynamic>> _otherPlatforms(
    Map<String, dynamic>? decoded,
  ) {
    final others = <String, Map<String, dynamic>>{};
    if (decoded == null) return others;

    final platforms = decoded[_platformsKey];
    if (platforms is Map<String, dynamic>) {
      for (final MapEntry(:key, :value) in platforms.entries) {
        if (key != _operatingSystem && value is Map<String, dynamic>) {
          others[key] = value;
        }
      }
    }

    final release = decoded['release'];
    if (release case {'assetName': final String assetName}) {
      for (final os in const ['windows', 'macos']) {
        if (os != _operatingSystem &&
            !others.containsKey(os) &&
            LauncherReleaseClient.matchesPlatform(assetName, os)) {
          others[os] = {'release': release, 'filePath': decoded['filePath']};
        }
      }
    }
    return others;
  }

  Future<void> _pruneExcept(Set<String> keepTagNames) async {
    final dir = Directory(p.join(mirrorDir, _filesDirName));
    if (!await dir.exists()) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is Directory &&
            !keepTagNames.contains(p.basename(entry.path))) {
          await entry.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _writeMetadata({
    required LauncherRelease release,
    required String filePath,
    Map<String, Map<String, dynamic>> others = const {},
  }) async {
    await Directory(mirrorDir).create(recursive: true);
    final entry = <String, dynamic>{
      'release': release.toJson(),
      'filePath': p.relative(filePath, from: mirrorDir).replaceAll(r'\', '/'),
    };
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'syncedAt': DateTime.now().toIso8601String(),
      ...entry,
      _platformsKey: {...others, _operatingSystem: entry},
    };

    final temp = File('$_metadataPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await temp.rename(_metadataPath);
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
      statusError: (status) => LauncherUpdateException(
        AppL10n.strings.launcherUpdate.downloadFailed(status),
      ),
      sizeError: (actual, expected) => LauncherUpdateException(
        AppL10n.strings.launcherUpdate.sizeMismatch(actual, expected),
      ),
    );
  }

  void dispose() => _httpClient.close();
}
