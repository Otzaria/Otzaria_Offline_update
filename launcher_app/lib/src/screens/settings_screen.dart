import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך ההגדרות — אוטומציה, אחסון, רשת וממשק.
///
/// **אין כאן נתיבים בכוונה.** תיקיית הנתונים צמודה לקובץ ההרצה (ראו
/// [AppPaths]) ומיקום אוצריא מתגלה לבד — שינוי נתיב היה שובר את הרעיון של
/// כונן נייד שנוסע בין מחשבים.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenLog,
  });

  final SettingsController controller;
  final VoidCallback onOpenLog;

  AppSettings get _s => controller.settings;

  Future<void> _set(AppSettings next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'הגדרות',
      description: 'ההורדה תמיד יזומה בלחיצה. ההתקנה מהתיקייה המקומית היא '
          'הדבר היחיד שניתן להפוך לאוטומטי, והיא דורשת אישור חד־פעמי.',
      children: [
        _automationCard(context),
        _downloadCard(context),
        _storageCard(context),
        _networkCard(context),
        _uiCard(context),
      ],
    );
  }

  // ── אוטומציה ──────────────────────────────────────────────────────────────

  Widget _automationCard(BuildContext context) {
    return SettingsCard(
      title: 'אוטומציה',
      subtitle: 'ברירת המחדל: בדיקה מקומית בלבד, בלי להתקין.',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.search_info_24_regular,
          title: 'בדיקת גרסאות בפתיחה',
          subtitle: 'משווה את המותקן למה שיש בתיקייה המקומית — בלי רשת',
          value: _s.autoMetadataCheck,
          onChanged: (v) => _set(_s.copyWith(autoMetadataCheck: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.cloud_24_regular,
          title: 'בדיקת עדכונים אוטומטית כשיש רשת',
          subtitle: 'בדיקה קלה בפתיחה מול GitHub — בלי הורדה. כשל (אין רשת) '
              'נבלע בשקט; הכפתור הידני בדף הבית עובד בכל מקרה',
          value: _s.autoCheckOnlineUpdates,
          onChanged: (v) => _set(_s.copyWith(autoCheckOnlineUpdates: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_arrow_right_24_regular,
          title: 'התקנת תוכנת אוצריא אוטומטית',
          subtitle: 'מתקין בפתיחה כשיש גרסה חדשה בתיקייה המקומית',
          value: _s.autoInstallApp,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: 'תוכנת אוצריא',
            apply: (on) => _set(_s.copyWith(autoInstallApp: on)),
          ),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.database_arrow_right_24_regular,
          title: 'התקנת עדכון ספרייה אוטומטית',
          subtitle: 'מחיל על המסד בפתיחה; מדולג כשאוצריא פתוחה',
          value: _s.autoInstallLibrary,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: 'הספרייה',
            apply: (on) => _set(_s.copyWith(autoInstallLibrary: on)),
          ),
        ),
      ],
    );
  }

  /// התקנה אוטומטית היא הסיכון האמיתי כאן — היא מחליפה קבצים בלי לשאול —
  /// ולכן היא דורשת אישור מפורש והסבר.
  Future<void> _confirmAutoInstall(
    BuildContext context, {
    required bool enabled,
    required String what,
    required Future<void> Function(bool) apply,
  }) async {
    if (!enabled) {
      await apply(false);
      return;
    }

    final approved = await showWarningDialog(
      context: context,
      title: 'התקנה אוטומטית של $what',
      content: 'מעתה $what תותקן ללא אישור נוסף בכל פעם שתימצא גרסה חדשה '
          'בתיקייה שלצד התוכנה. ההורדה עצמה תישאר יזומה.',
      subtitle: 'התקנה מחליפה קבצים במחשב שלך. אם אינך בטוח/ה — עדיף '
          'להשאיר את האפשרות כבויה ולאשר כל עדכון בנפרד.',
      confirmText: 'הפעל התקנה אוטומטית',
    );
    if (!approved) return;
    await apply(true);
  }

  // ── הורדה ─────────────────────────────────────────────────────────────────

  Widget _downloadCard(BuildContext context) {
    return SettingsCard(
      title: 'הורדה',
      subtitle: 'אילו רכיבים כפתור "הורד עכשיו" בדף הבית מביא לתיקייה '
          'המקומית. ההורדה עצמה תמיד יזומה בלחיצה.',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_24_regular,
          title: 'תוכנת אוצריא',
          subtitle: 'קובץ ההתקנה של הגרסה האחרונה',
          value: _s.syncApp,
          onChanged: (v) => _set(_s.copyWith(syncApp: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.library_24_regular,
          title: 'הספרייה',
          subtitle: 'הרכיב הכבד — המסד המלא הוא כ-1GB',
          value: _s.syncLibrary,
          onChanged: (v) => _set(_s.copyWith(syncLibrary: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'חנות התוספים',
          subtitle: 'הקטלוג וקובצי ההתקנה של כל התוספים',
          value: _s.syncPlugins,
          onChanged: (v) => _set(_s.copyWith(syncPlugins: v)),
        ),
      ],
    );
  }

  // ── אחסון ─────────────────────────────────────────────────────────────────

  Widget _storageCard(BuildContext context) {
    return SettingsCard(
      title: 'אחסון',
      subtitle: 'תיקיית הנתונים קבועה ליד קובץ ההרצה, ואין דרך לשנות אותה — '
          'כדי שהכול ייסע יחד על הכונן.',
      children: [
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.history_24_regular,
          title: 'גיבוי בטיחות של המסד',
          subtitle: 'לפני כתיבת מסד מלא: "כבוי" מתקין רק את הגרסה שהורדה, '
              'בלי רשת הצלה אם הכתיבה תיכשל באמצע',
          currentValue: _s.backupsToKeep,
          onChanged: (v) => _set(_s.copyWith(backupsToKeep: v)),
          options: const [
            SegmentOption(value: 0, label: 'כבוי'),
            SegmentOption(value: 1, label: 'פועל'),
          ],
        ),
      ],
    );
  }

  // ── רשת ───────────────────────────────────────────────────────────────────

  Widget _networkCard(BuildContext context) {
    return SettingsCard(
      title: 'רשת',
      subtitle: 'הרשת נדרשת רק בהורדה. בדיקה והתקנה עובדות בלעדיה תמיד.',
      children: [
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.timer_24_regular,
          title: 'timeout להורדה',
          subtitle: 'שניות עד שפנייה לרשת נחשבת כשל',
          currentValue: _s.networkTimeoutSeconds,
          onChanged: (v) => _set(_s.copyWith(networkTimeoutSeconds: v)),
          options: const [
            SegmentOption(value: 10, label: '10'),
            SegmentOption(value: 20, label: '20'),
            SegmentOption(value: 45, label: '45'),
          ],
        ),
      ],
    );
  }

  // ── ממשק ותמיכה ───────────────────────────────────────────────────────────

  /// רוחב קבוע לשתי השורות למטה — כך שתיבות ערכת הנושא, שהתווית הארוכה
  /// ביניהן ("לפי המערכת") הייתה מגדילה אותן יותר מהשורה השנייה, יושבות
  /// באותו גודל בדיוק כמו תיבות גודל הטקסט.
  static const double _uiSegmentWidth = 300;

  Widget _uiCard(BuildContext context) {
    return SettingsCard(
      title: 'ממשק ותמיכה',
      children: [
        SettingsActionTile.segmentedTile<AppThemeMode>(
          icon: FluentIcons.dark_theme_24_regular,
          title: 'ערכת נושא',
          currentValue: _s.themeMode,
          onChanged: (v) => _set(_s.copyWith(themeMode: v)),
          width: _uiSegmentWidth,
          options: const [
            SegmentOption(value: AppThemeMode.system, label: 'מערכת'),
            SegmentOption(value: AppThemeMode.light, label: 'בהיר'),
            SegmentOption(value: AppThemeMode.dark, label: 'כהה'),
          ],
        ),
        SettingsActionTile.segmentedTile<double>(
          icon: FluentIcons.text_font_size_24_regular,
          title: 'גודל טקסט',
          currentValue: _s.textScale,
          onChanged: (v) => _set(_s.copyWith(textScale: v)),
          width: _uiSegmentWidth,
          options: const [
            SegmentOption(value: 0.9, label: 'קטן'),
            SegmentOption(value: 1.0, label: 'רגיל'),
            SegmentOption(value: 1.15, label: 'גדול'),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.document_bullet_list_24_regular,
          title: 'יומן הפעילות',
          subtitle: 'כל הבדיקות, ההורדות וההתקנות נרשמות מקומית בלבד',
          actions: [
            ActionButton.neutral(
              text: 'פתיחת תיקיית הלוגים',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: onOpenLog,
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.arrow_reset_24_regular,
          title: 'איפוס ההגדרות',
          subtitle: 'מחזיר את כל ההגדרות לברירת המחדל, בלי למחוק התקנות',
          actions: [
            ActionButton.warning(
              text: 'איפוס',
              onPressed: () => _confirmReset(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final approved = await showWarningDialog(
      context: context,
      title: 'איפוס ההגדרות',
      content: 'כל ההגדרות יחזרו לברירת המחדל.',
      subtitle: 'ההתקנות עצמן, המסד, התוספים והעדכונים שהורדו לא יימחקו.',
      confirmText: 'אפס הגדרות',
    );
    if (!approved) return;
    await _set(const AppSettings());
    UiSnack.showSuccess('ההגדרות אופסו');
  }
}
