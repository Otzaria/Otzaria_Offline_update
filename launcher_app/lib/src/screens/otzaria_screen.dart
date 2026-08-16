import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/otzaria_module_controller.dart';
import '../services/byte_size.dart';
import '../services/native_file_dialogs.dart';
import '../services/timestamps.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// נוסח דיאלוג ההתקנה — משותף למסך הזה ולאריח בדף הבית, כדי שהאזהרה על
/// גרסה לא-יציבה תופיע בשניהם.
String appInstallPrompt(BuildContext context, OtzariaModuleController c) =>
    context.strings.appScreen.installPrompt(
      latestVersion: c.latestVersion,
      currentVersion: c.currentVersion,
      prereleaseNote: c.hasChannelChoice && c.preferPrerelease,
    );

/// מסך עדכון תוכנת אוצריא — מקביל במבנה ל-[LibraryScreen]: מצב, מה
/// התחדש בגרסה האחרונה, והתיקייה שממנה מותקנים.
class OtzariaScreen extends StatelessWidget {
  const OtzariaScreen({
    super.key,
    required this.otzaria,
    required this.settings,
    required this.otzariaIsRunning,
    this.onInstallAdopted,
    this.onInstallFullPackage,
  });

  final OtzariaModuleController otzaria;

  /// בחירת ערוץ הגרסה נשמרת בהגדרות, כדי שתישאר בין הפעלות.
  final SettingsController settings;
  final bool otzariaIsRunning;

  /// נקרא אחרי שהמשתמש הצביע ידנית על תיקיית ההתקנה — תיקיית התוספים
  /// נגזרת מהנתיב הזה, ולכן צריך לסרוק אותה מחדש.
  final Future<void> Function()? onInstallAdopted;

  /// התקנת החבילה המלאה. יושבת ב-`AppShell`, כי גם ההמלצה שבעלייה מגיעה
  /// אליה, והיא מרעננת אחריה גם את מודול הספרייה.
  final Future<void> Function()? onInstallFullPackage;

  /// **לא** תלוי בהורדה גלובלית: הורדה של רכיב אחר (למשל הספרייה) לא
  /// אמורה לחסום פעולות מקומיות כאן (בחירת מיקום, בדיקה מחדש).
  bool get _isBusy => otzaria.status == OtzariaModuleStatus.installing;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appScreen;

    return ScreenBody(
      title: t.title,
      children: [
        _stateCard(context),
        // רק כשהחבילה באמת על הכונן — כלומר רק למי שסימן אותה בהגדרות
        // והוריד אותה. לכל השאר המסך נשאר כפי שהיה.
        if (otzaria.fullPackage != null) _fullPackageCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב ההתקנה ────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = otzaria;
    final t = context.strings.appScreen;
    final common = context.strings.common;

    return SettingsCard(
      title: t.stateCardTitle,
      actions: [
        RecheckButton(onPressed: _isBusy ? null : c.checkForUpdate),
        ActionButton.recommended(
          text: t.launchButton,
          icon: FluentIcons.play_24_regular,
          onPressed: c.canLaunch ? c.launch : null,
        ),
        ActionButton.neutral(
          text: t.installUpdateButton,
          icon: FluentIcons.desktop_arrow_right_24_regular,
          isLoading: c.status == OtzariaModuleStatus.installing,
          onPressed: c.status == OtzariaModuleStatus.updateAvailable
              ? () => _confirmInstall(context)
              : null,
        ),
      ],
      children: [
        InfoStatusRow(
          icon: FluentIcons.desktop_24_regular,
          title: t.stateRowTitle,
          kind: switch (c.status) {
            OtzariaModuleStatus.idle => StatusKind.unknown,
            OtzariaModuleStatus.checking => StatusKind.working,
            OtzariaModuleStatus.upToDate => StatusKind.ok,
            OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
            OtzariaModuleStatus.installing => StatusKind.working,
            OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
            // ההתקנה תקינה ומעודכנת — רק המראה מפגרת אחריה.
            OtzariaModuleStatus.installedIsNewer => StatusKind.ok,
            OtzariaModuleStatus.error => StatusKind.error,
          },
          label: switch (c.status) {
            OtzariaModuleStatus.idle => common.notCheckedYet,
            OtzariaModuleStatus.checking => common.checking,
            OtzariaModuleStatus.upToDate => common.upToDate,
            OtzariaModuleStatus.updateAvailable => t.readyToInstall,
            OtzariaModuleStatus.installing => common.installing,
            OtzariaModuleStatus.needsDownload => t.nothingDownloadedYet,
            OtzariaModuleStatus.installedIsNewer => common.installedIsNewer,
            OtzariaModuleStatus.error => common.error,
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.tag_24_regular,
          title: t.installedVersion,
          subtitle: c.currentVersion ?? t.noInstallDetected,
          subtitleLtr: c.currentVersion != null,
          actions: [
            ActionButton.ghost(
              text: t.pickInstallDirButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickInstallDir(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.mirrorVersionTitle,
          // כששתיהן בתיקייה מוצגות שתיהן — הפקד שמתחת קובע איזו תותקן.
          subtitle: c.hasChannelChoice
              ? t.channelPair('${c.stableVersion}', '${c.prereleaseVersion}')
              : c.latestVersion ?? t.mirrorEmpty,
          subtitleLtr: c.latestVersion != null && !c.hasChannelChoice,
          actions: [
            ActionButton.ghost(
              text: t.whatsNewButton,
              icon: FluentIcons.history_24_regular,
              onPressed: () => _showWhatsNew(context),
            ),
          ],
        ),
        // מוצג רק כשבתיקייה יושבות שתי גרסאות — כלומר כשה-pre-release חדש
        // מהיציבה. אחרת אין בחירה אמיתית, ואין טעם להציג פקד.
        if (c.hasChannelChoice)
          SettingsActionTile.segmentedTile<bool>(
            icon: FluentIcons.branch_24_regular,
            title: t.channelTileTitle,
            subtitle: c.preferPrerelease
                ? t.prereleaseSubtitle('${c.prereleaseVersion}')
                : t.stableSubtitle('${c.stableVersion}'),
            options: [
              SegmentOption(value: false, label: t.channelStable),
              SegmentOption(value: true, label: t.channelPrerelease),
            ],
            currentValue: c.preferPrerelease,
            onChanged: _setChannel,
          ),
        // מוצג רק כשאוצריא פתוחה — אז זו אזהרה. "סגורה" היא שורה שאין בה מידע.
        if (otzariaIsRunning)
          SettingsActionTile.text(
            icon: FluentIcons.warning_24_regular,
            title: t.processTitle,
            subtitle: t.processRunning,
          ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == OtzariaModuleStatus.installing)
          InfoProgressRow(stage: t.installingProgress),
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
    final t = context.strings.appScreen;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      await onInstallAdopted?.call();
      UiSnack.showSuccess(t.installAdoptedSnack);
    } else {
      UiSnack.showError(t.installNotFoundSnack);
    }
  }

  Future<void> _confirmInstall(BuildContext context) async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: context.strings.home.appInstallDialogTitle,
      content: appInstallPrompt(context, otzaria),
      confirmText: context.strings.home.appInstallConfirm,
    );
    if (!approved) return;
    await otzaria.install();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.appInstalledSnack('${otzaria.currentVersion}'),
      );
    }
  }

  // ── מה התחדש ──────────────────────────────────────────────────────────────

  /// הערות הגרסה יושבות בדיאלוג ולא על המסך: הן ארוכות, וכשאין עדכון אין
  /// למי שנכנס למסך עניין בהן. הכפתור יושב בשורת הגרסה שבתיקייה המקומית.
  Future<void> _showWhatsNew(BuildContext context) {
    final notes = otzaria.latestReleaseNotes?.trim();
    final t = context.strings.appScreen;

    return showSingleActionDialog(
      context: context,
      title: t.whatsNewTitle,
      confirmText: context.strings.common.close,
      customContent: SizedBox(
        width: 600,
        // גובה **מרבי** ולא קבוע: בחלון בגובה המינימלי, ובעיקר בטקסט מוגדל,
        // 400 קבועים גלשו מהדיאלוג במקום להצטמצם אליו.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: (notes == null || notes.isEmpty)
              ? Text(t.whatsNewEmpty,
                  style: Theme.of(context).textTheme.bodyMedium)
              : SingleChildScrollView(
                  child: MarkdownBody(
                    data: notes,
                    styleSheet: _whatsNewStyleSheet(context),
                  ),
                ),
        ),
      ),
    );
  }

  /// גיליון סגנון ל"מה התחדש" — מבוסס על עיצוב הערכה (`fromTheme`) עם
  /// דריסות לפי טוקני העיצוב של אוצריא (צבע/פונט כותרות כמו כותרת
  /// [SettingsCard], והזחת בלט/מסגרת ציטוט לפי כיוון הכתיבה).
  MarkdownStyleSheet _whatsNewStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRtl = context.isRtl;
    final headingStyle =
        TextStyle(color: cs.primary, fontWeight: FontWeight.bold);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      h1: theme.textTheme.headlineSmall?.merge(headingStyle),
      h2: theme.textTheme.titleLarge?.merge(headingStyle),
      h3: theme.textTheme.titleMedium?.merge(headingStyle),
      blockSpacing: AppTokens.spaceSM,
      listIndent: AppTokens.spaceLG,
      // ה-bullet הוא הילד הראשון ב-Row של הפריט; הריווח צריך להיות בצד
      // שאליו זורם הטקסט — שמאל ב-RTL, ימין ב-LTR.
      listBulletPadding: EdgeInsets.only(
        left: isRtl ? AppTokens.spaceXS : 0,
        right: isRtl ? 0 : AppTokens.spaceXS,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceXS,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppTokens.borderRadiusAll,
        border: BorderDirectional(
          start: BorderSide(color: cs.primary, width: 3),
        ),
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
    final t = context.strings.appScreen;

    return SettingsCard(
      title: t.sourceCardTitle,
      hint: t.sourceCardHint,
      children: [
        // הנתיב עצמו אינו מוצג — הוא קבוע, ארוך, ומה שעושים איתו זה להעתיק.
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.sourceDirTitle,
          actions: [CopyPathButton(path: c.mirrorDir)],
        ),
        if (c.lastDownloadedAt != null)
          SettingsActionTile.text(
            icon: FluentIcons.history_24_regular,
            title: context.strings.common.lastDownloaded,
            subtitle: formatTimestamp(c.lastDownloadedAt!),
          ),
      ],
    );
  }

  // ── חבילת ההתקנה המלאה ────────────────────────────────────────────────────

  /// החבילה שכוללת גם את הספרייה. מוצגת רק כשהיא על הכונן, וכפתור ההתקנה
  /// פעיל רק כשאין במחשב אוצריא — במחשב שכבר יש בו אחת אין בה טעם, והיא
  /// הייתה דורסת התקנה עובדת ב-2GB מיותרים.
  Widget _fullPackageCard(BuildContext context) {
    final c = otzaria;
    final t = context.strings.appScreen;
    final full = c.fullPackage!;

    return SettingsCard(
      title: t.fullPackageCardTitle,
      hint: t.fullPackageHint,
      children: [
        InfoStatusRow(
          icon: FluentIcons.box_24_regular,
          title: t.fullPackageRowTitle,
          kind: c.fullPackageRecommended
              ? StatusKind.updateAvailable
              : StatusKind.ok,
          label: c.fullPackageRecommended
              ? t.fullPackageRecommended
              : t.fullPackageNotNeeded,
        ),
        // שם הקובץ אינו מעניין אף אחד; מה שכן — איזו גרסה יושבת שם וכמה היא.
        SettingsActionTile.text(
          icon: FluentIcons.document_24_regular,
          title: t.fullPackageVersionTitle,
          subtitle: t.fullPackageSize(
            '${c.stableVersion}',
            formatBytes(full.sizeBytes),
          ),
          actions: [
            ActionButton.recommended(
              text: t.fullPackageInstallButton,
              icon: FluentIcons.desktop_arrow_right_24_regular,
              isLoading: c.status == OtzariaModuleStatus.installing,
              onPressed:
                  c.fullPackageRecommended && onInstallFullPackage != null
                      ? () => onInstallFullPackage!()
                      : null,
            ),
          ],
        ),
      ],
    );
  }
}
