import 'dart:convert';
import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart'
    show writeStringAtomically;
import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';
import '../models/otzaria_releases.dart';
import 'otzaria_asset_selector.dart';
import 'otzaria_changelog_client.dart';
import 'otzaria_installer.dart';
import 'otzaria_release_client.dart';
import 'windows_arch.dart';

class MirroredOtzariaRelease {
  const MirroredOtzariaRelease({
    required this.release,
    required this.installerPath,
  });

  final OtzariaRelease release;
  final String installerPath;
}

typedef MirroredOtzariaReleases = OtzariaReleases<MirroredOtzariaRelease>;

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

  final OtzariaTargetPlatform? _platform;

  final String mirrorDir;

  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;
  final OtzariaChangelogClient _changelogClient;

  static const String _metadataFileName = 'latest-release.json';
  static const String _platformsKey = 'platforms';
  static const String _missingAssetTagsKey = 'missingAssetTags';

  static String platformKey(OtzariaTargetPlatform platform, OtzariaArch arch) =>
      platform == OtzariaTargetPlatform.windows && arch == OtzariaArch.arm64
          ? 'windows_arm64'
          : platform.name;

  static Set<String> _ownKeys(OtzariaTargetPlatform? platform) => {
        if (platform != null) platformKey(platform, OtzariaArch.x64),
        if (platform == OtzariaTargetPlatform.windows)
          platformKey(platform!, OtzariaArch.arm64),
      };

  static const int _schemaVersion = 3;

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  Future<MirroredOtzariaReleases> load({
    OtzariaArch arch = OtzariaArch.x64,
  }) async {
    final decoded = await _readMetadata();
    if (decoded == null) return const MirroredOtzariaReleases();
    final channels = _ownEntry(decoded, arch);
    if (channels == null || channels['source'] != 'github-latest') {
      return const MirroredOtzariaReleases();
    }

    return MirroredOtzariaReleases(
        latest: await _entryFrom(channels['latest'], arch));
  }

  Future<bool> lacksArm64Installers() async {
    if (_platform != OtzariaTargetPlatform.windows) return false;
    final decoded = await _readMetadata();
    if (decoded == null) return false;
    final x64 = await load();
    final arm = _ownEntry(decoded, OtzariaArch.arm64);
    final covered = <String>{
      ..._tagNamesIn({'arm64': arm ?? const {}}),
      if (arm?[_missingAssetTagsKey] case final List<dynamic> tags)
        ...tags.whereType<String>(),
    };
    return x64.all.any((entry) => !covered.contains(entry.release.tagName));
  }

  Future<Set<String>> otherPlatformTagNames() async =>
      _tagNamesIn(Map.fromEntries(
        _otherPlatforms(await _readMetadata(), _platform)
            .entries
            .where((entry) => entry.value['source'] == 'github-latest'),
      ));

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

  Map<String, dynamic>? _ownEntry(
    Map<String, dynamic> decoded,
    OtzariaArch arch,
  ) {
    final platforms = decoded[_platformsKey];
    final platform = _platform;
    final own = platforms is Map<String, dynamic> && platform != null
        ? platforms[platformKey(platform, arch)]
        : null;
    if (own is Map<String, dynamic>) return own;
    return arch == OtzariaArch.x64 ? decoded : null;
  }

  static Map<String, Map<String, dynamic>> _otherPlatforms(
    Map<String, dynamic>? decoded,
    OtzariaTargetPlatform? here,
  ) {
    final others = <String, Map<String, dynamic>>{};
    if (decoded == null || here == null) return others;

    final own = _ownKeys(here);
    final platforms = decoded[_platformsKey];
    final listed = platforms is Map<String, dynamic>
        ? platforms
        : const <String, dynamic>{};
    for (final MapEntry(:key, :value) in listed.entries) {
      if (!own.contains(key) && value is Map<String, dynamic>) {
        others[key] = value;
      }
    }

    final legacy = decoded['latest'];
    if (decoded['source'] == 'github-latest' &&
        legacy is Map<String, dynamic>) {
      final platform = _targetPlatformOf(legacy);
      if (platform != null &&
          platform != here &&
          !others.containsKey(platform.name)) {
        others[platform.name] = {'source': 'github-latest', 'latest': legacy};
      }
    }
    return others;
  }

  static OtzariaTargetPlatform? _targetPlatformOf(Map<String, dynamic> raw) {
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

  Future<MirroredOtzariaRelease?> _entryFrom(
    Object? raw,
    OtzariaArch arch,
  ) async {
    if (raw is! Map<String, dynamic> || raw['isPrerelease'] == true) {
      return null;
    }

    final OtzariaRelease release;
    final String installerPath;
    try {
      release = OtzariaRelease.fromJson(raw);
      if (release.isDraft || release.isPrerelease) return null;
      final relative = raw['installerPath'];
      if (relative is! String || relative.isEmpty) return null;
      installerPath = p.joinAll([
        mirrorDir,
        ...relative.split(RegExp(r'[/\\]')),
      ]);
    } catch (_) {
      return null;
    }
    if (!p.isWithin(
      p.absolute(mirrorDir),
      p.normalize(p.absolute(installerPath)),
    )) {
      return null;
    }

    final platform = _platform;
    if (platform != null && release.installerKind.targetPlatform != platform) {
      return null;
    }
    if (release.installerArch != arch) return null;

    final installer = File(installerPath);
    if (!await installer.exists()) return null;
    if (await installer.length() != release.installerSizeBytes) return null;

    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
    );
  }

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
    } catch (_) {}
    return found;
  }

  Future<MirroredOtzariaReleases> sync({
    OtzariaLatestRelease? online,
    void Function(int received, int total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    online ??= await _releaseClient.fetchLatestRelease();
    final release = online.latest;
    if (release == null) return const MirroredOtzariaReleases();
    final here = _platform ?? release.installerKind.targetPlatform;
    final others = _otherPlatforms(await _readMetadata(), here);
    final latest =
        await _downloadToMirror(release, onDownloadProgress, isCancelled);
    final variant =
        here == OtzariaTargetPlatform.windows ? release.arm64Variant : null;
    final arm64 = variant == null
        ? null
        : await _downloadToMirror(variant, onDownloadProgress, isCancelled);
    await _writeMetadata(
        latest: latest, arm64: arm64, here: here, others: others);
    await _installer.pruneCacheExcept(keepTagNames: {
      OtzariaInstaller.cacheSegment(release.tagName),
      if (arm64 != null) OtzariaInstaller.cacheSegment(arm64.release.tagName),
      ..._tagNamesIn(others).map(OtzariaInstaller.cacheSegment),
    });
    for (final path in await staleFullPackages()) {
      await _deleteQuietly(path);
    }
    return MirroredOtzariaReleases(latest: latest);
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
    } catch (_) {}
  }

  Future<void> _writeMetadata({
    required MirroredOtzariaRelease latest,
    required OtzariaTargetPlatform here,
    MirroredOtzariaRelease? arm64,
    Map<String, Map<String, dynamic>> others = const {},
  }) async {
    Map<String, dynamic> entry(MirroredOtzariaRelease e) => e.release.toJson()
      ..['installerPath'] =
          p.relative(e.installerPath, from: mirrorDir).replaceAll(r'\', '/');
    final own = <String, dynamic>{
      'source': 'github-latest',
      'latest': entry(latest)
    };
    await Directory(mirrorDir).create(recursive: true);
    await writeStringAtomically(
        _metadataPath,
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': _schemaVersion,
          'syncedAt': DateTime.now().toIso8601String(),
          ...own,
          'platforms': {
            ...others,
            here.name: own,
            if (here == OtzariaTargetPlatform.windows)
              platformKey(here, OtzariaArch.arm64): {
                'source': 'github-latest',
                if (arm64 != null) 'latest': entry(arm64),
                if (arm64 == null) 'missingAssetTags': [latest.release.tagName],
              },
          },
        }));
  }
}
