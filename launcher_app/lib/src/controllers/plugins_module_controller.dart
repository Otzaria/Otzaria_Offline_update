import 'package:flutter/foundation.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../services/app_logger.dart';
import 'progress_notifier.dart';

enum PluginsModuleStatus { idle, loading, ready, syncing, error }

/// סינון לפי סטטוס התוסף בחנות (`stable` / `beta` / `experimental`).
enum PluginStatusFilter { all, stable, beta, experimental }

/// עוטף את [PluginsManager] כמצב הניתן לצפייה עבור מסך החנות — טעינת
/// הקטלוג המקומי, הורדה יזומה מהאתר, סינון, שמירת קובץ והתקנה ישירה.
///
/// [load] בלבד נקרא בפתיחה: הוא קורא מהתיקייה המקומית וסורק את ההתקנה של
/// אוצריא, ולא נוגע ברשת. [sync] היא הפעולה היחידה שדורשת אינטרנט.
class PluginsModuleController extends ChangeNotifier with ProgressNotifier {
  PluginsModuleController({required String mirrorRootDir})
      // תיקיית התוספים של אוצריא מזוהה אוטומטית ואינה ניתנת להגדרה —
      // ראו AppPaths: אין נתיבים בהגדרות.
      : _manager = PluginsManager(
          resolveMirrorDir: () async => mirrorRootDir,
        );

  final PluginsManager _manager;

  /// זמן קצוב לפעולות רשת (מהגדרות "רשת") — נכנס לתוקף בבקשה הבאה.
  set networkTimeout(Duration value) => _manager.networkTimeout = value;

  PluginsModuleStatus status = PluginsModuleStatus.idle;
  String? errorMessage;

  List<StorePlugin> plugins = const [];
  Map<String, String> installed = const {};
  DateTime? lastSync;

  /// שורש קובצי החנות במראה — ממנו נבנים נתיבי התמונות המוחלטים.
  String? pluginsDir;

  // ── סינון ─────────────────────────────────────────────────────────────────
  String search = '';

  /// החנות נפתחת על "הכול" — המשתמש בא לראות מה קיים, לא רק את היציב.
  PluginStatusFilter statusFilter = PluginStatusFilter.all;
  String? tagFilter;

  /// הצג רק מה שלא מותקן או שיש לו עדכון — דלוק כברירת מחדל, כמו בחנות
  /// המקורית: המשתמש בא לעדכן, לא לגלול על מה שכבר מותקן.
  bool hideInstalled = true;

  // ── סנכרון ────────────────────────────────────────────────────────────────
  String? syncMessage;
  double? syncProgress;
  final List<String> syncWarnings = [];

  /// טוען את הקטלוג המקומי וסורק את התוספים המותקנים. ללא רשת.
  Future<void> load() async {
    status = PluginsModuleStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final view = await _manager.load();
      plugins = view.catalog.plugins;
      lastSync = view.catalog.lastSync;
      installed = view.installed;
      pluginsDir = view.pluginsDir;
      _invalidateDerived();
      status = PluginsModuleStatus.ready;
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('טעינת קטלוג התוספים נכשלה', e, st);
    }
    notifyListeners();
  }

  /// מסנכרן את הקטלוג והקבצים מהאתר אל המראה. דורש אינטרנט.
  Future<void> sync() async {
    status = PluginsModuleStatus.syncing;
    errorMessage = null;
    syncMessage = 'מתחיל סנכרון...';
    syncProgress = null;
    syncWarnings.clear();
    notifyListeners();

    try {
      await _manager.sync(onProgress: (progress) {
        syncMessage = progress.message;
        if (progress.phase == PluginSyncPhase.warning) {
          syncWarnings.add(progress.message);
        } else if (progress.fraction != null) {
          syncProgress = progress.fraction;
        }
        // הסנכרון מדווח פעמים רבות בשנייה (נכס אחר נכס) — מדולל, כמו
        // שאר מדי ההתקדמות.
        notifyProgress();
      });
      AppLogger.instance.info('סנכרון חנות התוספים הושלם');
      await load();
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('סנכרון חנות התוספים נכשל', e, st);
      notifyListeners();
    }
  }

  // ── פעולות על תוסף בודד ───────────────────────────────────────────────────

  StorePlugin? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  PluginInstallStatus statusOf(StorePlugin plugin) =>
      plugin.statusAgainst(installed);

  /// הגרסה המותקנת של התוסף, או null אם אינו מותקן.
  String? installedVersionOf(StorePlugin plugin) =>
      plugin.manifestId == null ? null : installed[plugin.manifestId];

  String suggestedFileName(StorePlugin plugin) =>
      _manager.suggestedFileName(plugin);

  /// נתיב מוחלט לנכס (תמונה / צילום מסך) שנשמר בקטלוג כנתיב יחסי.
  String? assetPath(String? relativePath) {
    final root = pluginsDir;
    if (root == null || relativePath == null || relativePath.isEmpty) {
      return null;
    }
    return PluginMirrorStore.resolveAgainst(root, relativePath);
  }

  Future<PluginInstallResult> saveCopy(StorePlugin plugin, String destPath) =>
      _manager.saveCopy(plugin, destPath);

  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    final result = await _manager.directInstall(plugin);
    if (!result.success) {
      AppLogger.instance.error(
        'התקנה ישירה של ${plugin.name} נכשלה: ${result.error}',
      );
    }
    return result;
  }

  Future<PluginInstallResult> openHomepage(String url) =>
      _manager.openExternalUrl(url);

  // ── סינון ─────────────────────────────────────────────────────────────────

  void setSearch(String value) {
    if (search == value) return;
    search = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setStatusFilter(PluginStatusFilter value) {
    if (statusFilter == value) return;
    statusFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setTagFilter(String? value) {
    if (tagFilter == value) return;
    tagFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setHideInstalled(bool value) {
    if (hideInstalled == value) return;
    hideInstalled = value;
    _invalidateDerived();
    notifyListeners();
  }

  // ── תוצרים מחושבים, ממוזנים ───────────────────────────────────────────────
  // כל אלה נקראו ישירות מ-`build`, ולכן חושבו מחדש בכל בנייה של המסך — כולל
  // בכל דיווח התקדמות של הורדה. `filtered` לבדו הוא `statusOf` לכל תוסף
  // ו-`allTags` הוא מיון. הם משתנים רק כשהקטלוג או הסינון משתנים, ולכן
  // נשמרים עד ל-[_invalidateDerived].
  List<StorePlugin>? _filtered;
  List<String>? _allTags;
  List<StorePlugin>? _updatable;

  void _invalidateDerived() {
    _filtered = null;
    _allTags = null;
    _updatable = null;
  }

  List<StorePlugin> get filtered => _filtered ??= plugins.where((plugin) {
        if (!plugin.matchesQuery(search)) return false;
        if (statusFilter != PluginStatusFilter.all &&
            plugin.status != statusFilter.name) {
          return false;
        }
        if (tagFilter != null && !plugin.tags.contains(tagFilter)) return false;
        if (hideInstalled && statusOf(plugin) == PluginInstallStatus.upToDate) {
          return false;
        }
        return true;
      }).toList(growable: false);

  List<String> get allTags => _allTags ??= () {
        final tags = <String>{};
        for (final plugin in plugins) {
          tags.addAll(plugin.tags);
        }
        return tags.toList()..sort();
      }();

  /// תוספים שמותקנים אצל המשתמש בגרסה ישנה מזו שבחנות.
  List<StorePlugin> get updatablePlugins => _updatable ??= plugins
      .where((p) => statusOf(p) == PluginInstallStatus.updateAvailable)
      .toList(growable: false);

  int get installedCount => installed.length;

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
