import 'dart:convert';
import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart'
    show writeStringAtomically;
import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';
import '../models/otzaria_release_channel.dart';
import '../models/otzaria_update_check_result.dart';
import 'otzaria_asset_selector.dart';
import 'otzaria_changelog_client.dart';
import 'otzaria_installer.dart';
import 'otzaria_release_client.dart';

class MirroredOtzariaRelease {
  const MirroredOtzariaRelease({
    required this.release,
    required this.installerPath,
    this.newerThanStableTag,
  });

  final OtzariaRelease release;
  final String installerPath;
  final String? newerThanStableTag;
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
  static const String _platformsKey = 'platforms';
  static const String _newerThanStableKey = 'newerThanStable';

  static const int _schemaVersion = 2;

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  Future<MirroredOtzariaReleases> load() async {
    final decoded = await _readMetadata();
    if (decoded == null) return const MirroredOtzariaReleases();
    final channels = _ownChannels(decoded);

    if (channels['tagName'] is String) {
      final legacy = await _entryFrom(channels);
      if (legacy == null) return const MirroredOtzariaReleases();
      return legacy.release.isPrerelease
          ? MirroredOtzariaReleases(prerelease: legacy)
          : MirroredOtzariaReleases(stable: legacy);
    }

    return _withoutStalePrerelease(
      stable: await _entryFrom(channels[OtzariaReleaseChannel.stable.name]),
      prerelease: await _entryFrom(
        channels[OtzariaReleaseChannel.prerelease.name],
      ),
    );
  }

  Future<Set<String>> otherPlatformTagNames() async =>
      _tagNamesIn(_otherPlatforms(await _readMetadata(), _platform));

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

  Map<String, dynamic> _ownChannels(Map<String, dynamic> decoded) {
    final platforms = decoded[_platformsKey];
    final own =
        platforms is Map<String, dynamic> ? platforms[_platform?.name] : null;
    return own is Map<String, dynamic> ? own : decoded;
  }

  static Map<String, Map<String, dynamic>> _otherPlatforms(
    Map<String, dynamic>? decoded,
    OtzariaTargetPlatform? here,
  ) {
    final others = <String, Map<String, dynamic>>{};
    if (decoded == null || here == null) return others;

    final platforms = decoded[_platformsKey];
    final listed = platforms is Map<String, dynamic>
        ? platforms
        : const <String, dynamic>{};
    for (final MapEntry(:key, :value) in listed.entries) {
      if (key != here.name && value is Map<String, dynamic>) {
        others[key] = value;
      }
    }

    for (final channel in OtzariaReleaseChannel.values) {
      final raw = decoded[channel.name];
      final platform = _targetPlatformOf(raw);
      if (platform == null ||
          platform == here ||
          listed.containsKey(platform.name)) {
        continue;
      }
      (others[platform.name] ??= {})[channel.name] = raw;
    }
    return others;
  }

  static OtzariaTargetPlatform? _targetPlatformOf(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return OtzariaRelease.fromJson(raw).installerKind.targetPlatform;
    } catch (_) {
      return null;
    }
  }

  static Set<String> _tagNamesIn(Map<String, Map<String, dynamic>> platforms) =>
      {
        for (final channels in platforms.values)
          for (final entry in channels.values)
            if (entry is Map<String, dynamic> && entry['tagName'] is String)
              entry['tagName'] as String,
      };

  static MirroredOtzariaReleases _withoutStalePrerelease({
    MirroredOtzariaRelease? stable,
    MirroredOtzariaRelease? prerelease,
  }) =>
      MirroredOtzariaReleases(
        stable: stable,
        prerelease: stable != null &&
                prerelease != null &&
                _isStalePrerelease(stable, prerelease)
            ? null
            : prerelease,
      );

  static bool _isStalePrerelease(
    MirroredOtzariaRelease stable,
    MirroredOtzariaRelease prerelease,
  ) {
    final stableTag = stable.release.tagName;
    if (prerelease.release.tagName == stableTag) return true;
    if (prerelease.newerThanStableTag == stableTag) return false;
    final prereleaseDate = prerelease.release.publishedAt;
    final stableDate = stable.release.publishedAt;
    if (prereleaseDate != null && stableDate != null) {
      return prereleaseDate.isBefore(stableDate);
    }
    return OtzariaUpdateCheckResult.compareVersions(
          prerelease.release.tagName,
          stableTag,
        ) <
        0;
  }

  Future<MirroredOtzariaRelease?> _entryFrom(Object? raw) async {
    if (raw is! Map<String, dynamic>) return null;

    final OtzariaRelease release;
    final String installerPath;
    try {
      release = OtzariaRelease.fromJson(raw);
      final relative = raw['installerPath'];
      if (relative is! String || relative.isEmpty) return null;
      installerPath = p.joinAll([
        mirrorDir,
        ...relative.split(RegExp(r'[/\\]')),
      ]);
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

    final newerThanStable = raw[_newerThanStableKey];
    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
      newerThanStableTag: newerThanStable is String ? newerThanStable : null,
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

  Future<MirroredOtzariaReleases> sync({
    OtzariaChannelReleases? online,
    void Function(int received, int total)? onDownloadProgress,
    void Function(OtzariaReleaseChannel channel)? onChannelStart,
    bool Function()? isCancelled,
  }) async {
    online ??= await _releaseClient.fetchChannelReleases();

    final existing = await load();
    final here = _platform ??
        (online.stable ??
                online.prerelease ??
                existing.stable?.release ??
                existing.prerelease?.release)
            ?.installerKind
            .targetPlatform;
    final others = _otherPlatforms(await _readMetadata(), here);
    var stable = existing.stable?.release.tagName == online.prerelease?.tagName
        ? null
        : existing.stable;
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
        if (prerelease != null && _isStalePrerelease(mirrored, prerelease)) {
          prerelease = null;
        }
      } else {
        prerelease = MirroredOtzariaRelease(
          release: mirrored.release,
          installerPath: mirrored.installerPath,
          newerThanStableTag: online.stable?.tagName,
        );
      }
      await _writeMetadata(
        stable: stable,
        prerelease: prerelease,
        here: here,
        others: others,
      );
    }

    final result = MirroredOtzariaReleases(
      stable: stable,
      prerelease: prerelease,
    );
    if (result.all.isNotEmpty) {
      await _installer.pruneCacheExcept(
        keepTagNames: {
          for (final e in result.all) e.release.tagName,
          ..._tagNamesIn(others),
        },
      );
    }
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
    OtzariaTargetPlatform? here,
    Map<String, Map<String, dynamic>> others = const {},
  }) async {
    String relative(String path) =>
        p.relative(path, from: mirrorDir).replaceAll(r'\', '/');

    Map<String, dynamic> entry(MirroredOtzariaRelease e) => e.release.toJson()
      ..['installerPath'] = relative(e.installerPath)
      ..addAll({
        if (e.newerThanStableTag case final tag?) _newerThanStableKey: tag,
      });

    await Directory(mirrorDir).create(recursive: true);
    final channels = <String, dynamic>{
      if (stable != null) OtzariaReleaseChannel.stable.name: entry(stable),
      if (prerelease != null)
        OtzariaReleaseChannel.prerelease.name: entry(prerelease),
    };
    final json = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'syncedAt': DateTime.now().toIso8601String(),
      ...channels,
      _platformsKey: {...others, if (here != null) here.name: channels},
    };

    await writeStringAtomically(
      _metadataPath,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }
}
