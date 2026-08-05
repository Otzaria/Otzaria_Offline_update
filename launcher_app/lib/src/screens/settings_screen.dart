import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך ההגדרות — אוטומציה, ערוצים, נתיבים, רשת וממשק (תכנון §8).
/// כל אפשרויות ההורדה וההתקנה האוטומטיות כבויות בברירת מחדל.
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
      description: 'הפרדה מלאה בין הורדה אוטומטית להתקנה אוטומטית. '
          'התקנה אוטומטית דורשת אישור חד־פעמי.',
      children: [
        _automationCard(context),
        _channelsCard(context),
        _pathsCard(context),
        _networkCard(context),
        _uiCard(context),
      ],
    );
  }

  // ── אוטומציה ──────────────────────────────────────────────────────────────

  Widget _automationCard(BuildContext context) {
    return SettingsCard(
      title: 'אוטומציה',
      subtitle: 'ברירת המחדל: בדיקה קלה בלבד, בלי להוריד ובלי להתקין.',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.search_info_24_regular,
          title: 'בדיקת מטא־דאטה אוטומטית',
          subtitle: 'בדיקת גרסאות בפתיחה, ללא הורדה',
          value: _s.autoMetadataCheck,
          onChanged: (v) => _set(_s.copyWith(autoMetadataCheck: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.arrow_download_24_regular,
          title: 'הורדת עדכון תוכנת אוצריא',
          subtitle: 'מוריד גרסה חדשה למטמון, בלי להתקין',
          value: _s.autoDownloadApp,
          onChanged: (v) => _set(_s.copyWith(autoDownloadApp: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_arrow_right_24_regular,
          title: 'התקנת עדכון תוכנת אוצריא',
          subtitle: 'מתקין לאחר הורדה; דורש שאוצריא תהיה סגורה',
          value: _s.autoInstallApp,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: 'תוכנת אוצריא',
            apply: (on) => _set(
              _s.copyWith(
                  autoInstallApp: on, autoDownloadApp: on ? true : null),
            ),
          ),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.arrow_download_24_regular,
          title: 'הורדת עדכון ספרייה',
          subtitle: 'מוריד דלתא או מסד מלא למטמון',
          value: _s.autoDownloadLibrary,
          onChanged: (v) => _set(_s.copyWith(autoDownloadLibrary: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.database_arrow_right_24_regular,
          title: 'התקנת עדכון ספרייה',
          subtitle: 'מחיל את העדכון על המסד לאחר אימות',
          value: _s.autoInstallLibrary,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: 'ספריית הספרים',
            apply: (on) => _set(
              _s.copyWith(
                autoInstallLibrary: on,
                autoDownloadLibrary: on ? true : null,
              ),
            ),
          ),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'הורדת עדכוני תוספים מותקנים',
          subtitle: 'רק תוספים שזוהו במחשב הזה',
          value: _s.autoDownloadInstalledPlugins,
          enabled: false,
          onChanged: (v) => _set(_s.copyWith(autoDownloadInstalledPlugins: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'התקנת עדכוני תוספים מותקנים',
          subtitle: 'יתאפשר כשמודול התוספים ייבנה',
          value: _s.autoInstallInstalledPlugins,
          enabled: false,
          onChanged: (v) => _set(_s.copyWith(autoInstallInstalledPlugins: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.box_24_regular,
          title: 'הורדת כלל התוספים',
          subtitle: 'מיועד להכנת חבילת USB מלאה',
          value: _s.autoDownloadAllPlugins,
          enabled: false,
          onChanged: (v) => _set(_s.copyWith(autoDownloadAllPlugins: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.usb_stick_24_regular,
          title: 'הכנת חבילת USB אוטומטית',
          subtitle: 'מסנכרן ליעד הנבחר כשהוא מחובר',
          value: _s.autoPrepareUsbBundle,
          enabled: false,
          onChanged: (v) => _set(_s.copyWith(autoPrepareUsbBundle: v)),
        ),
      ],
    );
  }

  /// התקנה אוטומטית היא הסיכון האמיתי כאן — ולכן היא דורשת אישור מפורש
  /// והסבר, ומדליקה גם את ההורדה האוטומטית שהיא תלויה בה (תכנון §8.1).
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
      content: 'מעתה $what תותקן ללא אישור נוסף בכל פעם שיימצא עדכון. '
          'ההורדה האוטומטית תודלק גם היא, כי ההתקנה תלויה בה.',
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
        label: 'כולל preview',
      ),
    ];

    return SettingsCard(
      title: 'ערוצי גרסאות',
      subtitle: 'בחירת preview לרכיב אחד אינה חלה על השאר.',
      children: [
        SettingsActionTile.segmentedTile<UpdateChannel>(
          icon: FluentIcons.desktop_24_regular,
          title: 'תוכנת אוצריא',
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
        SettingsActionTile.segmentedTile<UpdateChannel>(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'תוספים',
          options: options,
          currentValue: _s.pluginsChannel,
          onChanged: (v) => _set(_s.copyWith(pluginsChannel: v)),
        ),
      ],
    );
  }

  // ── נתיבים ואחסון ─────────────────────────────────────────────────────────

  Widget _pathsCard(BuildContext context) {
    return SettingsCard(
      title: 'נתיבים ואחסון',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.desktop_24_regular,
          title: 'נתיב התקנת אוצריא',
          path: _s.otzariaInstallPath,
          placeholder: 'זיהוי אוטומטי',
          actions: [
            ActionButton.neutral(
              text: 'בחירת תיקייה',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: () => _pickDir(
                'בחירת תיקיית ההתקנה של אוצריא',
                (path) => _set(_s.copyWith(otzariaInstallPath: path)),
              ),
            ),
          ],
        ),
        SettingsActionTile.path(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'תיקיית התוספים',
          path: _s.pluginsPath,
          placeholder: 'תיקבע כשמודול התוספים ייבנה',
        ),
        SettingsActionTile.path(
          icon: FluentIcons.usb_stick_24_regular,
          title: 'יעד USB מועדף',
          path: _s.preferredUsbPath,
          placeholder: 'לא נבחר',
          actions: [
            ActionButton.neutral(
              text: 'בחירת יעד',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: () => _pickDir(
                'בחירת יעד ה-USB המועדף',
                (path) => _set(_s.copyWith(preferredUsbPath: path)),
              ),
            ),
          ],
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

  Future<void> _pickDir(
      String title, Future<void> Function(String) apply) async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: title);
    if (path == null) return;
    await apply(path);
    UiSnack.showSuccess('הנתיב נשמר');
  }

  // ── רשת ───────────────────────────────────────────────────────────────────

  Widget _networkCard(BuildContext context) {
    return SettingsCard(
      title: 'רשת',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.plug_disconnected_24_regular,
          title: 'עבודה offline בלבד',
          subtitle: 'לא תתבצע שום פנייה לרשת, גם לא בדיקת גרסאות',
          value: _s.offlineOnly,
          onChanged: (v) => _set(_s.copyWith(offlineOnly: v)),
        ),
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.timer_24_regular,
          title: 'timeout לבדיקת רשת',
          subtitle: 'שניות עד שבדיקה נחשבת כשל',
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
      content: 'כל ההגדרות יחזרו לברירת המחדל, כולל הנתיבים השמורים.',
      subtitle: 'ההתקנות עצמן, המסד והתוספים לא יימחקו.',
      confirmText: 'אפס הגדרות',
    );
    if (!approved) return;
    await _set(const AppSettings());
    UiSnack.showSuccess('ההגדרות אופסו');
  }
}
