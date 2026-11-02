import 'package:equatable/equatable.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../services/windows_arch.dart';
import 'otzaria_releases.dart';

typedef OtzariaLatestRelease = OtzariaReleases<OtzariaRelease>;

enum OtzariaTargetPlatform {
  windows,
  macos;

  static OtzariaTargetPlatform detect(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => OtzariaTargetPlatform.windows,
      'macos' => OtzariaTargetPlatform.macos,
      _ => throw UnsupportedError(
          AppL10n.strings.appDomain.unsupportedPlatform(operatingSystem),
        ),
    };
  }

  static OtzariaTargetPlatform? detectOrNull(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => OtzariaTargetPlatform.windows,
      'macos' => OtzariaTargetPlatform.macos,
      _ => null,
    };
  }

  String get label => switch (this) {
        OtzariaTargetPlatform.windows => 'Windows',
        OtzariaTargetPlatform.macos => 'macOS',
      };
}

enum OtzariaInstallerKind {
  windowsSetupExe,

  macAppZip,

  macAppDmg;

  bool get isMac =>
      this == OtzariaInstallerKind.macAppZip ||
      this == OtzariaInstallerKind.macAppDmg;

  OtzariaTargetPlatform get targetPlatform =>
      isMac ? OtzariaTargetPlatform.macos : OtzariaTargetPlatform.windows;
}

class OtzariaRelease extends Equatable {
  const OtzariaRelease({
    required this.tagName,
    required this.name,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.installerKind,
    required this.installerAssetName,
    required this.installerDownloadUrl,
    required this.installerSizeBytes,
    this.installerSha256,
    this.releaseNotes,
    this.installerArch = OtzariaArch.x64,
    this.arm64Variant,
  });

  final String tagName;
  final String name;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;

  final String? releaseNotes;

  final OtzariaInstallerKind installerKind;

  final String installerAssetName;
  final String installerDownloadUrl;
  final int installerSizeBytes;
  final String? installerSha256;

  final OtzariaArch installerArch;

  final OtzariaRelease? arm64Variant;

  OtzariaRelease copyWithReleaseNotes(String? releaseNotes) => OtzariaRelease(
        tagName: tagName,
        name: name,
        isPrerelease: isPrerelease,
        isDraft: isDraft,
        publishedAt: publishedAt,
        installerKind: installerKind,
        installerAssetName: installerAssetName,
        installerDownloadUrl: installerDownloadUrl,
        installerSizeBytes: installerSizeBytes,
        installerSha256: installerSha256,
        releaseNotes: releaseNotes,
        installerArch: installerArch,
        arm64Variant: arm64Variant?.copyWithReleaseNotes(releaseNotes),
      );

  OtzariaRelease withArm64Variant(OtzariaRelease? variant) => OtzariaRelease(
        tagName: tagName,
        name: name,
        isPrerelease: isPrerelease,
        isDraft: isDraft,
        publishedAt: publishedAt,
        installerKind: installerKind,
        installerAssetName: installerAssetName,
        installerDownloadUrl: installerDownloadUrl,
        installerSizeBytes: installerSizeBytes,
        installerSha256: installerSha256,
        releaseNotes: releaseNotes,
        installerArch: installerArch,
        arm64Variant: variant,
      );

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'name': name,
        'isPrerelease': isPrerelease,
        'isDraft': isDraft,
        'publishedAt': publishedAt?.toIso8601String(),
        'installerKind': installerKind.name,
        'installerAssetName': installerAssetName,
        'installerDownloadUrl': installerDownloadUrl,
        'installerSizeBytes': installerSizeBytes,
        if (installerSha256 != null) 'installerSha256': installerSha256,
        'releaseNotes': releaseNotes,
        if (installerArch != OtzariaArch.x64)
          'installerArch': installerArch.name,
      };

  static String? normalizedSha256(Object? raw) {
    if (raw is! String) return null;
    final hex = raw.trim().toLowerCase().replaceFirst('sha256:', '');
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  factory OtzariaRelease.fromJson(Map<String, dynamic> json) {
    final kindName = json['installerKind'];
    final kind = OtzariaInstallerKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    final archName = json['installerArch'];
    final arch = archName == null
        ? OtzariaArch.x64
        : OtzariaArch.values.where((a) => a.name == archName).firstOrNull;
    if (arch == null ||
        json['tagName'] is! String ||
        json['installerAssetName'] is! String ||
        json['installerSizeBytes'] is! int ||
        kind == null) {
      throw FormatException(AppL10n.strings.appDomain.corruptReleaseMetadata);
    }

    final publishedAt = json['publishedAt'];
    return OtzariaRelease(
      tagName: json['tagName'] as String,
      name: (json['name'] as String?) ?? json['tagName'] as String,
      isPrerelease: json['isPrerelease'] as bool? ?? false,
      isDraft: json['isDraft'] as bool? ?? false,
      publishedAt:
          publishedAt is String ? DateTime.tryParse(publishedAt) : null,
      installerKind: kind,
      installerAssetName: json['installerAssetName'] as String,
      installerDownloadUrl: (json['installerDownloadUrl'] as String?) ?? '',
      installerSizeBytes: json['installerSizeBytes'] as int,
      installerSha256: normalizedSha256(json['installerSha256']),
      releaseNotes: json['releaseNotes'] as String?,
      installerArch: arch,
    );
  }

  @override
  List<Object?> get props => [
        tagName,
        name,
        isPrerelease,
        isDraft,
        publishedAt,
        installerKind,
        installerAssetName,
        installerDownloadUrl,
        installerSizeBytes,
        installerSha256,
        releaseNotes,
        installerArch,
        arm64Variant,
      ];
}

class NoInstallerAssetException implements Exception {
  const NoInstallerAssetException({
    required this.tagName,
    required this.platform,
    required this.expectedSuffixes,
  });

  final String tagName;
  final OtzariaTargetPlatform platform;

  final List<String> expectedSuffixes;

  @override
  String toString() => AppL10n.strings.appDomain.noAssetForPlatform(
        tagName,
        platform.label,
        expectedSuffixes,
      );
}
