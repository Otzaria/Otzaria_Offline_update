import 'package:seforim_library_updater/seforim_library_updater.dart';

class RecentLibraryReleasesClient extends GithubLibraryReleaseClient {
  RecentLibraryReleasesClient({
    super.httpClient,
    this.reuseWindow = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration reuseWindow;
  final DateTime Function() _clock;
  ({DateTime at, List<LibraryRelease> releases})? _recent;

  Future<List<LibraryRelease>> fetchFreshReleases() async {
    final releases = List<LibraryRelease>.unmodifiable(
      await super.fetchReleases(),
    );
    _recent = (at: _clock(), releases: releases);
    return releases;
  }

  @override
  Future<List<LibraryRelease>> fetchReleases() async {
    final recent = _recent;
    if (recent != null) {
      final age = _clock().difference(recent.at);
      if (!age.isNegative && age < reuseWindow) return recent.releases;
    }
    return fetchFreshReleases();
  }

  void forgetReleases() => _recent = null;
}
