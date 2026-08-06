import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך ההגדרות — אוטומציה, ערוצים, אחסון, רשת וממשק.
///
/// **אין כאן נתיבים בכוונה.** תיקיית הנתונים צמודה לקובץ ההרצה (ראו
/// [AppPaths]) ומיקום אוצריא מתגלה לבד — שינוי נתיב היה שובר את הרעיון של
/// כונן נייד שנוסע בין מחשבים.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.dataDir,
    required this.onOpenLog,
  });

  final SettingsController controller;
  final String dataDir;
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
        _channelsCard(context),
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
            what: 'ספריית הספרים',
            apply: (on) => _set(_s.copyWith(autoInstallLibrary: on)),
          ),
        ),
        // התקנת תוסף עוברת דרך הפרוטוקול otzaria://, שפותח את אוצריא בכל
        // תוסף בנפרד — ולכן היא לא יכולה לרוץ ברקע ונשארת יזומה מהחנות.
        SettingsActionTile.text(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'התקנת תוספים אוטומטית',
          subtitle: 'לא זמין — ההתקנה פותחת את אוצריא לכל תוסף בנפרד, '
              'ולכן היא תמיד יזומה מהחנות',
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

  // ── ערוצים ────────────────────────────────────────────────────────────────

  Widget _channelsCard(BuildContext context) {
    const options = [
      SegmentOption(value: UpdateChannel.stable, label: 'יציב בלבד'),
      SegmentOption(
        value: UpdateChannel.stableAndPreview,
        label: 'כולל pre-release',
      ),
    ];

    return SettingsCard(
      title: 'ערוצי גרסאות',
      subtitle: 'release רגיל = יציב, pre-release = לא יציב. הבחירה משפיעה '
          'על מה שההורדה מביאה, ובחירה לרכיב אחד אינה חלה על השאר.',
      children: [
        SettingsActionTile.segmentedTile<UpdateChannel>(
          icon: FluentIcons.desktop_24_regular,
          title: 'תוכנת אוצריא',
          subtitle: 'הריפו של אוצריא מפרסם כמעט רק pre-release — בערוץ היציב '
              'ייתכן שלא תימצא גרסה כלל',
          options: options,
          currentValue: _s.appChannel,
          onChanged: (v) => _set(_s.copyWith(appChannel: v)),
        ),
        SettingsActionTile.segmentedTile<UpdateChannel>(
          icon: FluentIcons.library_24_regular,
          title: 'ספריית הספרים',
          options: options,
          currentValue: _s.libraryChannel,
          onChanged: (v) => _set(_s.copyWith(libraryChannel: v)),
        ),
        // לתוספים אין ערוץ pre-release — לכל תוסף יש `status` משלו
        // (יציב/בטא/ניסיוני). לכן הבחירה כאן קובעת את סינון ברירת המחדל
        // של החנות, והתוויות שונות משל שני הרכיבים האחרים.
        SettingsActionTile.segmentedTile<UpdateChannel>(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'תוספים',
          subtitle: 'קובע לפי מה החנות נפתחת מסוננת; ניתן לשנות בחנות עצמה',
          currentValue: _s.pluginsChannel,
          onChanged: (v) => _set(_s.copyWith(pluginsChannel: v)),
          options: const [
            SegmentOption(value: UpdateChannel.stable, label: 'יציב בלבד'),
            SegmentOption(
              value: UpdateChannel.stableAndPreview,
              label: 'כולל בטא וניסיוני',
            ),
          ],
        ),
      ],
    );
  }

  // ── אחסון ─────────────────────────────────────────────────────────────────

  Widget _storageCard(BuildContext context) {
    return SettingsCard(
      title: 'אחסון',
      subtitle: 'תיקיית הנתונים קבועה ליד קובץ ההרצה, כדי שהכול ייסע יחד '
          'על הכונן. אין דרך לשנות אותה — וזה בכוונה.',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית הנתונים',
          path: dataDir,
          placeholder: '—',
        ),
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.history_24_regular,
          title: 'גיבויים לשמירה',
          subtitle: 'כמה גיבויים של המסד יישמרו לפני מחיקת הישן',
          currentValue: _s.backupsToKeep,
          onChanged: (v) => _set(_s.copyWith(backupsToKeep: v)),
          options: const [
            SegmentOption(value: 1, label: '1'),
            SegmentOption(value: 2, label: '2'),
            SegmentOption(value: 3, label: '3'),
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

  Widget _uiCard(BuildContext context) {
    return SettingsCard(
      title: 'ממשק ותמיכה',
      children: [
        SettingsActionTile.segmentedTile<AppThemeMode>(
          icon: FluentIcons.dark_theme_24_regular,
          title: 'ערכת נושא',
          currentValue: _s.themeMode,
          onChanged: (v) => _set(_s.copyWith(themeMode: v)),
          options: const [
            SegmentOption(value: AppThemeMode.system, label: 'לפי המערכת'),
            SegmentOption(value: AppThemeMode.light, label: 'בהיר'),
            SegmentOption(value: AppThemeMode.dark, label: 'כהה'),
          ],
        ),
        SettingsActionTile.segmentedTile<double>(
          icon: FluentIcons.text_font_size_24_regular,
          title: 'גודל טקסט',
          currentValue: _s.textScale,
          onChanged: (v) => _set(_s.copyWith(textScale: v)),
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
