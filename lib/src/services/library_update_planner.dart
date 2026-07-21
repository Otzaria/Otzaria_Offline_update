import '../models/library_release.dart';
import '../models/library_update_plan.dart';

/// בוחר את תוכנית העדכון: מסלול דלתא, הורדה מלאה, none, או blocked.
///
/// פונקציה טהורה — אינה ניגשת לרשת או ל-DB. מקבלת את כל המידע שכבר נאסף
/// (גרסה מקומית, edges, ו-DB מלא ל-fallback) ומחזירה [LibraryUpdatePlan].
class LibraryUpdatePlanner {
  const LibraryUpdatePlanner();

  /// בונה תוכנית עדכון.
  ///
  /// [localVersion] — גרסת ה-DB המקומי.
  /// [hasLocalVersionMeta] — `false` אם `schema_meta.db_version` חסר.
  /// [latestVersion] — הגרסה הגבוהה ביותר הזמינה ב-releases.
  /// [edges] — כל ה-patches הזמינים.
  /// [latestFullDbAsset] / [latestReleaseTag] — ה-DB המלא ל-fallback.
  LibraryUpdatePlan plan({
    required int localVersion,
    required bool hasLocalVersionMeta,
    required int latestVersion,
    required List<PatchEdge> edges,
    ReleaseAsset? latestFullDbAsset,
    String? latestReleaseTag,
  }) {
    if (!hasLocalVersionMeta) {
      return _fullOrBlocked(
        localVersion: localVersion,
        latestVersion: latestVersion,
        asset: latestFullDbAsset,
        tag: latestReleaseTag,
        reason: 'גרסת ה-DB המקומי אינה ידועה (חסר schema_meta.db_version)',
      );
    }

    if (localVersion >= latestVersion) {
      return LibraryUpdatePlan.none(
        localVersion: localVersion,
        targetVersion: latestVersion,
      );
    }

    final path = _findBestPath(edges, localVersion, latestVersion);
    if (path != null && path.isNotEmpty) {
      return LibraryUpdatePlan.delta(
        localVersion: localVersion,
        targetVersion: latestVersion,
        steps: path,
      );
    }

    return _fullOrBlocked(
      localVersion: localVersion,
      latestVersion: latestVersion,
      asset: latestFullDbAsset,
      tag: latestReleaseTag,
      reason: 'אין מסלול דלתא רציף מגרסה $localVersion לגרסה $latestVersion',
    );
  }

  LibraryUpdatePlan _fullOrBlocked({
    required int localVersion,
    required int latestVersion,
    required ReleaseAsset? asset,
    required String? tag,
    required String reason,
  }) {
    if (asset != null && tag != null) {
      return LibraryUpdatePlan.fullDownload(
        localVersion: localVersion,
        targetVersion: latestVersion,
        asset: asset,
        releaseTag: tag,
        reason: reason,
      );
    }
    return LibraryUpdatePlan.blocked(
      localVersion: localVersion,
      targetVersion: latestVersion,
      reason: '$reason, ואין DB מלא זמין להורדה',
    );
  }

  /// מוצא מסלול ממזער (מספר patches, ואז גודל דחוס כולל) מ-[from] ל-[to].
  /// מחזיר null אם אין מסלול. Dijkstra על גרף ה-edges (DAG עולה).
  List<PatchEdge>? _findBestPath(
    List<PatchEdge> edges,
    int from,
    int to,
  ) {
    final adjacency = <int, List<PatchEdge>>{};
    for (final edge in edges) {
      if (edge.toVersion <= edge.fromVersion) continue; // רק קדימה
      adjacency.putIfAbsent(edge.fromVersion, () => []).add(edge);
    }

    final best = <int, _Reach>{from: const _Reach(0, 0, [])};
    final visited = <int>{};

    while (true) {
      int? current;
      _Reach? currentReach;
      for (final entry in best.entries) {
        if (visited.contains(entry.key)) continue;
        if (currentReach == null || entry.value.isBetterThan(currentReach)) {
          current = entry.key;
          currentReach = entry.value;
        }
      }
      if (current == null || currentReach == null) break;
      if (current == to) return currentReach.path;
      visited.add(current);

      for (final edge in adjacency[current] ?? const <PatchEdge>[]) {
        final next = edge.toVersion;
        if (visited.contains(next)) continue;
        final candidate = _Reach(
          currentReach.hops + 1,
          currentReach.size + edge.compressedSize,
          [...currentReach.path, edge],
        );
        final existing = best[next];
        if (existing == null || candidate.isBetterThan(existing)) {
          best[next] = candidate;
        }
      }
    }
    return null;
  }
}

/// עלות הגעה לגרסה: מספר patches (עיקרי) וגודל דחוס כולל (משני).
class _Reach {
  final int hops;
  final int size;
  final List<PatchEdge> path;
  const _Reach(this.hops, this.size, this.path);

  bool isBetterThan(_Reach other) {
    if (hops != other.hops) return hops < other.hops;
    return size < other.size;
  }
}
