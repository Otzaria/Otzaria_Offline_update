import 'package:seforim_library_updater/seforim_library_updater.dart';

/// תוצאת בדיקת עדכון למסד (ה-DB). אם [dbPath] הוא null, לא נמצא DB לא
/// בנתיב מותאם אישית ולא בברירת המחדל של אוצריא — ה-UI צריך לבקש
/// מהמשתמש להצביע על התיקייה, ואז לקרוא ל-`LibraryManager.setCustomDbPath`.
class LibraryUpdateCheckResult {
  const LibraryUpdateCheckResult({
    required this.dbPath,
    this.localVersion,
    this.plan,
  });

  final String? dbPath;
  final LocalDbVersion? localVersion;
  final LibraryUpdatePlan? plan;

  bool get needsManualDbPath => dbPath == null;

  bool get updateAvailable =>
      plan != null && plan!.kind != LibraryUpdatePlanKind.none;
}
