import 'package:otzaria_l10n/otzaria_l10n.dart';

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
  /// [latestFullDbAsset] / [fullDbReleaseTag] — ה-DB המלא ל-fallback.
  /// [latestFullDbVersion] — הגרסה ש**הנכס הזה** מביא; ראו
  /// [LibraryDiscoveryResult.latestFullDbVersion].
  /// [latestContentTag] — ה-release החדש ביותר, זה שהתוכן העדכני מגיע ממנו.
  /// [localReleaseTag] / [localReleaseTagVersion] — ה-release שממנו הגיע ה-DB
  /// המקומי והגרסה שנרשמה איתו, אם ידועים. ראו [_isContentRefresh].
  /// [blockingSchemaVersion] — סכמה שנראתה ב-releases ואיננו יודעים להחיל
  /// (`LibraryDiscoveryResult.blockingSchemaVersion`). לתוכנית עצמה אין בה
  /// צורך — ה-edges שלה כבר סוננו — אלא רק להסבר שמוצג למשתמש.
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
  }) {
    // היעד של הורדה מלאה הוא מה שהנכס מביא, לא מה שקיים ב-releases: אחרת
    // האימות שאחרי החילוץ דוחה את המסד. הפער נסגר באותה החלה עצמה, דרך
    // [LibraryUpdatePlan.followUpDelta].
    final fullTargetVersion = latestFullDbVersion ?? latestVersion;

    if (!hasLocalVersionMeta) {
      return _fullOrBlocked(
        localVersion: localVersion,
        latestVersion: latestVersion,
        fullTargetVersion: fullTargetVersion,
        edges: edges,
        asset: latestFullDbAsset,
        tag: fullDbReleaseTag,
        reason: AppL10n.strings.libraryDomain.planLocalVersionUnknown,
        // גרסה מקומית לא ידועה — אין מול מה לדרוש התקדמות, וממילא זה גם
        // המסלול של התקנה טרייה.
        requireProgress: false,
      );
    }

    if (localVersion >= latestVersion) {
      if (latestFullDbAsset != null &&
          fullDbReleaseTag != null &&
          _isContentRefresh(
            localTag: localReleaseTag,
            localTagVersion: localReleaseTagVersion,
            latestTag: latestContentTag,
            localVersion: localVersion,
          )) {
        return LibraryUpdatePlan.fullDownload(
          localVersion: localVersion,
          targetVersion: fullTargetVersion,
          asset: latestFullDbAsset,
          releaseTag: fullDbReleaseTag,
          followUpDelta:
              _followUpDelta(edges, fullTargetVersion, latestVersion),
          reason: AppL10n.strings.libraryDomain
              .planContentChangedWithoutVersionBump(latestContentTag!),
        );
      }
      return LibraryUpdatePlan.none(
        localVersion: localVersion,
        targetVersion: latestVersion,
      );
    }

    // המסלול בקובצי עדכון — עד latest אם אפשר, ואחרת עד הגרסה הגבוהה שהם
    // כן מגיעים אליה. מעבר סכמה חותך את הגרף באמצע, ואז חצי הדרך בעשרות MB
    // עדיפה גם על הישארות במקום וגם על ~1.5GB שנוחתים נמוך יותר.
    final path = _bestReachablePath(edges, localVersion, latestVersion);
    final deltaTarget = path == null ? localVersion : path.last.toVersion;

    // הגרסה שההורדה המלאה מגיעה אליה בסוף, או `localVersion` כשאין מסד מלא
    // בכלל — כלומר "אין מולה מה להשוות".
    final fullAvailable = latestFullDbAsset != null && fullDbReleaseTag != null;
    final fullRouteTarget = fullAvailable
        ? (_followUpDelta(edges, fullTargetVersion, latestVersion)
                ?.targetVersion ??
            fullTargetVersion)
        : localVersion;

    if (path != null && path.isNotEmpty && deltaTarget >= fullRouteTarget) {
      return LibraryUpdatePlan.delta(
        localVersion: localVersion,
        targetVersion: deltaTarget,
        steps: path,
        // מסלול שנעצר מתחת ל-latest אומר למה — אחרת המסך מציג יעד 23 בזמן
        // שקיימת 26, בלי הסבר.
        reason: deltaTarget >= latestVersion
            ? null
            : blockingSchemaVersion != null
                ? AppL10n.strings.libraryDomain.planPartialDeltaSchemaStop(
                    deltaTarget,
                    latestVersion,
                    blockingSchemaVersion,
                  )
                : AppL10n.strings.libraryDomain
                    .planNoDeltaRoute(deltaTarget, latestVersion),
        // ההתאוששות כש-patch נכשל על המסד הזה — ראו
        // [LibraryUpdatePlan.fullDownloadFallback].
        fullDownloadFallback:
            latestFullDbAsset != null && fullDbReleaseTag != null
                ? LibraryUpdatePlan.fullDownload(
                    localVersion: localVersion,
                    targetVersion: fullTargetVersion,
                    asset: latestFullDbAsset,
                    releaseTag: fullDbReleaseTag,
                    followUpDelta:
                        _followUpDelta(edges, fullTargetVersion, latestVersion),
                  )
                : null,
      );
    }

    // אין מסלול patches — או שאין קשתות, או שהן נפסלו בגלל סכמה שאיננו
    // יודעים להחיל. ההסבר נבדל, כי במקרה השני ההורדה המלאה היא **המסלול
    // המתוכנן** ולא נפילה לאחור, וכך זה גם באוצריא עצמה.
    final strings = AppL10n.strings.libraryDomain;
    return _fullOrBlocked(
      localVersion: localVersion,
      latestVersion: latestVersion,
      fullTargetVersion: fullTargetVersion,
      edges: edges,
      asset: latestFullDbAsset,
      tag: fullDbReleaseTag,
      reason: blockingSchemaVersion != null
          ? strings.planPatchSchemaTooNew(blockingSchemaVersion, latestVersion)
          : strings.planNoDeltaRoute(localVersion, latestVersion),
      requireProgress: true,
      blockingSchemaVersion: blockingSchemaVersion,
    );
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

  /// שרשרת ה-patches שמשלימה הורדה מלאה שנוחתת מתחת ל-latest. `null` כשהמסד
  /// המלא כבר בגרסה האחרונה או שאין מסלול משם — ואז מה שהורד הוא כל מה שיש.
  LibraryUpdatePlan? _followUpDelta(
    List<PatchEdge> edges,
    int fullTargetVersion,
    int latestVersion,
  ) {
    if (fullTargetVersion >= latestVersion) return null;
    final path = _findBestPath(edges, fullTargetVersion, latestVersion);
    if (path == null || path.isEmpty) return null;
    return LibraryUpdatePlan.delta(
      localVersion: fullTargetVersion,
      targetVersion: latestVersion,
      steps: path,
    );
  }

  /// [requireProgress] — לדרוש שהתוכנית תעבור את הגרסה המקומית. כבוי רק
  /// כשאין גרסה מקומית להשוות אליה (התקנה טרייה / מסד בלי `schema_meta`).
  LibraryUpdatePlan _fullOrBlocked({
    required int localVersion,
    required int latestVersion,
    required int fullTargetVersion,
    required List<PatchEdge> edges,
    required ReleaseAsset? asset,
    required String? tag,
    required String reason,
    required bool requireProgress,
    int? blockingSchemaVersion,
  }) {
    final strings = AppL10n.strings.libraryDomain;
    if (asset != null && tag != null) {
      final followUp = _followUpDelta(edges, fullTargetVersion, latestVersion);
      final finalTarget = followUp?.targetVersion ?? fullTargetVersion;
      // מסד מלא שגם עם ההשלמה ב-patches אינו עובר את הגרסה המקומית אינו
      // עדכון אלא נסיגה — זה בדיוק המסלול שהחליף מסד v23 במסד v21 ואז נכשל,
      // כשגרסה חדשה עברה לסכמה שאיננו מכירים. עדיף לומר זאת מלגעת במסד.
      if (requireProgress && finalTarget <= localVersion) {
        return LibraryUpdatePlan.blocked(
          localVersion: localVersion,
          targetVersion: latestVersion,
          reason: strings.planFullDbWouldNotProgress(
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
        // סכמה חדשה אינה "נפילה לאחור": הורדת המסד המלא היא המסלול המתוכנן,
        // ולכן ההסבר אומר את זה ולא את "אין מסלול דלתא".
        reason: blockingSchemaVersion != null
            ? strings.planNewSchemaNeedsFullDb(
                latestVersion,
                blockingSchemaVersion,
              )
            : reason,
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
