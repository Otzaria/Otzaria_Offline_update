import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../controllers/otzaria_module_controller.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// נוסח דיאלוג ההתקנה — משותף למסך הזה ולאריח בדף הבית, כדי שהאזהרה על
/// גרסה לא-יציבה תופיע בשניהם.
String appInstallPrompt(OtzariaModuleController c) {
  final channelNote = c.hasChannelChoice && c.preferPrerelease
      ? ' זו הגרסה הלא-יציבה (pre-release) שנבחרה בהגדרות מסך התוכנה.'
      : '';
  return 'הגרסה ${c.latestVersion} תותקן מהתיקייה המקומית על גבי '
      '${c.currentVersion ?? 'ההתקנה הקיימת'}.$channelNote '
      'ההתקנה אינה דורשת אינטרנט. יש לוודא שאוצריא סגורה.';
}

/// מסך עדכון תוכנת אוצריא — מקביל במבנה ל-[LibraryScreen]: מצב, מה
/// התחדש בגרסה האחרונה, והתיקייה שממנה מותקנים.
class OtzariaScreen extends StatelessWidget {
  const OtzariaScreen({
    super.key,
    required this.otzaria,
    required this.settings,
    required this.otzariaIsRunning,
  });

  final OtzariaModuleController otzaria;

  /// בחירת ערוץ הגרסה נשמרת בהגדרות, כדי שתישאר בין הפעלות.
  final SettingsController settings;
  final bool otzariaIsRunning;

  /// **לא** תלוי בהורדה גלובלית: הורדה של רכיב אחר (למשל הספרייה) לא
  /// אמורה לחסום פעולות מקומיות כאן (בחירת מיקום, בדיקה מחדש).
  bool get _isBusy => otzaria.status == OtzariaModuleStatus.installing;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'עדכון תוכנת אוצריא',
      description: 'ההתקנה מוחלת מהתיקייה שלצד התוכנה, בלי צורך באינטרנט. '
          'יש לוודא שאוצריא סגורה לפני התקנה.',
      children: [
        _stateCard(context),
        _whatsNewCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב ההתקנה ────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = otzaria;

    return SettingsCard(
      title: 'מצב ההתקנה',
      children: [
        InfoStatusRow(
          icon: FluentIcons.desktop_24_regular,
          title: 'מצב',
          kind: switch (c.status) {
            OtzariaModuleStatus.idle => StatusKind.unknown,
            OtzariaModuleStatus.checking => StatusKind.working,
            OtzariaModuleStatus.upToDate => StatusKind.ok,
            OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
            OtzariaModuleStatus.installing => StatusKind.working,
            OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
            OtzariaModuleStatus.error => StatusKind.error,
          },
          label: switch (c.status) {
            OtzariaModuleStatus.idle => 'טרם נבדק',
            OtzariaModuleStatus.checking => 'בודק...',
            OtzariaModuleStatus.upToDate => 'מעודכן',
            OtzariaModuleStatus.updateAvailable => 'מוכן להתקנה',
            OtzariaModuleStatus.installing => 'מתקין...',
            OtzariaModuleStatus.needsDownload => 'טרם הורדה גרסה',
            OtzariaModuleStatus.error => 'שגיאה',
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.tag_24_regular,
          title: 'גרסה מותקנת',
          subtitle: c.currentVersion ?? 'לא זוהתה התקנה',
          subtitleLtr: c.currentVersion != null,
          actions: [
            ActionButton.ghost(
              text: 'בחירת מיקום ידנית',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickInstallDir(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: 'גרסה בתיקייה המקומית',
          // כששתיהן בתיקייה מוצגות שתיהן — הפקד שמתחת קובע איזו תותקן.
          subtitle: c.hasChannelChoice
              ? '${c.stableVersion} (יציבה) · ${c.prereleaseVersion} (לא יציבה)'
              : c.latestVersion ?? 'אין — יש להריץ הורדה',
          subtitleLtr: c.latestVersion != null && !c.hasChannelChoice,
        ),
        // מוצג רק כשבתיקייה יושבות שתי גרסאות — כלומר כשה-pre-release חדש
        // מהיציבה. אחרת אין בחירה אמיתית, ואין טעם להציג פקד.
        if (c.hasChannelChoice)
          SettingsActionTile.segmentedTile<bool>(
            icon: FluentIcons.branch_24_regular,
            title: 'הגרסה שתותקן',
            subtitle: c.preferPrerelease
                ? 'הגרסה הלא-יציבה (${c.prereleaseVersion}) — חדשה יותר, '
                    'אך עלולה להכיל תקלות'
                : 'הגרסה היציבה (${c.stableVersion}) — מומלץ',
            options: const [
              SegmentOption(value: false, label: 'יציבה'),
              SegmentOption(value: true, label: 'לא יציבה'),
            ],
            currentValue: c.preferPrerelease,
            onChanged: _setChannel,
          ),
        SettingsActionTile.text(
          icon: FluentIcons.play_24_regular,
          title: 'תהליך אוצריא',
          subtitle: otzariaIsRunning
              ? 'פתוחה כרגע — עדכון מסד חסום עד לסגירתה'
              : 'סגורה',
        ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == OtzariaModuleStatus.installing)
          const InfoProgressRow(stage: 'מתקין את אוצריא...'),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'בדיקה מחדש',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _isBusy ? null : c.checkForUpdate,
            ),
            ActionButton.recommended(
              text: 'הפעלת אוצריא',
              icon: FluentIcons.play_24_regular,
              onPressed: c.canLaunch ? c.launch : null,
            ),
            ActionButton.neutral(
              text: 'התקנת העדכון',
              icon: FluentIcons.desktop_arrow_right_24_regular,
              isLoading: c.status == OtzariaModuleStatus.installing,
              onPressed: c.status == OtzariaModuleStatus.updateAvailable
                  ? () => _confirmInstall(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// שומר את הבחירה בהגדרות; `AppShell` מזליג אותה לקונטרולר, שמריץ בדיקה
  /// מחדש מהתיקייה המקומית. אין כאן רשת — שתי הגרסאות כבר בדיסק.
  void _setChannel(bool preferPrerelease) {
    settings.update(
      settings.settings.copyWith(preferAppPrerelease: preferPrerelease),
    );
  }

  Future<void> _pickInstallDir(BuildContext context) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחירת תיקיית ההתקנה של אוצריא',
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      UiSnack.showSuccess('נמצאה התקנת אוצריא — הגרסה עודכנה');
    } else {
      UiSnack.showError('לא נמצאה התקנת אוצריא בתיקייה שנבחרה');
    }
  }

  Future<void> _confirmInstall(BuildContext context) async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: 'התקנת תוכנת אוצריא',
      content: appInstallPrompt(otzaria),
      confirmText: 'התקן',
    );
    if (!approved) return;
    await otzaria.install();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess('אוצריא עודכנה לגרסה ${otzaria.currentVersion}');
    }
  }

  // ── מה התחדש ──────────────────────────────────────────────────────────────

  Widget _whatsNewCard(BuildContext context) {
    final notes = otzaria.latestReleaseNotes?.trim();

    return SettingsCard(
      title: 'מה התחדש בגרסה האחרונה',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: (notes == null || notes.isEmpty)
              ? Text(
                  'אין תיאור לגרסה הזו, או שעדיין לא הורדה גרסה.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : MarkdownBody(
                  data: notes,
                  styleSheet: _whatsNewStyleSheet(context),
                ),
        ),
      ],
    );
  }

  /// גיליון סגנון ל"מה התחדש" — מבוסס על עיצוב הערכה (`fromTheme`) עם
  /// דריסות לפי טוקני העיצוב של אוצריא (צבע/פונט כותרות כמו כותרת
  /// [SettingsCard], והזחת בלט/מסגרת ציטוט מותאמות ל-RTL).
  MarkdownStyleSheet _whatsNewStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headingStyle =
        TextStyle(color: cs.primary, fontWeight: FontWeight.bold);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      h1: theme.textTheme.headlineSmall?.merge(headingStyle),
      h2: theme.textTheme.titleLarge?.merge(headingStyle),
      h3: theme.textTheme.titleMedium?.merge(headingStyle),
      blockSpacing: AppTokens.spaceSM,
      listIndent: AppTokens.spaceLG,
      // ה-bullet הוא הילד הראשון ב-Row של הפריט; ב-RTL הוא מוצג מימין,
      // כך שהריווח לכיוון הטקסט צריך להיות בצד שמאל שלו, לא ימין.
      listBulletPadding: const EdgeInsets.only(left: AppTokens.spaceXS),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceXS,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border(right: BorderSide(color: cs.primary, width: 3)),
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
    );
  }

  // ── התיקייה שממנה מתקינים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = otzaria;

    return SettingsCard(
      title: 'התיקייה שממנה מתקינים',
      subtitle: 'קבועה, לצד קובץ ההרצה — ראו "עדכון ספרייה" להסבר המלא.',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית עדכוני התוכנה',
          path: c.mirrorDir,
          placeholder: '—',
        ),
        if (c.lastDownloadedAt != null)
          SettingsActionTile.text(
            icon: FluentIcons.history_24_regular,
            title: 'הורד לאחרונה',
            subtitle: c.lastDownloadedAt!.toLocal().toString().split('.').first,
          ),
      ],
    );
  }
}
