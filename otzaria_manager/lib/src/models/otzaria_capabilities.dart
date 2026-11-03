import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'otzaria_data_root.dart';
import 'otzaria_release.dart';

/// The model an Otzaria release reads; vectors of another generation are
/// unreadable by it even at the same library version.
enum SemanticModelGeneration {
  round2('round2'),
  qa491('qa491');

  const SemanticModelGeneration(this.id);

  final String id;

  static SemanticModelGeneration? byId(Object? id) {
    for (final generation in values) {
      if (generation.id == id) return generation;
    }
    return null;
  }
}

enum SemanticSupportBasis {
  /// The installed app's own, current capabilities file.
  declared,

  /// The installed version, from this tool's verified version table.
  appVersion,

  /// Nothing proves what the installed Otzaria reads.
  unproven,
}

class SemanticAppSupport {
  const SemanticAppSupport({
    this.generation,
    this.windows = false,
    required this.basis,
    this.unrecognizedFamilies = const [],
    this.capabilitiesStale = false,
    this.capabilitiesOfOtherApp = false,
  });

  /// `null` = not proven; never read it as Round2.
  final SemanticModelGeneration? generation;

  /// The app also installs windows-form vectors of [generation].
  final bool windows;
  final SemanticSupportBasis basis;
  final List<String> unrecognizedFamilies;
  final bool capabilitiesStale;
  final bool capabilitiesOfOtherApp;

  bool get proven => generation != null;

  String get proofKey => [
        generation?.id ?? 'unknown',
        windows ? 'windows' : 'anchor',
        basis.name,
        unrecognizedFamilies.join(','),
        capabilitiesStale,
        capabilitiesOfOtherApp,
      ].join('|');
}

class OtzariaCapabilities {
  const OtzariaCapabilities({
    this.formatVersion,
    this.appVersion,
    this.buildNumber,
    this.arch,
    this.portable,
    this.exePath,
    this.readableDbSchemaVersion,
    this.libraryDbPath,
    this.reportsQueueFormat,
    this.pluginInstallResults,
    this.semanticVectorFamilies,
    this.writtenAt,
  });

  static const String fileName = 'otzaria_capabilities.json';
  static const String libraryDatabasePathFileName = 'library_database_path.txt';
  static const String portableDataFolderName =
      OtzariaDataRoot.portableDataFolderName;
  static const String portableMarkerFileName =
      OtzariaDataRoot.portableMarkerFileName;

  static const int legacyReadableDbSchemaVersion = 5;

  static const List<(int, String)> _readableSchemaSinceAppVersion = [
    (6, '0.9.98'),
    (7, '0.9.98.2'),
  ];

  final int? formatVersion;
  final String? appVersion;
  final int? buildNumber;
  final String? arch;
  final bool? portable;
  final String? exePath;
  final int? readableDbSchemaVersion;
  final String? libraryDbPath;
  final int? reportsQueueFormat;
  final int? pluginInstallResults;

  /// Vector release-tag prefixes Otzaria installs, preferred first.
  final List<String>? semanticVectorFamilies;
  final DateTime? writtenAt;

  static OtzariaCapabilities? fromJson(Object? json) {
    if (json is! Map) return null;
    T? field<T>(String key) {
      final value = json[key];
      return value is T ? value : null;
    }

    String? text(String key) {
      final value = field<String>(key);
      return value == null || value.isEmpty ? null : value;
    }

    final schema = field<int>('readableDbSchemaVersion');
    final writtenAt = field<String>('writtenAt');
    return OtzariaCapabilities(
      formatVersion: field<int>('formatVersion'),
      appVersion: text('appVersion'),
      buildNumber: field<int>('buildNumber'),
      arch: text('arch'),
      portable: field<bool>('portable'),
      exePath: text('exePath'),
      readableDbSchemaVersion: schema != null && schema > 0 ? schema : null,
      libraryDbPath: text('libraryDbPath'),
      reportsQueueFormat: field<int>('reportsQueueFormat'),
      pluginInstallResults: field<int>('pluginInstallResults'),
      semanticVectorFamilies: _strings(json['semanticVectorFamilies']),
      writtenAt: writtenAt == null ? null : DateTime.tryParse(writtenAt),
    );
  }

  static List<String>? _strings(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is String && item.isNotEmpty) item,
        ]
      : null;

  static const String windowsVectorFamily = 'vectors-windows';

  /// The first Otzaria whose model and vectors are QA491; every earlier one
  /// reads Round2 only (verified against the app's sources at each tag).
  static const String qa491SinceAppVersion = '0.9.98.3';

  /// Newest version whose generation is known without its own capabilities.
  static const String semanticGenerationProvenThrough = '0.9.98.3';

  // Three or four dotted numbers and optional `+build`. A prerelease or any
  // other suffix may sit before the cut-off, so it proves nothing.
  static final _provable = RegExp(r'^[vV]?\d+(\.\d+){2,3}(\+[0-9A-Za-z.]+)?$');

  static bool _provableVersion(String version) =>
      _provable.hasMatch(version.trim());

  static int? _versionBuild(String? version) =>
      int.tryParse(version?.trim().split('+').last ?? '');

  /// `vectors` release-tag families, by the strings Otzaria writes.
  static const Map<String, (SemanticModelGeneration, bool)>
      _knownVectorFamilies = {
    'vectors': (SemanticModelGeneration.round2, false),
    'vectors-windows': (SemanticModelGeneration.round2, true),
    'vectors-qa491': (SemanticModelGeneration.qa491, false),
    'vectors-qa491-windows': (SemanticModelGeneration.qa491, true),
  };

  /// The model generation an app [version] reads, or `null` past the newest
  /// version this tool has verified.
  static SemanticModelGeneration? semanticGenerationForAppVersion(
    String version,
  ) {
    if (!_provableVersion(version)) return null;
    if (compareAppVersions(version, qa491SinceAppVersion) < 0) {
      return SemanticModelGeneration.round2;
    }
    if (compareAppVersions(version, semanticGenerationProvenThrough) <= 0) {
      return SemanticModelGeneration.qa491;
    }
    return null;
  }

  /// Which model generation and vector shape the Otzaria at [launchPath]
  /// consumes. A record written by another exe, or by an older app than the
  /// one installed now, is not proof of what the installed app reads.
  static SemanticAppSupport semanticSupport({
    OtzariaCapabilities? capabilities,
    String? launchPath,
    String? installedVersion,
  }) {
    final version = installedVersion == null || installedVersion.isEmpty
        ? null
        : installedVersion;
    if (version != null && !_provableVersion(version)) {
      // A version nobody can place proves nothing, and neither does a file
      // that cannot be checked against it.
      return SemanticAppSupport(
        basis: SemanticSupportBasis.unproven,
        capabilitiesStale: capabilities != null,
      );
    }
    var caps = capabilities;
    var other = false;
    var stale = false;
    if (caps != null) {
      final writtenBy = caps.appVersion;
      final foreignExe = caps.exePath != null &&
          launchPath != null &&
          !caps.describesExe(launchPath);
      // A downgrade into the same folder leaves the newer app's file behind.
      final newer = writtenBy != null &&
          version != null &&
          compareAppVersions(version, writtenBy) < 0;
      final writtenBuild = caps.buildNumber ?? _versionBuild(writtenBy);
      final installedBuild = _versionBuild(version);
      final differentBuild = writtenBuild != null &&
          installedBuild != null &&
          writtenBuild != installedBuild;
      if (foreignExe || newer) {
        other = true;
        caps = null;
      } else if ((writtenBy != null && !_provableVersion(writtenBy)) ||
          differentBuild) {
        stale = true;
        caps = null;
      }
    }
    final declared = caps?.semanticVectorFamilies;
    if (caps != null && declared != null && declared.isNotEmpty) {
      final writtenBy = caps.appVersion;
      final fresh = version == null ||
          (writtenBy != null && compareAppVersions(version, writtenBy) == 0);
      if (fresh) return _declared(declared);
      // Older app's file: it only tells what the shape is when both versions
      // read the same generation.
      final before =
          writtenBy == null ? null : semanticGenerationForAppVersion(writtenBy);
      final now = semanticGenerationForAppVersion(version);
      final carried =
          before != null && before == now ? _declared(declared) : null;
      if (carried != null && carried.generation == now) {
        return SemanticAppSupport(
          generation: now,
          windows: carried.windows,
          basis: SemanticSupportBasis.appVersion,
          capabilitiesStale: true,
        );
      }
      final byVersion = semanticGenerationForAppVersion(version);
      return SemanticAppSupport(
        generation: byVersion,
        basis: byVersion == null
            ? SemanticSupportBasis.unproven
            : SemanticSupportBasis.appVersion,
        capabilitiesStale: true,
      );
    }
    // No installed version: the file of this very exe names the version.
    final known = version ?? caps?.appVersion;
    final byVersion =
        known == null ? null : semanticGenerationForAppVersion(known);
    return SemanticAppSupport(
      generation: byVersion,
      basis: byVersion == null
          ? SemanticSupportBasis.unproven
          : SemanticSupportBasis.appVersion,
      capabilitiesStale: stale,
      capabilitiesOfOtherApp: other,
    );
  }

  static SemanticAppSupport _declared(List<String> families) {
    final first = _knownVectorFamilies[families.first];
    if (first == null) {
      return SemanticAppSupport(
        basis: SemanticSupportBasis.unproven,
        unrecognizedFamilies: [
          for (final f in families)
            if (!_knownVectorFamilies.containsKey(f)) f,
        ],
      );
    }
    final generation = first.$1;
    return SemanticAppSupport(
      generation: generation,
      windows: families.any((f) {
        final known = _knownVectorFamilies[f];
        return known != null && known.$1 == generation && known.$2;
      }),
      basis: SemanticSupportBasis.declared,
      unrecognizedFamilies: [
        for (final f in families)
          if (!_knownVectorFamilies.containsKey(f)) f,
      ],
    );
  }

  /// Whether the Otzaria at [launchPath] installs windows-form vectors of its
  /// own generation.
  static bool supportsWindowsVectors({
    OtzariaCapabilities? capabilities,
    String? launchPath,
    String? installedVersion,
  }) =>
      semanticSupport(
        capabilities: capabilities,
        launchPath: launchPath,
        installedVersion: installedVersion,
      ).windows;

  /// First Otzaria release that bundles `otzaria_search_engine` 6.0.0
  /// (`text.line_text_version` 4); 0.9.98+801 still ships ^3.1.0.
  static const String searchEngine6SinceAppVersion = '0.9.98.2';

  /// Whether the Otzaria at [launchPath] reads `text.line_text_version` 4
  /// vectors: `true`/`false` from its version, `null` when no version is known.
  static bool? readsSemanticLineText4({
    OtzariaCapabilities? capabilities,
    String? launchPath,
    String? installedVersion,
  }) {
    final trusted = capabilities?.exePath == null ||
            launchPath == null ||
            capabilities!.describesExe(launchPath)
        ? capabilities
        : null;
    final version = installedVersion ?? trusted?.appVersion;
    if (version == null || _numericParts(version).isEmpty) return null;
    return compareAppVersions(version, searchEngine6SinceAppVersion) >= 0;
  }

  static OtzariaCapabilities? _parse(List<int> bytes) =>
      fromJson(jsonDecode(_withoutBom(utf8.decode(bytes))));

  static String _withoutBom(String text) =>
      text.startsWith('﻿') ? text.substring(1) : text;

  static void Function(String path)? debugPathGuard;

  static Future<OtzariaCapabilities?> read(String dataRoot) async {
    debugPathGuard?.call(dataRoot);
    try {
      return _parse(await File(p.join(dataRoot, fileName)).readAsBytes());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<String?> readLibraryDatabaseDir(String dataRoot) async {
    debugPathGuard?.call(dataRoot);
    try {
      final text = _withoutBom(
        utf8.decode(
          await File(p.join(dataRoot, libraryDatabasePathFileName))
              .readAsBytes(),
        ),
      ).trim();
      return text.isEmpty ? null : text;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static String? dataRootFor(
    String launchPath, {
    required OtzariaTargetPlatform platform,
    Map<String, String>? environment,
  }) =>
      OtzariaDataRoot.resolve(
        launchPath,
        operatingSystem: switch (platform) {
          OtzariaTargetPlatform.windows => 'windows',
          OtzariaTargetPlatform.macos => 'macos',
        },
        environment: environment ?? Platform.environment,
      );

  static OtzariaCapabilities? readForInstall(
    String launchPath, {
    required OtzariaTargetPlatform platform,
    Map<String, String>? environment,
  }) {
    final root = dataRootFor(
      launchPath,
      platform: platform,
      environment: environment,
    );
    if (root == null) return null;
    debugPathGuard?.call(root);
    try {
      return _parse(File(p.join(root, fileName)).readAsBytesSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  bool describesExe(String launchPath) {
    final exe = exePath;
    if (exe == null) return false;
    if (p.equals(exe, launchPath)) return true;
    return p.isWithin(launchPath, exe) &&
        launchPath.toLowerCase().endsWith('.app');
  }

  static int? readableDbSchemaForAppVersion(String version) {
    if (_numericParts(version).isEmpty) return null;
    for (final (schema, since) in _readableSchemaSinceAppVersion.reversed) {
      if (compareAppVersions(version, since) >= 0) return schema;
    }
    return legacyReadableDbSchemaVersion;
  }

  static int? resolveReadableDbSchema({
    OtzariaCapabilities? capabilities,
    String? installedVersion,
    String? launchPath,
  }) {
    final trusted = capabilities?.exePath == null ||
            launchPath == null ||
            capabilities!.describesExe(launchPath)
        ? capabilities
        : null;
    final declared = trusted?.readableDbSchemaVersion;
    final fromInstalled = installedVersion == null
        ? null
        : readableDbSchemaForAppVersion(installedVersion);
    if (declared == null) return fromInstalled;
    final declaredFor = trusted?.appVersion;
    if (fromInstalled == null || installedVersion == null) return declared;
    if (declaredFor == null) return declared;
    final order = compareAppVersions(installedVersion, declaredFor);
    if (order == 0) return declared;
    if (order > 0) return declared > fromInstalled ? declared : fromInstalled;
    return fromInstalled;
  }

  static int compareAppVersions(String a, String b) {
    final left = _numericParts(a);
    final right = _numericParts(b);
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _numericParts(String version) {
    var base = version.trim();
    if (base.startsWith('v') || base.startsWith('V')) base = base.substring(1);
    final cut = base.indexOf(RegExp(r'[+\-\s]'));
    if (cut >= 0) base = base.substring(0, cut);
    final parts = <int>[];
    for (final part in base.split('.')) {
      final value = int.tryParse(part);
      if (value == null) return parts;
      parts.add(value);
    }
    return parts;
  }
}
