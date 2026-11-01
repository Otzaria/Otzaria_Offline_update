import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/otzaria_release.dart';
import 'otzaria_asset_selector.dart';
import 'windows_arch.dart';

class OtzariaReleaseClient {
  OtzariaReleaseClient({
    http.Client? httpClient,
    OtzariaTargetPlatform? platform,
    this.timeout = const Duration(seconds: 20),
  })  : _httpClient = httpClient ?? http.Client(),
        _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem);

  Duration timeout;

  static const _owner = 'Otzaria';
  static const _repo = 'otzaria';
  static const _apiBase = 'https://api.github.com';

  final http.Client _httpClient;

  final OtzariaTargetPlatform _platform;

  static const _assetSelector = OtzariaAssetSelector();

  Future<OtzariaLatestRelease> fetchLatestRelease() async {
    final uri = Uri.parse('$_apiBase/repos/$_owner/$_repo/releases/latest');
    final decoded = await githubGetJson(
      _httpClient,
      uri,
      timeout: timeout,
      statusError: (status) => isFilterBlockStatus(status)
          ? NetworkBlockedException(uri: uri, statusCode: status)
          : GithubApiException(
              AppL10n.strings.appDomain.githubStatus(status, '$uri'),
            ),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded['draft'] == true ||
        decoded['prerelease'] == true) {
      throw GithubApiException(
        AppL10n.strings.appDomain.noReleasesAtAll('$_owner/$_repo'),
      );
    }
    final release = _withArm64Variant(_parseRelease(decoded), decoded);
    return OtzariaLatestRelease(latest: release);
  }

  OtzariaRelease _withArm64Variant(
    OtzariaRelease release,
    Map<String, dynamic> json,
  ) {
    if (_platform != OtzariaTargetPlatform.windows) return release;
    try {
      return release.withArm64Variant(
        _parseRelease(json, arch: OtzariaArch.arm64),
      );
    } on NoInstallerAssetException {
      return release;
    }
  }

  OtzariaRelease _parseRelease(
    Map<String, dynamic> json, {
    OtzariaArch arch = OtzariaArch.x64,
  }) {
    final tagName = json['tag_name'] as String;
    final assets = [
      for (final raw in json['assets'] as List<dynamic>)
        if (GithubReleaseAsset.tryParse(raw) case final asset?
            when asset.isReady)
          asset,
    ];

    final selected = _assetSelector.select(
      platform: _platform,
      assets: assets,
      nameOf: (asset) => asset.name,
      arch: arch,
    );

    if (selected == null) {
      throw NoInstallerAssetException(
        tagName: tagName,
        platform: _platform,
        expectedSuffixes: OtzariaAssetSelector.expectedSuffixesFor(
          _platform,
          arch: arch,
        ),
      );
    }

    final (asset, installerKind) = selected;

    return OtzariaRelease(
      tagName: tagName,
      name: (json['name'] as String?) ?? tagName,
      isPrerelease: json['prerelease'] as bool? ?? false,
      isDraft: json['draft'] as bool? ?? false,
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'] as String),
      installerKind: installerKind,
      installerAssetName: asset.name,
      installerDownloadUrl: asset.downloadUrl,
      installerSizeBytes: asset.size,
      installerSha256: OtzariaRelease.normalizedSha256(asset.sha256),
      releaseNotes: json['body'] as String?,
      installerArch: arch,
    );
  }

  void dispose() => _httpClient.close();
}

class GithubApiException implements Exception {
  const GithubApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
