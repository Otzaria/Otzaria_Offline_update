import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'otzaria_data_root.dart';
import 'otzaria_release.dart';

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

  /// Whether the Otzaria at [launchPath] installs windows-family vectors.
  /// A record written by another exe proves nothing, as for the DB schema.
  static bool supportsWindowsVectors({
    OtzariaCapabilities? capabilities,
    String? launchPath,
    String? installedVersion,
  }) {
    if (capabilities == null) return false;
    final writtenBy = capabilities.appVersion;
    // A downgrade into the same folder leaves the newer app's file behind.
    if (writtenBy != null &&
        installedVersion != null &&
        compareAppVersions(installedVersion, writtenBy) < 0) {
      return false;
    }
    if (capabilities.exePath != null &&
        launchPath != null &&
        !capabilities.describesExe(launchPath)) {
      return false;
    }
    return capabilities.semanticVectorFamilies?.contains(windowsVectorFamily) ??
        false;
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
