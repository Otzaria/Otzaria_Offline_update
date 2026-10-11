import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/library_release.dart';
import '../models/library_update_plan.dart';
import 'apply_time_estimate.dart';

/// בוחר את תוכנית העדכון: מסלול דלתא, הורדה מלאה, none, או blocked.
///
/// פונקציה טהורה — אינה ניגשת לרשת או ל-DB. מקבלת את כל המידע שכבר נאסף
/// (גרסה מקומית, edges, ו-DB מלא ל-fallback) ומחזירה [LibraryUpdatePlan].
///
/// **כששני המסלולים מגיעים לאותה גרסה, נבחר המהיר** — שניהם כבר יושבים על
/// הכונן, ולכן מה שנשאר להשוות הוא הזמן שהמשתמש מחכה. ראו [ApplyTimeEstimate].
class LibraryUpdatePlanner {
  const LibraryUpdatePlanner({this.applyTime = const ApplyTimeEstimate()});

  /// אומדן זמן העדכון **על המחשב הזה**, שלפיו נבחר בין שרשרת קובצי עדכון
  /// לבין החלפת המסד המלא כששתיהן מגיעות לאותה גרסה. ניתן להזרקה לבדיקות.
  final ApplyTimeEstimate applyTime;

  /// בונה תוכנית עדכון.
  ///
  /// [localVersion] — גרסת ה-DB המקומי.
  /// [hasLocalVersionMeta] — `false` אם `schema_meta.db_version` חסר.
  /// [latestVersion] — הגרסה הגבוהה ביותר הזמינה ב-releases.
  /// [edges] — כל ה-patches הזמינים.
  /// [latestFullDbAsset] / [fullDbReleaseTag] — ה-DB המלא ל-fallback.
  /// [latestFullDbVersion] — הגרסה ש**הנכס הזה** מביא; ראו
  /// [LibraryDiscoveryResult.latestFullDbVersion].
  /// [latestContentTag] — ה-release החדש ביותר, זה שהתוכן העדכני מגיע ממנו.
  /// [localReleaseTag] / [localReleaseTagVersion] — ה-release שממנו הגיע ה-DB
  /// המקומי והגרסה שנרשמה איתו, אם ידועים. ראו [_isContentRefresh].
  /// [blockingSchemaVersion] — סכמה שנראתה ב-releases ואיננו יודעים להחיל
  /// (`LibraryDiscoveryResult.blockingSchemaVersion`). לתוכנית עצמה אין בה
  /// צורך — ה-edges שלה כבר סוננו — אלא רק להסבר שמוצג למשתמש.
  /// [blockingPatchFormatVersion] — אותו דבר על ציר פורמט ה-`patch.db`;
  /// משמש רק כשהסכמה עצמה מוכרת.
  LibraryUpdatePlan plan({
    required int localVersion,
    required bool hasLocalVersionMeta,
    required int latestVersion,
    required List<PatchEdge> edges,
    ReleaseAsset? latestFullDbAsset,
    String? fullDbReleaseTag,
    int? latestFullDbVersion,
    String? latestContentTag,
    String? localReleaseTag,
    int? localReleaseTagVersion,
    int? blockingSchemaVersion,
    int? blockingPatchFormatVersion,
    String? localVersionUnknownReason,
  }) {
    final fullTargetVersion = latestFullDbVersion ?? latestVersion;
    final followUp = _followUpDelta(
      edges,
      fullTargetVersion,
      latestVersion,
      blockingSchemaVersion,
      blockingPatchFormatVersion,
    );

    if (!hasLocalVersionMeta) {
      return _fullOrBlocked(
        localVersion: localVersion,
        latestVersion: latestVersion,
        fullTargetVersion: fullTargetVersion,
        followUp: followUp,
        asset: latestFullDbAsset,
        tag: fullDbReleaseTag,
        reason: localVersionUnknownReason ??
            AppL10n.strings.libraryDomain.planLocalVersionUnknown,
        requireProgress: false,
      );
    }

    if (localVersion >= latestVersion) {
      if (latestFullDbAsset != null &&
          fullDbReleaseTag != null &&
          fullDbReleaseTag == latestContentTag &&
          _isContentRefresh(
            localTag: localReleaseTag,
            localTagVersion: localReleaseTagVersion,
            latestTag: latestContentTag,
            localVersion: localVersion,
          ) &&
          (followUp?.targetVersion ?? fullTargetVersion) >= localVersion) {
        return LibraryUpdatePlan.fullDownload(
          localVersion: localVersion,
          targetVersion: fullTargetVersion,
          asset: latestFullDbAsset,
          releaseTag: fullDbReleaseTag,
          followUpDelta: followUp,
          reason: AppL10n.strings.libraryDomain
              .planContentChangedWithoutVersionBump(fullDbReleaseTag),
        );
      }
      return LibraryUpdatePlan.none(
        localVersion: localVersion,
        targetVersion: latestVersion,
      );
    }

    final path = _bestReachablePath(edges, localVersion, latestVersion);
    final deltaTarget = path == null ? localVersion : path.last.toVersion;

    final fullAvailable = latestFullDbAsset != null && fullDbReleaseTag != null;
    final fullRouteTarget = fullAvailable
        ? (followUp?.targetVersion ?? fullTargetVersion)
        : localVersion;

    if (fullAvailable &&
        path != null &&
        path.isNotEmpty &&
        deltaTarget == fullRouteTarget &&
        fullRouteTarget > localVersion &&
        latestFullDbAsset.size > 0) {
      final deltaSeconds =
          applyTime.deltaRouteSeconds(path.map((e) => e.compressedSize));
      final fullSeconds = applyTime.fullRouteSeconds(latestFullDbAsset.size) +
          applyTime.deltaRouteSeconds(
              followUp?.deltaSteps.map((e) => e.compressedSize) ?? const []);
      if (applyTime.isOutOfRange(deltaSeconds, fullSeconds)) {
        return LibraryUpdatePlan.fullDownload(
          localVersion: localVersion,
          targetVersion: fullTargetVersion,
          asset: latestFullDbAsset,
          releaseTag: fullDbReleaseTag,
          reason: AppL10n.strings.libraryDomain.planFullDbFasterThanPatches(
            path.length,
            ApplyTimeEstimate.minutesOf(deltaSeconds),
            ApplyTimeEstimate.minutesOf(fullSeconds),
          ),
          followUpDelta: followUp,
        );
      }
    }

    if (path != null && path.isNotEmpty && deltaTarget >= fullRouteTarget) {
      return LibraryUpdatePlan.delta(
        localVersion: localVersion,
        targetVersion: deltaTarget,
        steps: path,
        reason: deltaTarget >= latestVersion
            ? null
            : _partialStopReason(
                deltaTarget,
                latestVersion,
                blockingSchemaVersion,
                blockingPatchFormatVersion,
              ),
        fullDownloadFallback: latestFullDbAsset != null &&
                fullDbReleaseTag != null &&
                fullRouteTarget > localVersion
            ? LibraryUpdatePlan.fullDownload(
                localVersion: localVersion,
                targetVersion: fullTargetVersion,
                asset: latestFullDbAsset,
                releaseTag: fullDbReleaseTag,
                followUpDelta: followUp,
              )
            : null,
      );
    }

    final strings = AppL10n.strings.libraryDomain;
    return _fullOrBlocked(
      localVersion: localVersion,
      latestVersion: latestVersion,
      fullTargetVersion: fullTargetVersion,
      followUp: followUp,
      asset: latestFullDbAsset,
      tag: fullDbReleaseTag,
      reason: blockingSchemaVersion != null
          ? strings.planPatchSchemaTooNew(blockingSchemaVersion, latestVersion)
          : blockingPatchFormatVersion != null
              ? strings.planPatchFormatTooNew(
                  blockingPatchFormatVersion,
                  latestVersion,
                )
              : strings.planNoDeltaRoute(localVersion, latestVersion),
      requireProgress: true,
      blockingSchemaVersion: blockingSchemaVersion,
      blockingPatchFormatVersion: blockingPatchFormatVersion,
    );
  }

  /// ההסבר לשרשרת שנעצרה מתחת ל-latest: מעבר סכמה, פורמט patch שאיננו
  /// מכירים, או פשוט חוסר קשתות. הסכמה קודמת — היא מה שמשתנה בפועל.
  String _partialStopReason(
    int reachedVersion,
    int latestVersion,
    int? blockingSchemaVersion,
    int? blockingPatchFormatVersion,
  ) {
    final strings = AppL10n.strings.libraryDomain;
    if (blockingSchemaVersion != null) {
      return strings.planPartialDeltaSchemaStop(
        reachedVersion,
        latestVersion,
        blockingSchemaVersion,
      );
    }
    if (blockingPatchFormatVersion != null) {
      return strings.planPartialDeltaFormatStop(
        reachedVersion,
        latestVersion,
        blockingPatchFormatVersion,
      );
    }
    return strings.planNoDeltaRoute(reachedVersion, latestVersion);
  }

  /// האם המסד המקומי בגרסה האחרונה אבל מ-release **אחר** — כלומר התוכן
  /// עודכן בלי להעלות את `db_version`, מה שקורה בפועל ב-SeforimLibrary.
  ///
  /// דורש שנדע מאיזה release ה-DB המקומי הגיע: `null` פירושו DB שלא הותקן
  /// דרך הלאנצ'ר הזה, ואז אין דרך להשוות — ומוטב לדווח "מעודכן" מלהציע
  /// הורדה מלאה של ~1GB בכל פתיחה על סמך ניחוש.
  ///
  /// [localTagVersion] חייבת להתאים ל-[localVersion]: רישום שנעשה בגרסה אחרת
  /// אינו מעיד על התוכן שבמסד עכשיו (מסד שאוצריא עדכנה בעצמה, או מחשב אחר
  /// שכתב את הרישום על הכונן), והשוואה כזו הכריזה על "עדכון" מגרסה X לאותה
  /// גרסה X — ~1.4GB על לא כלום.
  bool _isContentRefresh({
    required String? localTag,
    required int? localTagVersion,
    required String? latestTag,
    required int localVersion,
  }) =>
      localTag != null &&
      latestTag != null &&
      localTagVersion == localVersion &&
      localTag != latestTag;

  LibraryUpdatePlan? _followUpDelta(
    List<PatchEdge> edges,
    int fullTargetVersion,
    int latestVersion,
    int? blockingSchemaVersion,
    int? blockingPatchFormatVersion,
  ) {
    if (fullTargetVersion >= latestVersion) return null;
    final path = _bestReachablePath(edges, fullTargetVersion, latestVersion);
    if (path == null) return null;
    final reached = path.last.toVersion;
    return LibraryUpdatePlan.delta(
      localVersion: fullTargetVersion,
      targetVersion: reached,
      steps: path,
      reason: reached >= latestVersion
          ? null
          : _partialStopReason(
              reached,
              latestVersion,
              blockingSchemaVersion,
              blockingPatchFormatVersion,
            ),
    );
  }

  LibraryUpdatePlan _fullOrBlocked({
    required int localVersion,
    required int latestVersion,
    required int fullTargetVersion,
    required LibraryUpdatePlan? followUp,
    required ReleaseAsset? asset,
    required String? tag,
    required String reason,
    required bool requireProgress,
    int? blockingSchemaVersion,
    int? blockingPatchFormatVersion,
  }) {
    final strings = AppL10n.strings.libraryDomain;
    if (asset != null && tag != null) {
      final finalTarget = followUp?.targetVersion ?? fullTargetVersion;
      if (requireProgress && finalTarget <= localVersion) {
        return LibraryUpdatePlan.blocked(
          localVersion: localVersion,
          targetVersion: latestVersion,
          reason: blockingSchemaVersion != null
              ? strings.planPatchSchemaTooNew(
                  blockingSchemaVersion,
                  latestVersion,
                )
              : strings.planFullDbWouldNotProgress(
                  finalTarget,
                  localVersion,
                  latestVersion,
                ),
        );
      }
      return LibraryUpdatePlan.fullDownload(
        localVersion: localVersion,
        targetVersion: fullTargetVersion,
        asset: asset,
        releaseTag: tag,
        reason: followUp?.reason ??
            (blockingSchemaVersion != null
                ? strings.planNewSchemaNeedsFullDb(
                    latestVersion,
                    blockingSchemaVersion,
                  )
                : blockingPatchFormatVersion != null
                    ? strings.planPatchFormatTooNew(
                        blockingPatchFormatVersion,
                        latestVersion,
                      )
                    : reason),
        followUpDelta: followUp,
      );
    }
    return LibraryUpdatePlan.blocked(
      localVersion: localVersion,
      targetVersion: latestVersion,
      reason: strings.planNoFullDbEither(reason),
    );
  }

  /// המסלול אל הגרסה הגבוהה ביותר שאפשר להגיע אליה מ-[from], עד [to] כולל.
  /// מנסה מלמעלה למטה ועוצר בהצלחה הראשונה, ולכן מחזיר תמיד את הגבוהה ביותר.
  /// `null` כשאין אף מסלול קדימה.
  ///
  /// הגרף כאן הוא עשרות קשתות, ולכן כמה ריצות Dijkstra הן זולות — וזה מה
  /// שמאפשר לעצור באמצע כשמעבר סכמה חתך את הדרך ל-latest.
  List<PatchEdge>? _bestReachablePath(
    List<PatchEdge> edges,
    int from,
    int to,
  ) {
    for (var target = to; target > from; target--) {
      final path = _findBestPath(edges, from, target);
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
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
