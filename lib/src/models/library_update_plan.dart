import 'package:equatable/equatable.dart';

import 'delta_manifest.dart';
import 'library_release.dart';

/// קשת בגרף העדכונים: patch בודד מ-[fromVersion] ל-[toVersion], עם ה-manifest
/// שלו וה-URLs להורדת קבצי ה-patch.
class PatchEdge extends Equatable {
  final DeltaManifest manifest;

  /// URL להורדת כל קובץ patch, ממופה לפי שם הקובץ (`patchFiles[].file`).
  final Map<String, String> patchFileUrls;

  /// כתובת ה-manifest עצמו (לתיעוד/דיווח שגיאות).
  final String manifestUrl;

  const PatchEdge({
    required this.manifest,
    required this.patchFileUrls,
    required this.manifestUrl,
  });

  int get fromVersion => manifest.fromVersion;
  int get toVersion => manifest.toVersion;

  /// גודל ההורדה הדחוס הכולל של קשת זו.
  int get compressedSize => manifest.totalCompressedSize;

  @override
  List<Object?> get props => [manifest, patchFileUrls, manifestUrl];
}

/// סוג תוכנית העדכון שנבחרה.
enum LibraryUpdatePlanKind {
  /// הספרייה כבר מעודכנת.
  none,

  /// קיים מסלול דלתא בטוח — רשימת patches להחלה.
  delta,

  /// אין מסלול דלתא בטוח — צריך להוריד DB מלא.
  fullDownload,

  /// מצב לא תקין שדורש פעולה ידנית.
  blocked,
}

/// תוצאת התכנון: מה צריך לעשות כדי להביא את הספרייה לגרסה האחרונה.
class LibraryUpdatePlan extends Equatable {
  final LibraryUpdatePlanKind kind;

  /// הגרסה המקומית הנוכחית (או 0 אם לא ידועה).
  final int localVersion;

  /// הגרסה היעד (latest). null אם לא נמצאה.
  final int? targetVersion;

  /// שלבי הדלתא להחלה, בסדר (עבור [LibraryUpdatePlanKind.delta]).
  final List<PatchEdge> deltaSteps;

  /// ה-DB המלא להורדה (עבור [LibraryUpdatePlanKind.fullDownload]).
  final ReleaseAsset? fullDbAsset;

  /// ה-tag של ה-release שממנו יורד ה-DB המלא.
  final String? fullDbReleaseTag;

  /// הסבר קריא — חובה ל-[LibraryUpdatePlanKind.blocked], אופציונלי לאחרים.
  final String? reason;

  const LibraryUpdatePlan._({
    required this.kind,
    required this.localVersion,
    this.targetVersion,
    this.deltaSteps = const [],
    this.fullDbAsset,
    this.fullDbReleaseTag,
    this.reason,
  });

  /// הספרייה מעודכנת — אין מה לעשות.
  factory LibraryUpdatePlan.none({
    required int localVersion,
    int? targetVersion,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.none,
        localVersion: localVersion,
        targetVersion: targetVersion ?? localVersion,
      );

  /// מסלול דלתא — סדרת patches להחלה.
  factory LibraryUpdatePlan.delta({
    required int localVersion,
    required int targetVersion,
    required List<PatchEdge> steps,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.delta,
        localVersion: localVersion,
        targetVersion: targetVersion,
        deltaSteps: List.unmodifiable(steps),
      );

  /// מסלול הורדה מלאה.
  factory LibraryUpdatePlan.fullDownload({
    required int localVersion,
    int? targetVersion,
    required ReleaseAsset asset,
    required String releaseTag,
    String? reason,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.fullDownload,
        localVersion: localVersion,
        targetVersion: targetVersion,
        fullDbAsset: asset,
        fullDbReleaseTag: releaseTag,
        reason: reason,
      );

  /// מצב חסום — דורש פעולה ידנית.
  factory LibraryUpdatePlan.blocked({
    required int localVersion,
    int? targetVersion,
    required String reason,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.blocked,
        localVersion: localVersion,
        targetVersion: targetVersion,
        reason: reason,
      );

  /// גודל ההורדה הכולל בבייטים (דחוס) — לתצוגה למשתמש.
  int get totalDownloadSize {
    switch (kind) {
      case LibraryUpdatePlanKind.delta:
        return deltaSteps.fold<int>(0, (sum, e) => sum + e.compressedSize);
      case LibraryUpdatePlanKind.fullDownload:
        return fullDbAsset?.size ?? 0;
      case LibraryUpdatePlanKind.none:
      case LibraryUpdatePlanKind.blocked:
        return 0;
    }
  }

  @override
  List<Object?> get props => [
        kind,
        localVersion,
        targetVersion,
        deltaSteps,
        fullDbAsset,
        fullDbReleaseTag,
        reason,
      ];
}
