import 'package:http/http.dart' as http;
import 'package:seforim_library_updater/seforim_library_updater.dart';

class _UnusedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('PersonalReleasesClient sends through its source');
}

final RegExp _patchName = RegExp(r'^patch-v(\d+)-v(\d+)\.db\.zst(?:\.|$)');

/// [releases] בלי קובצי עדכון שמתחילים מתחת ל-[fromVersion]: עדכון מתקדם רק
/// קדימה, ולכן אף מחשב רשום אינו יכול להחיל אותם.
List<LibraryRelease> withoutPatchesBelow(
  List<LibraryRelease> releases,
  int fromVersion,
) => [
  for (final release in releases)
    LibraryRelease(
      tag: release.tag,
      isPrerelease: release.isPrerelease,
      isDraft: release.isDraft,
      publishedAt: release.publishedAt,
      assets: [
        for (final asset in release.assets)
          if (!_startsBelow(asset.name, fromVersion)) asset,
      ],
    ),
];

bool _startsBelow(String name, int fromVersion) {
  final match = _patchName.firstMatch(name);
  return match != null && int.parse(match.group(1)!) < fromVersion;
}

/// המייצא לוקח כל patch של release חדש מ-[fromVersion], גם כזה שמתחיל מתחת
/// לה; מסונן כאן ולא במנוע, כי את seforim_library_updater לא משנים מהריפו הזה.
class PersonalReleasesClient extends GithubLibraryReleaseClient {
  PersonalReleasesClient(this._source, {required this.fromVersion})
    : super(httpClient: _unused);

  // כל בקשה עוברת דרך [_source]; זה רק ממלא את מחלקת הבסיס.
  static final http.Client _unused = _UnusedHttpClient();

  final GithubLibraryReleaseClient _source;
  final int fromVersion;
  Future<List<LibraryRelease>>? _filtered;

  @override
  Future<List<LibraryRelease>> fetchReleases() => _filtered ??= _source
      .fetchReleases()
      .then((all) => withoutPatchesBelow(all, fromVersion));

  @override
  Future<DeltaManifest> fetchManifest(String url) => _source.fetchManifest(url);

  @override
  Future<ReleaseAsset> resolveSplitAsset(
    LibraryRelease release,
    ReleaseAsset manifestAsset,
  ) => _source.resolveSplitAsset(release, manifestAsset);
}
