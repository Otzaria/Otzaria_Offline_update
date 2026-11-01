import 'otzaria_install_state.dart';
import 'otzaria_release.dart';

class OtzariaUpdateCheckResult {
  const OtzariaUpdateCheckResult({
    required this.currentState,
    this.latestRelease,
    this.isOtzariaRunning = false,
    this.hasStaleFullPackage = false,
    this.mirrorLacksArchitectures = false,
  });
  final OtzariaRelease? latestRelease;
  final OtzariaInstallState? currentState;
  final bool isOtzariaRunning;
  final bool hasStaleFullPackage;
  final bool mirrorLacksArchitectures;
  bool get needsDownload => latestRelease == null;
  bool get updateAvailable {
    final latest = latestRelease;
    final current = currentState;
    if (latest == null) return false;
    if (current == null) return true;
    final compared = compareBases(normalizeVersion(latest.tagName),
        normalizeVersion(current.installedTagName));
    if (compared != 0) return compared > 0;
    final installedVersion = normalizeVersion(current.installedTagName);
    final targetVersion = normalizeVersion(latest.tagName);
    return installedVersion.contains('-') && !targetVersion.contains('-');
  }

  bool get installedIsNewer =>
      latestRelease != null &&
      currentState != null &&
      compareBases(normalizeVersion(currentState!.installedTagName),
              normalizeVersion(latestRelease!.tagName)) >
          0;

  static bool sameVersion(String installedVersion, String tagName) {
    if (!sameBuild(installedVersion, tagName)) return false;
    final installed = normalizeVersion(installedVersion);
    final tag = normalizeVersion(tagName);
    if (installed == tag) return true;

    final installedBase = _baseVersion(installed);
    final tagBase = _baseVersion(tag);
    if (installed == installedBase &&
        tag == tagBase &&
        compareBases(installedVersion, tagName) == 0) {
      return true;
    }
    if (installedBase != tagBase) return false;
    return installedBase == installed && tagBase != tag;
  }

  static int compareVersions(String a, String b) {
    final left = normalizeVersion(a);
    final right = normalizeVersion(b);
    final leftBase = _baseVersion(left);
    final rightBase = _baseVersion(right);

    final bases = compareBases(a, b);
    if (bases != 0) return bases;

    final leftHasSuffix = left != leftBase;
    final rightHasSuffix = right != rightBase;
    if (leftHasSuffix != rightHasSuffix) return leftHasSuffix ? -1 : 1;

    return _compareBuilds(a, b);
  }

  static bool sameBuild(String a, String b) {
    final left = _buildSuffix(a);
    final right = _buildSuffix(b);
    if (left == null || right == null) return true;
    return left == right;
  }

  static String? _buildSuffix(String raw) {
    final version = raw.trim();
    final separator = version.indexOf('+');
    if (separator < 0) return null;
    final build = version.substring(separator + 1).trim();
    return build.isEmpty ? null : build;
  }

  static int _compareBuilds(String a, String b) {
    final left = int.tryParse(_buildSuffix(a) ?? '');
    final right = int.tryParse(_buildSuffix(b) ?? '');
    if (left == null || right == null || left == right) return 0;
    return left < right ? -1 : 1;
  }

  static List<int> _numericParts(String base) => base
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);

  static String _baseVersion(String version) {
    final separator = version.indexOf('-');
    return separator >= 0 ? version.substring(0, separator) : version;
  }

  static bool carriesVersionCode(String raw) => _hotfixOf(raw) != null;

  static int compareBases(String a, String b, {bool? leftCarriesHotfix}) {
    var left = _numericParts(_baseVersion(normalizeVersion(a)));
    var right = _numericParts(_baseVersion(normalizeVersion(b)));
    if (!((leftCarriesHotfix ?? _carriesHotfix(a)) && _carriesHotfix(b))) {
      left = left.take(3).toList();
      right = right.take(3).toList();
    }
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      final leftPart = i < left.length ? left[i] : 0;
      final rightPart = i < right.length ? right[i] : 0;
      if (leftPart != rightPart) return leftPart < rightPart ? -1 : 1;
    }
    return 0;
  }

  static bool _carriesHotfix(String raw) =>
      _numericParts(_baseVersion(normalizeVersion(raw))).length >= 4 ||
      _buildSuffix(raw) == null;

  static String versionFromDisk(String raw) {
    final version = normalizeVersion(raw);
    final hotfix = _hotfixOf(raw);
    return hotfix == null || hotfix == 0 ? version : '$version.$hotfix';
  }

  static int? _hotfixOf(String raw) {
    final build = buildNumberOf(raw);
    final parts = normalizeVersion(raw).split('.').map(int.tryParse).toList();
    if (build == null || build < 10000 || parts.length != 3) return null;
    if (parts.any((part) => part == null || part < 0 || part > 99)) return null;
    final [major!, minor!, patch!] = parts;
    if (build ~/ 100 != major * 10000 + minor * 100 + patch) return null;
    return build % 100;
  }

  static int? buildNumberOf(String raw) =>
      int.tryParse(_buildSuffix(raw) ?? '');

  static String normalizeVersion(String raw) {
    var version = raw.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    final buildSeparator = version.indexOf('+');
    return buildSeparator >= 0 ? version.substring(0, buildSeparator) : version;
  }
}
