import 'package:equatable/equatable.dart';

import 'delta_manifest.dart';
import 'library_release.dart';
import 'patch_table_spec.dart';

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

  /// האם שני קצות ה-patch בסכמות DB שיש להן סדר hash.
  bool get hasSupportedSchema =>
      isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
      isSupportedSchemaVersion(manifest.toSchemaVersion);

  /// האם פורמט ה-`patch.db` שהמניפסט מצהיר עליו ניתן להחלה. מניפסט היסטורי
  /// (סכמות 1–3) אינו נושא את השדה, ושם ה-preflight של `PatchApplier` נשאר
  /// השער היחיד — ראו `DeltaManifest.patchFormatVersion`.
  bool get hasSupportedPatchFormat {
    final format = manifest.patchFormatVersion;
    return format == null || isSupportedPatchFormatVersion(format);
  }

  /// האם אפשר להחיל את הקשת בכלל — **שני** צירי היכולת. קשת שאינה כזו
  /// מסוננת ב-`LibraryUpdateDiscovery` ואינה נכנסת למראה: המסלול לגרסה כזו
  /// הוא מסד מלא, לא קובצי עדכון.
  bool get isApplicable => hasSupportedSchema && hasSupportedPatchFormat;

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

  /// תוכנית ההורדה המלאה שממתינה מאחורי מסלול דלתא — מסלול ההתאוששות
  /// היחיד כש-patch אינו מתאים למסד שעל המחשב. המסד המלא ממילא יושב במראה,
  /// ובלי הנתיב הזה משתמש שנתקל ב-patch כזה נשאר תקוע לנצח (issue #19).
  /// `null` רק כשאין במראה מסד מלא בכלל.
  final LibraryUpdatePlan? fullDownloadFallback;

  /// שרשרת ה-patches שרצה **מיד אחרי** הורדה מלאה שנוחתת על גרסה ישנה
  /// מ-latest. המראה מעדיפה לשמור מסד מלא שכבר עליה על פני הורדת ~1.1GB
  /// חדשים (`LibraryMirrorExporter._chooseFullDbCarrier`), ובלי ההשלמה הזו
  /// התקנה על מחשב ריק הייתה נעצרת על אותה גרסה ישנה.
  final LibraryUpdatePlan? followUpDelta;

  const LibraryUpdatePlan._({
    required this.kind,
    required this.localVersion,
    this.targetVersion,
    this.deltaSteps = const [],
    this.fullDbAsset,
    this.fullDbReleaseTag,
    this.reason,
    this.fullDownloadFallback,
    this.followUpDelta,
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
    String? reason,
    LibraryUpdatePlan? fullDownloadFallback,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.delta,
        localVersion: localVersion,
        targetVersion: targetVersion,
        deltaSteps: List.unmodifiable(steps),
        reason: reason,
        fullDownloadFallback: fullDownloadFallback,
      );

  /// מסלול הורדה מלאה.
  factory LibraryUpdatePlan.fullDownload({
    required int localVersion,
    int? targetVersion,
    required ReleaseAsset asset,
    required String releaseTag,
    String? reason,
    LibraryUpdatePlan? followUpDelta,
  }) =>
      LibraryUpdatePlan._(
        kind: LibraryUpdatePlanKind.fullDownload,
        localVersion: localVersion,
        targetVersion: targetVersion,
        fullDbAsset: asset,
        fullDbReleaseTag: releaseTag,
        reason: reason,
        followUpDelta: followUpDelta,
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

  /// הגרסה שהמסד יגיע אליה **בסוף** התוכנית, כולל ההשלמה ב-patches שרצה
  /// אחרי הורדה מלאה. [targetVersion] הוא היעד של השלב הראשון בלבד — מה
  /// שהאימות אחרי החילוץ דורש — ולכן הצגתו הבטיחה למשתמש את גרסת המסד המלא
  /// במקום את הגרסה שיקבל בפועל.
  int? get finalTargetVersion => followUpDelta?.targetVersion ?? targetVersion;

  /// גודל ההורדה הכולל בבייטים (דחוס) — לתצוגה למשתמש.
  int get totalDownloadSize {
    switch (kind) {
      case LibraryUpdatePlanKind.delta:
        return deltaSteps.fold<int>(0, (sum, e) => sum + e.compressedSize);
      case LibraryUpdatePlanKind.fullDownload:
        return (fullDbAsset?.size ?? 0) +
            (followUpDelta?.totalDownloadSize ?? 0);
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
        fullDownloadFallback,
        followUpDelta,
      ];
}
