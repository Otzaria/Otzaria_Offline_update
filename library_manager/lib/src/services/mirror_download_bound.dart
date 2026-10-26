import 'package:seforim_library_updater/seforim_library_updater.dart';

/// קשת: הנכסים שלה וגודלם. [sure] — קבציה ידועים (manifest בכונן, או קובץ
/// יחיד בשם הקשת); רק קשת כזו מוסרת, אחרת החסם עלול לרדת מתחת להורדה.
typedef _Edge = ({
  int from,
  int to,
  List<ReleaseAsset> assets,
  int bytes,
  bool sure,
});

final RegExp _edgeName = RegExp(
  r'^patch-v(\d+)-v(\d+)\.db\.zst\.manifest\.json$',
);

/// חסם עליון ל-`LibraryMirrorExporter.export` (לא אישי) משמות וגדלים, בלי רשת;
/// `null` = אין חסם. הכללים — README, "מבנה".
int? mirrorDownloadBytesBound({
  required List<LibraryRelease> relevant,
  required int supportedDbSchemaVersion,
  required ApplyTimeEstimate applyTime,
  required bool Function(LibraryRelease release, ReleaseAsset asset) complete,
  required DeltaManifest? Function(LibraryRelease release, ReleaseAsset asset)
  heldManifest,
}) {
  ReleaseAsset? fullOf(LibraryRelease release) =>
      release.fullDbAssetFor(maxSchemaVersion: supportedDbSchemaVersion);
  final carriers = relevant.where((r) => fullOf(r) != null).toList()
    ..sort(
      (a, b) => LibraryUpdateDiscovery.releaseVersionOf(
        b,
      ).compareTo(LibraryUpdateDiscovery.releaseVersionOf(a)),
    );
  final newest = carriers.firstOrNull;
  final newestFull = newest == null ? null : fullOf(newest)!;
  if (newestFull?.isSplitFullDbManifest ?? false) return null;
  final newestVersion = newest == null
      ? 0
      : LibraryUpdateDiscovery.releaseVersionOf(newest);

  final always = <(LibraryRelease, ReleaseAsset)>[];
  final edges = <(LibraryRelease, _Edge)>[];
  for (final release in relevant) {
    final claimed = <String>{};
    for (final manifestAsset in release.deltaManifestAssets) {
      always.add((release, manifestAsset));
      claimed.add(manifestAsset.name);
      final manifest = heldManifest(release, manifestAsset);
      final int from;
      final int to;
      final List<ReleaseAsset> files;
      var sure = true;
      if (manifest != null) {
        final names = {for (final f in manifest.patchFiles) f.file};
        claimed.addAll(names);
        if (!_appliable(manifest)) continue;
        files = release.assets.where((a) => names.contains(a.name)).toList();
        // קשת חסרה אינה נבנית, אבל מה שיש ממנה יורד.
        if (files.length < names.length) {
          always.addAll(files.map((f) => (release, f)));
          continue;
        }
        (from, to) = (manifest.fromVersion, manifest.toVersion);
      } else {
        final match = _edgeName.firstMatch(manifestAsset.name);
        if (match == null) continue;
        final base = manifestAsset.name.substring(
          0,
          manifestAsset.name.length - '.manifest.json'.length,
        );
        files = release.assets
            .where(
              (a) =>
                  !a.isDeltaManifest &&
                  (a.name == base || a.name.startsWith('$base.')),
            )
            .toList();
        claimed.addAll(files.map((f) => f.name));
        sure = files.length == 1 && files.single.name == base;
        (from, to) = (int.parse(match.group(1)!), int.parse(match.group(2)!));
      }
      edges.add((
        release,
        (
          from: from,
          to: to,
          assets: [manifestAsset, ...files],
          bytes: [
            manifestAsset,
            ...files,
          ].fold(0, (sum, a) => sum + (a.size > 0 ? a.size : 0)),
          sure: sure,
        ),
      ));
    }
    for (final asset in release.assets) {
      if (asset.name.startsWith('patch-') && !claimed.contains(asset.name)) {
        always.add((release, asset));
      }
    }
  }

  // שני המעברים של המייצא: עם זיכוי ההורדה לפני בחירת הנשא, ובלעדיו אחריה.
  List<(LibraryRelease, _Edge)> fast({required bool credit}) {
    if (newestFull == null || newestFull.size <= 0) return edges;
    final fullSeconds = applyTime.fullRouteSeconds(newestFull.size);
    return [
      for (final entry in edges)
        if (!entry.$2.sure ||
            entry.$2.to > newestVersion ||
            !applyTime.isOutOfRange(
              applyTime.deltaRouteSeconds([entry.$2.bytes]),
              fullSeconds,
              savedDownloadBytes: credit ? newestFull.size - entry.$2.bytes : 0,
            ))
          entry,
    ];
  }

  var kept = fast(credit: false);
  if (newest != null) {
    if (!complete(newest, newestFull!)) {
      final reach = _maxReach([for (final e in fast(credit: true)) e.$2]);
      for (final candidate in carriers.skip(1)) {
        if (!complete(candidate, fullOf(candidate)!)) continue;
        final version = LibraryUpdateDiscovery.releaseVersionOf(candidate);
        final reached = reach[version] ?? version;
        // מסד ישן שהמייצא עשוי לבחור: ההורדה בין ~0.1GB לכל המסד — אין חסם.
        if (version < newestVersion
            ? reached >= newestVersion
            : reached > version) {
          return null;
        }
      }
    }
    final reach = _maxReach([for (final e in kept) e.$2]);
    kept = [
      for (final entry in kept)
        if (!entry.$2.sure ||
            (reach[entry.$2.to] ?? entry.$2.to) >= newestVersion)
          entry,
    ];
  }

  final counted = <(String, String)>{};
  var bytes = 0;
  void count(LibraryRelease release, ReleaseAsset asset) {
    if (!counted.add((release.tag, asset.name))) return;
    if (complete(release, asset)) return;
    if (asset.size > 0) bytes += asset.size;
  }

  if (newest != null) count(newest, newestFull!);
  for (final (release, asset) in always) {
    count(release, asset);
  }
  for (final (release, edge) in kept) {
    for (final asset in edge.assets) {
      count(release, asset);
    }
  }
  return bytes;
}

bool _appliable(DeltaManifest manifest) {
  final format = manifest.patchFormatVersion;
  return !manifest.fullRebase &&
      isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
      isSupportedSchemaVersion(manifest.toSchemaVersion) &&
      (format == null || isSupportedPatchFormatVersion(format)) &&
      manifest.hasSupportedCompression;
}

/// לכל גרסה — הגבוהה ביותר שאפשר להגיע אליה ממנה בקשתות קדימה.
Map<int, int> _maxReach(List<_Edge> edges) {
  final reach = <int, int>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final edge in edges) {
      if (edge.to <= edge.from) continue;
      final candidate = reach[edge.to] ?? edge.to;
      if (candidate > (reach[edge.from] ?? edge.from)) {
        reach[edge.from] = candidate;
        changed = true;
      }
    }
  }
  return reach;
}

/// חסם עליון ל-`export(fromVersion:)` (מצב אישי) בלי רשת ובלי כתיבה: קובצי
/// העדכון או המסד המלא, ו-max של שניהם כשאי אפשר להכריע מה הייצוא יבחר.
int? personalDownloadBytesBound({
  required List<LibraryRelease> eligible,
  required List<LibraryRelease> relevant,
  required int fromVersion,
  required int supportedDbSchemaVersion,
  required ApplyTimeEstimate applyTime,
  required bool Function(LibraryRelease release, ReleaseAsset asset) complete,
  required DeltaManifest? Function(LibraryRelease release, ReleaseAsset asset)
  heldManifest,
}) {
  int missing(LibraryRelease release, ReleaseAsset asset) =>
      complete(release, asset) || asset.size <= 0 ? 0 : asset.size;
  ReleaseAsset? fullOf(LibraryRelease release) =>
      release.fullDbAssetFor(maxSchemaVersion: supportedDbSchemaVersion);

  var latest = 0;
  for (final release in eligible) {
    final version = LibraryUpdateDiscovery.releaseVersionOf(release);
    if (version > latest) latest = version;
  }
  LibraryRelease? carrier;
  var carrierVersion = -1;
  for (final release in eligible) {
    if (fullOf(release) == null) continue;
    final version = LibraryUpdateDiscovery.releaseVersionOf(release);
    if (version > carrierVersion) {
      (carrier, carrierVersion) = (release, version);
    }
  }
  // כמו `_newestFullDbCarrier` של המייצא: רק מסד מלא שמגיע לבדו ל-latest.
  if (carrierVersion < latest) carrier = null;
  final full = carrier == null ? null : fullOf(carrier)!;
  if (full != null && (full.isSplitFullDbManifest || full.size <= 0)) {
    return null;
  }
  final fullDownload = full == null ? 0 : missing(carrier!, full);

  var patches = 0;
  for (final release in relevant) {
    for (final asset in release.assets) {
      if (asset.name.startsWith('patch-')) patches += missing(release, asset);
    }
  }
  // "אין חדש" עשוי להיות מראה פגומה שהייצוא בונה מחדש במלואה — לא 0.
  if (relevant.isEmpty) {
    return full == null || latest <= fromVersion ? null : fullDownload;
  }
  if (full == null) return patches;
  final either = patches > fullDownload ? patches : fullDownload;

  // ודאית — רק קשת שה-manifest שלה בכונן ותקף: את השאר הייצוא עשוי לפסול
  // לפי התוכן (fullRebase, סכמה, פורמט, דחיסה).
  final possible = <({int from, int to, int bytes})>[];
  final sure = <({int from, int to, int bytes})>[];
  var allNamed = true;
  for (final release in relevant) {
    for (final manifestAsset in release.deltaManifestAssets) {
      final manifest = heldManifest(release, manifestAsset);
      if (manifest != null) {
        if (!_appliable(manifest)) continue;
        final names = {for (final f in manifest.patchFiles) f.file};
        final files = release.assets.where((a) => names.contains(a.name));
        if (files.length < names.length) continue;
        final edge = (
          from: manifest.fromVersion,
          to: manifest.toVersion,
          bytes: [manifestAsset, ...files].fold(0, (n, a) => n + a.size),
        );
        possible.add(edge);
        sure.add(edge);
        continue;
      }
      final match = _edgeName.firstMatch(manifestAsset.name);
      if (match == null) {
        allNamed = false;
        continue;
      }
      possible.add((
        from: int.parse(match.group(1)!),
        to: int.parse(match.group(2)!),
        bytes: 0,
      ));
    }
  }

  // אין שרשרת גם בהנחה שכל קשת תקפה — ודאי שיורד המסד המלא.
  if (allNamed && _cheapest(possible, fromVersion, latest, applyTime) == null) {
    return fullDownload;
  }
  final route = _cheapest(sure, fromVersion, latest, applyTime);
  if (route == null) return either;
  final fullWins = applyTime.isOutOfRange(
    route.seconds,
    applyTime.fullRouteSeconds(full.size),
    savedDownloadBytes: full.size - route.bytes,
  );
  // רק כשכל הקשתות ודאיות, השרשרת שנמדדה היא זו שהייצוא ימדוד.
  if (possible.length != sure.length || !allNamed) return either;
  return fullWins ? fullDownload : patches;
}

/// כמו `_cheapestRoute` של המייצא: זמן ההחלה של השרשרת הזולה וגודלה.
({double seconds, int bytes})? _cheapest(
  List<({int from, int to, int bytes})> edges,
  int from,
  int to,
  ApplyTimeEstimate applyTime,
) {
  final best = <int, ({double seconds, int bytes})>{
    from: (seconds: 0, bytes: 0),
  };
  final starts = edges.map((e) => e.from).toSet().toList()..sort();
  for (final version in starts) {
    final base = best[version];
    if (base == null) continue;
    for (final edge in edges) {
      if (edge.from != version || edge.to <= edge.from) continue;
      final cost = base.seconds + applyTime.intermediateStepSeconds(edge.bytes);
      final known = best[edge.to];
      if (known == null || cost < known.seconds) {
        best[edge.to] = (seconds: cost, bytes: base.bytes + edge.bytes);
      }
    }
  }
  final total = best[to];
  if (total == null || to == from) return total;
  return (
    seconds: total.seconds + applyTime.chainStartExtraSeconds,
    bytes: total.bytes,
  );
}
