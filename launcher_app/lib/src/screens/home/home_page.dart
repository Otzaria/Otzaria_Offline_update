import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../services/byte_size.dart';
import '../../services/timestamps.dart';
import '../../shell/home_guidance.dart';
import '../../shell/shell_keys.dart';
import '../../shell/shell_navigator.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../reports/reports_page.dart' show showReportsDisclosure;
import 'home_view_model.dart';
import 'welcome_view.dart';

void _noop() {}
void _noopSection(ShellSection _) {}
Future<bool> _notClosed() async => false;

/// מה שהבית מפעיל. הכול מוזרק, כך שבדיקה וצילום בונים את הדף בלי סשן.
class HomeActions {
  const HomeActions({
    this.onInstallHere = _noop,
    this.onUpdateHere = _noop,
    this.onDownload = _noop,
    this.onDownloadSemantic = _noop,
    this.onRetryFailedDownloads = _noop,
    this.onLaunch = _noop,
    this.onRecheck = _noop,
    this.onOpenSection = _noopSection,
    this.onOpenSettings = _noop,
    this.onHelp = _noop,
    this.onToggleLanguage = _noop,
    this.onDismissReportsIntro = _noop,
    this.onDismissLegacyReports = _noop,
    this.onRestartElevated = _noop,
    this.onDismissElevation = _noop,
    this.onOpenLauncherUpdate = _noop,
    this.onShowProgress = _noop,
    this.onWhatsNew = _noop,
    this.onRecheckApp = _noop,
    this.onCloseOtzaria = _notClosed,
    this.onPickLibraryFolder = _noop,
    this.onRegisterThisComputer = _noop,
    this.onGrantSemanticConsent = _noop,
  });

  final VoidCallback onInstallHere;
  final VoidCallback onUpdateHere;
  final VoidCallback onDownload;

  /// "חיפוש חכם זמין להורדה" — מוריד בלי לשאול.
  final VoidCallback onDownloadSemantic;

  /// "נסה שוב" בהערה על קבצים שלא ירדו.
  final VoidCallback onRetryFailedDownloads;
  final VoidCallback onLaunch;
  final VoidCallback onRecheck;
  final ValueChanged<ShellSection> onOpenSection;
  final VoidCallback onOpenSettings;
  final VoidCallback onHelp;
  final VoidCallback onToggleLanguage;
  final VoidCallback onDismissReportsIntro;
  final VoidCallback onDismissLegacyReports;
  final VoidCallback onRestartElevated;
  final VoidCallback onDismissElevation;

  /// "עדכון זמין" בשורת המצב — דף "עדכון הכלי הזה".
  final VoidCallback onOpenLauncherUpdate;

  /// "הצג התקדמות" בגיבור של עדכון ספרייה שרץ מחוץ למסך משימה.
  final VoidCallback onShowProgress;

  /// "מה חדש?" — חלון מעל הבית.
  final VoidCallback onWhatsNew;

  /// "בדוק שוב" כשהבדיקה המקומית של התוכנה נכשלה — מהכונן בלבד, בלי
  /// `checkAll`, שעלול להתקין לבד.
  final VoidCallback onRecheckApp;

  /// "סגירת אוצריא" בפס, כשאין מה להתקין. מחזירה אם היא אכן נסגרה.
  final Future<bool> Function() onCloseOtzaria;

  /// הודעות הספרייה: בחירת מיקום, רישום המחשב הזה והסכמה לחיפוש חכם.
  final VoidCallback onPickLibraryFolder;
  final VoidCallback onRegisterThisComputer;
  final VoidCallback onGrantSemanticConsent;
}

/// דף הבית: הודעות, הגיבור ("מה לעשות עכשיו"), אריחים ושורת תחתית. בכונן
/// ריק במחשב בלי אוצריא — מסך הפתיחה במקומם.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.model,
    this.actions = const HomeActions(),
    this.taskProgress,
    this.launcherProgress,
  });

  final HomeViewModel model;
  final HomeActions actions;

  /// מד ההתקדמות של המשימה שרצה — `ListenableBuilder` על ה-progress של
  /// הקונטרולרים, שהמסגרת בונה.
  final Widget? taskProgress;

  /// אחוז ההורדה של הכלי עצמו, באותו אופן.
  final Widget? launcherProgress;

  /// מתחת לרוחב הזה הגיבור מוותר על הסמל ומצמצם ריפוד (`@container` במוקאפ).
  static const double narrowWidth = 800;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth <= narrowWidth;
        if (model.guidance.primary == GuidancePrimary.welcome) {
          return WelcomeView(
            key: ShellKeys.welcome,
            offline: model.readOnly || model.online == false,
            narrow: narrow,
            busy: model.isCheckingOnline,
            notices: [
              ..._driveNotices(context),
              ..._notices(context),
              ..._libraryNotices(context),
              if (foundNothingText(context, model) case final text?)
                NoticeBanner(
                  key: ShellKeys.heroFoundNothing,
                  leading: const IconTile(
                    icon: FluentIcons.checkmark_24_regular,
                    tone: IconTileTone.quiet,
                  ),
                  title: text,
                ),
            ],
            links: _welcomeLinks(context),
            onDownload: actions.onDownload,
            onHelp: actions.onHelp,
            onToggleLanguage: actions.onToggleLanguage,
          );
        }
        const padding = LayoutConstraints.pagePadding;
        final below = [
          ..._libraryNotices(context),
          if (model.showsNewPlugins) _newPluginsBanner(context),
        ];
        final list = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  LayoutConstraints.panelContentMaxWidth + padding.horizontal,
            ),
            child: ListView(
              padding: padding,
              children: [
                ..._driveNotices(context),
                ..._notices(context),
                _Hero(
                  model: model,
                  actions: actions,
                  narrow: narrow,
                  progress: taskProgress,
                ),
                if (below.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...below,
                  // הפס נושא מרווח תחתון של 12; המקטע שאחריו מתחיל ב-28.
                  const SizedBox(height: 16),
                  SectionLabel(context.strings.guide.tilesLabel, first: true),
                ] else
                  SectionLabel(context.strings.guide.tilesLabel),
                _Tiles(model: model, onOpen: actions.onOpenSection),
                if (model.hasContact)
                  _ContactLine(
                    name: model.contactName,
                    phone: model.contactPhone,
                  ),
              ],
            ),
          ),
        );
        return Column(
          children: [
            Expanded(child: list),
            _StatusBar(
              model: model,
              actions: actions,
              launcherProgress: launcherProgress,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _driveNotices(BuildContext context) {
    if (!model.readOnly) return const [];
    final t = context.strings.readOnlyDrive;
    final full = model.driveFull;
    return [
      NoticeBanner(
        key: full ? ShellKeys.driveFullNotice : ShellKeys.readOnlyNotice,
        leading: IconTile(
          icon: full
              ? FluentIcons.storage_24_regular
              : FluentIcons.lock_closed_24_regular,
          tone: IconTileTone.error,
        ),
        title: full ? t.bannerTitleDriveFull : t.bannerTitle,
        body: full ? t.bannerSubtitleDriveFull : t.bannerSubtitle,
      ),
    ];
  }

  /// "עדכון כאן" עצמו מבקש לסגור את אוצריא, ולכן בפס אין כפתור שמתחרה בו.
  List<Widget> _notices(BuildContext context) {
    final g = context.strings.guide;
    final elevation = context.strings.elevation;
    return [
      if (model.reportsIntro) _reportsIntro(context),
      if (model.legacyReportsNotice) _legacyReports(context),
      if (model.guidance.showOtzariaOpenBanner)
        NoticeBanner(
          key: ShellKeys.otzariaOpenBanner,
          kind: NoticeKind.banner,
          leading: const IconTile(child: OtzariaLogo()),
          title: g.otzariaOpenTitle,
          body: !model.guidance.otzariaOpenBlocksUpdate
              ? g.otzariaOpenIdleBody
              : model.autoInstallSkipped
                  ? '${g.autoInstallSkippedLead}${g.otzariaOpenBody}'
                  : g.otzariaOpenBody,
          actions: [
            if (!model.guidance.otzariaOpenBlocksUpdate)
              CloseOtzariaButton(onClose: actions.onCloseOtzaria),
          ],
        ),
      if (model.offersElevation)
        NoticeBanner(
          key: ShellKeys.elevationBanner,
          kind: NoticeKind.banner,
          leading:
              const IconTile(icon: FluentIcons.shield_checkmark_24_regular),
          title: elevation.bannerTitle,
          body: elevation.bannerContent,
          actions: [
            ActionButton.ghost(
              text: elevation.bannerDismiss,
              onPressed: actions.onDismissElevation,
            ),
            ActionButton.neutral(
              text: elevation.bannerConfirm,
              onPressed: actions.onRestartElevated,
            ),
          ],
        ),
    ];
  }

  /// מתחת לגיבור, כדי שבחלון נמוך הפעולה הראשית לא תיגלל החוצה. "לא נמצאה"
  /// ו"מחשב אחר" — בגיבור עצמו כשהוא "צריך בדיקה" עליהן.
  List<Widget> _libraryNotices(BuildContext context) {
    final m = model;
    final g = context.strings.guide;
    final t = context.strings.pages;
    final blocked = m.checkBlocked;
    final inHero = _libraryInHero(m);
    return [
      if (m.libraryDownloadNotes.isNotEmpty)
        NoticeBanner(
          leading: const IconTile(icon: FluentIcons.info_24_regular),
          title: context.strings.libraryScreen.downloadNoteTitle,
          body: m.libraryDownloadNotes.join('\n'),
        ),
      if (m.libraryNotFound && !inHero)
        NoticeBanner(
          key: ShellKeys.libraryNotFoundNotice,
          leading: const IconTile(icon: FluentIcons.library_24_regular),
          title: t.libNotFoundTitle,
          body: t.libNotFoundBody,
          actions: [
            ActionButton.neutral(
              text: t.libPickFolderButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: blocked ? null : actions.onPickLibraryFolder,
            ),
          ],
        ),
      if (m.libraryElsewhereFrom case final from? when !inHero)
        NoticeBanner(
          key: ShellKeys.libraryElsewhereNotice,
          leading: const IconTile(
            icon: FluentIcons.person_24_regular,
            tone: IconTileTone.quiet,
          ),
          title: context.strings.libraryScreen.personalOtherMachineTitle,
          body: _elsewhereBody(context, m, from),
          actions: _elsewhereActions(context, m, actions),
        ),
      if (m.semanticConsent)
        NoticeBanner(
          key: ShellKeys.semanticConsentNotice,
          leading: const IconTile(icon: FluentIcons.sparkle_24_regular),
          title: t.libSemanticSection,
          body: g.semanticConsentBody,
          actions: [
            ActionButton.neutral(
              text: t.libSemanticGrant,
              onPressed: blocked ? null : actions.onGrantSemanticConsent,
            ),
            ActionButton.ghost(
              key: ShellKeys.semanticConsentWhatIsSent,
              text: t.repWhatIsSent,
              onPressed: () => showReportsDisclosure(
                context,
                reports: false,
                search: true,
              ),
            ),
          ],
        ),
    ];
  }

  /// מה עוד יש בכונן שאין בו אוצריא — במסך הפתיחה אין אריחים.
  List<({String label, VoidCallback onTap})> _welcomeLinks(
    BuildContext context,
  ) {
    final g = context.strings.guide;
    return [
      if (model.customApps > 0)
        (
          label: g.tileCustomApps,
          onTap: () => actions.onOpenSection(ShellSection.customApps),
        ),
      if (model.showsReportsTile)
        (
          label: g.tileReports,
          onTap: () => actions.onOpenSection(ShellSection.reports),
        ),
    ];
  }

  Widget _legacyReports(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.legacyReportsNotice,
      leading: const IconTile(
        icon: FluentIcons.bug_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.legacyReportsDialogTitle,
      body: t.legacyReportsDialogContent,
      actions: [
        ActionButton.neutral(
          text: t.introDialogConfirm,
          onPressed: actions.onDismissLegacyReports,
        ),
      ],
    );
  }

  Widget _reportsIntro(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.reportsIntroNotice,
      leading: const IconTile(
        icon: FluentIcons.bug_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.introDialogTitle,
      // הנוסח נכתב לדו-שיח; בהודעה הפסקאות מתחברות לאחת.
      body: (!model.readOnly
              ? t.introDialogContent
              : model.driveFull
                  ? t.introDialogContentReadOnlyDriveFull
                  : t.introDialogContentReadOnly)
          .replaceAll('\n\n', ' '),
      actions: [
        ActionButton.neutral(
          text: t.introDialogConfirm,
          onPressed: actions.onDismissReportsIntro,
        ),
      ],
    );
  }

  Widget _newPluginsBanner(BuildContext context) {
    final g = context.strings.guide;
    final names = model.newPlugins;
    const shown = 3;
    return NoticeBanner(
      key: ShellKeys.newPluginsBanner,
      kind: NoticeKind.banner,
      leading: const IconTile(icon: FluentIcons.puzzle_piece_24_regular),
      title: g.newPluginsTitle(names.length),
      body: g.newPluginsBody(
        names.take(shown).toList(),
        names.length > shown ? names.length - shown : 0,
      ),
      actions: [
        ActionButton.ghost(
          text: g.toPluginsButton,
          onPressed: () => actions.onOpenSection(ShellSection.plugins),
        ),
      ],
    );
  }
}

/// הגיבור במצב "צריך בדיקה" על ספרייה שלא נמצאה או שהכונן הוכן למחשב אחר —
/// והוא שמציע את הפעולה, במקום ההודעה.
bool _libraryInHero(HomeViewModel m) =>
    m.guidance.primary == GuidancePrimary.attention &&
    m.guidance.attentionItem == GuidanceItem.library &&
    (m.libraryNotFound || m.libraryElsewhereFrom != null);

String _elsewhereBody(BuildContext context, HomeViewModel m, String from) {
  final body = context.strings.libraryScreen.personalOtherMachineSubtitle(
    from.isEmpty ? context.strings.common.unknownValue : from,
  );
  // כמו בדף הספרייה: בכונן מוגן אין לאן לרשום.
  return m.readOnly
      ? '$body ${context.strings.pages.libPersonalReadOnly}'
      : body;
}

List<Widget> _elsewhereActions(
  BuildContext context,
  HomeViewModel m,
  HomeActions actions,
) {
  final s = context.strings.libraryScreen;
  return [
    ActionButton.neutral(
      text: s.personalVersionButton,
      onPressed:
          m.readOnly || m.checkBlocked ? null : actions.onRegisterThisComputer,
    ),
    ActionButton.ghost(
      text: s.personalOtherMachineSettingsButton,
      onPressed: actions.onOpenSettings,
    ),
  ];
}

/// "הורדה" שלא מצאה מה להביא, כהערה — ראו `AppSession.foundNothing`.
String? foundNothingText(BuildContext context, HomeViewModel m) {
  final g = context.strings.guide;
  return switch ((m.foundNothing, m.onlineCheckedAt)) {
    (null, _) => null,
    (FoundNothing.rechecked, final at?) =>
      g.recheckNothingNote(formatClock(at)),
    (FoundNothing.rechecked, null) => g.recheckNothingTitle,
    (FoundNothing.earlierCheck, final at?) => g.nothingNewNote(formatClock(at)),
    (FoundNothing.earlierCheck, null) => g.nothingNewTitle,
  };
}

Widget _logo(double size) => Image.asset(
      'assets/images/otzaria_logo.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    );

// ── הגיבור ────────────────────────────────────────────────────────────────────

/// שורה ברשימת הגיבור: מה יירד, יותקן או עוד מחכה. [size] — "עד X" כשיש חסם.
typedef _Item = ({
  Widget icon,
  String title,
  String? subtitle,
  String? size,
  VoidCallback? onTap,
});

_Item _item(
  Widget icon,
  String title, {
  String? subtitle,
  String? size,
  VoidCallback? onTap,
}) =>
    (icon: icon, title: title, subtitle: subtitle, size: size, onTap: onTap);

/// הערה קטנה בגיבור (`.hero-note`), עם קישור אופציונלי בסופה.
class _Note {
  const _Note(this.icon, this.text, {this.link, this.onLink, this.key});

  final Key? key;
  final IconData icon;
  final String text;
  final String? link;
  final VoidCallback? onLink;
}

class _HeroSpec {
  const _HeroSpec({
    required this.title,
    this.body,
    this.items = const [],
    this.total,
    this.free,
    this.actions = const [],
    this.notes = const [],
    this.extra = const [],
    this.eyebrow = true,
  });

  final String title;
  final String? body;

  /// מתחת לגוף — למשל השגיאה של בדיקת התוכנה.
  final List<Widget> extra;
  final List<_Item> items;

  /// שורת הסיכום שבתחתית הרשימה.
  final String? total;
  final String? free;
  final List<Widget> actions;
  final List<_Note> notes;

  /// "המחשב הזה · אוצריא X". במחשב לא מחובר שבכונן שלו אין חדש — בלעדיה.
  final bool eyebrow;
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.model,
    required this.actions,
    required this.narrow,
    this.progress,
  });

  final HomeViewModel model;
  final HomeActions actions;
  final bool narrow;
  final Widget? progress;

  HomeGuidance get _g => model.guidance;

  @override
  Widget build(BuildContext context) {
    final pad = narrow
        ? const EdgeInsets.all(24)
        : const EdgeInsets.symmetric(horizontal: 32, vertical: 28);
    final spec = _spec(context);

    return Container(
      key: ShellKeys.hero,
      padding: pad,
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        children: [
          Expanded(child: _content(context, spec)),
          // הרשימה צריכה את הרוחב.
          if (!narrow && spec.items.isEmpty) ...[
            const SizedBox(width: 24),
            _emblem(),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _emblem() => switch (_g.primary) {
        GuidancePrimary.upToDate ||
        GuidancePrimary.newerHereThanDrive =>
          const _Emblem(icon: FluentIcons.checkmark_24_regular, done: true),
        GuidancePrimary.downloadToDrive => const _Emblem(
            icon: FluentIcons.usb_stick_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.installHere => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.attention ||
        GuidancePrimary.checkFailed =>
          const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.warning_16_regular,
          ),
        GuidancePrimary.taskInProgress
            when model.task == HomeTask.downloading =>
          const _Emblem(
            icon: FluentIcons.usb_stick_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.checking => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.search_16_regular,
          ),
        _ => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.arrow_sync_16_regular,
          ),
      };

  Widget _content(BuildContext context, _HeroSpec spec) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spec.eyebrow) ...[
          _eyebrow(context),
          const SizedBox(height: 10),
        ],
        Text(
          spec.title,
          style: AppTextStyles.heroTitle.copyWith(color: cs.onSurface),
        ),
        if (spec.body != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(
              spec.body!,
              style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
        if (spec.extra.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...spec.extra,
        ],
        if (spec.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ItemList(items: spec.items, total: spec.total, free: spec.free),
        ],
        if (progress != null && _g.primary == GuidancePrimary.taskInProgress)
          progress!,
        if (_g.primary == GuidancePrimary.checking) ...[
          const SizedBox(height: 22),
          const SizedBox(
            key: ShellKeys.heroChecking,
            width: 220,
            child: AppProgressBar(),
          ),
        ],
        if (spec.actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: spec.actions,
          ),
        ],
        for (final note in spec.notes) ...[
          const SizedBox(height: 14),
          _HeroNote(note, key: note.key),
        ],
      ],
    );
  }

  Widget _eyebrow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final style = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);
    final installed = model.installedVersion;
    return Wrap(
      key: ShellKeys.eyebrow,
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(FluentIcons.desktop_16_regular, size: 16, color: cs.primary),
        Text(g.eyebrowThisComputer, style: style),
        Text('·', style: style.copyWith(color: cs.outline)),
        Text(
          installed == null
              ? g.eyebrowNotInstalled
              : g.eyebrowOtzaria(
                  displayVersion(
                    installed,
                    other: model.onlineAppVersion ?? model.driveAppVersion,
                  ),
                ),
          style: style,
        ),
      ],
    );
  }

  _HeroSpec _spec(BuildContext context) {
    final g = context.strings.guide;
    final m = model;

    Widget primary(
      String text,
      VoidCallback? onPressed, {
      IconData? icon,
      bool spinning = false,
    }) =>
        ActionButton.recommended(
          key: ShellKeys.heroPrimary,
          text: text,
          icon: icon,
          size: ActionButtonSize.lg,
          autofocus: true,
          spinning: spinning,
          onPressed: onPressed,
        );
    Widget secondary(String text, VoidCallback? onPressed, {IconData? icon}) =>
        ActionButton.ghost(
          key: ShellKeys.heroSecondary,
          text: text,
          icon: icon,
          spinning: icon != null && m.checkingNow,
          onPressed: onPressed,
        );

    final busy = m.isCheckingOnline;
    final offline = m.online == false;
    final launch =
        primary(g.launchButton, m.canLaunch ? actions.onLaunch : null);
    final recheck = m.checkingNow || m.checkBlocked ? null : actions.onRecheck;
    // כשהגיבור מציע עדכון — אוצריא המותקנת עדיין נפתחת מכאן.
    final launchToo = [
      if (m.installedVersion != null &&
          m.canLaunch &&
          !_g.showOtzariaOpenBanner)
        ActionButton.ghost(
          key: ShellKeys.heroLaunch,
          text: g.launchButton,
          onPressed: actions.onLaunch,
        ),
    ];
    final whatsNew = [
      if (m.whatsNew)
        ActionButton.ghost(
          key: ShellKeys.heroWhatsNew,
          text: g.whatsNewButton,
          onPressed: actions.onWhatsNew,
        ),
    ];
    // במחשב לא מחובר "בדוק עכשיו" נשאר בשורת המצב בלבד.
    final quietActions = [
      launch,
      ...whatsNew,
      if (!offline)
        secondary(
          g.recheckButton,
          recheck,
          icon: FluentIcons.arrow_sync_24_regular,
        ),
    ];

    final blocked = busy || m.checkBlocked;
    _Note failedNote({required bool retry}) => _Note(
          key: ShellKeys.heroFailedDownloads,
          FluentIcons.warning_16_regular,
          g.failedDownloadsNote(m.failedDownloads!),
          link: retry ? context.strings.common.retry : null,
          onLink: retry && !blocked ? actions.onRetryFailedDownloads : null,
        );
    // הערות של בית שאין בו הורדה: חיפוש חכם שלא נחשב עדכון, וקבצים שנכשלו.
    final downloadNotes = [
      if (m.semanticOffer)
        _Note(
          key: ShellKeys.heroSemanticOffer,
          FluentIcons.sparkle_16_regular,
          g.semanticOfferNote,
          link: g.semanticOfferLink,
          onLink: blocked ? null : actions.onDownloadSemantic,
        ),
      if (m.failedDownloads != null) failedNote(retry: true),
    ];
    final recheckNote = [
      if (foundNothingText(context, m) case final text?)
        _Note(
          key: ShellKeys.heroFoundNothing,
          FluentIcons.checkmark_16_regular,
          text,
        ),
    ];
    String? installed() =>
        m.installedVersion == null ? null : displayVersion(m.installedVersion!);
    // שגיאת התוכנה כשהגיבור על משהו אחר, האשף וגרסה שממתינה בערוץ.
    final pickFolder = m.appErrorPicksFolder;
    final appNotes = [
      if (m.appError case final error?)
        _Note(
          key: ShellKeys.heroAppErrorNote,
          FluentIcons.warning_16_regular,
          error.split('\n').first,
          link: pickFolder
              ? context.strings.pages.appAdvancedPageTitle
              : g.recheckButton,
          onLink: pickFolder
              ? () => actions.onOpenSection(ShellSection.otzaria)
              : m.checkBlocked
                  ? null
                  : actions.onRecheckApp,
        ),
      if (m.appSetupNotice case final notice?)
        _Note(FluentIcons.info_16_regular, notice),
      if (m.appAwaitsNewerStable case final stable?)
        _Note(
          key: ShellKeys.appAwaitsNewer,
          FluentIcons.info_16_regular,
          context.strings.pages.appAwaitsNewer(stable: stable),
        ),
    ];
    final libraryNotes = _libraryNotes(context, failedShown: true);
    // ב"צריך בדיקה" אין הערת "נסה שוב" — הקבצים החסרים נאמרים בכל מקרה.
    final attentionNotes = _libraryNotes(context, failedShown: false);

    switch (_g.primary) {
      case GuidancePrimary.checking || GuidancePrimary.welcome:
        return _HeroSpec(
          title: g.checkingTitle,
          body: g.checkingBody,
          // הבדיקה אינה סיבה לחכות עם אוצריא שכבר מותקנת.
          actions: [if (m.installedVersion != null) launch],
          notes: recheckNote,
        );
      case GuidancePrimary.installHere:
        return _HeroSpec(
          title: g.installHereTitle,
          body: g.installHereBody,
          items: _hereItems(context),
          actions: [primary(g.installHereButton, actions.onInstallHere)],
          notes: [
            ...recheckNote,
            ...appNotes,
            ...libraryNotes,
            ...downloadNotes,
          ],
        );
      case GuidancePrimary.updateHere:
        return _HeroSpec(
          title: g.updateHereTitle,
          body: g.updateHereBody,
          items: _hereItems(context),
          actions: [
            primary(g.updateHereButton, actions.onUpdateHere),
            ...whatsNew,
            ...launchToo,
          ],
          notes: [
            ...recheckNote,
            ...appNotes,
            ...libraryNotes,
            ...downloadNotes,
          ],
        );
      case GuidancePrimary.downloadToDrive:
        final hereToo = _g.secondary == GuidanceSecondary.updateHereToo;
        final items = _downloadItems(context);
        return _HeroSpec(
          title: g.downloadTitle,
          body: g.downloadBody,
          items: items,
          total: _total(context),
          free: m.driveFreeBytes == null
              ? null
              : g.driveFree(formatBytes(m.driveFreeBytes!)),
          actions: [
            // בזמן הבדיקה ברשת: מחוון בכפתור, כדי שלא ייראה כבוי בלי סיבה.
            primary(
              g.downloadButton,
              busy ? null : actions.onDownload,
              icon: busy
                  ? FluentIcons.arrow_sync_24_regular
                  : FluentIcons.arrow_download_24_regular,
              spinning: busy,
            ),
            // שתי פעולות אמיתיות — השנייה ניטרלית, לא קישור.
            if (hereToo)
              ActionButton.neutral(
                key: ShellKeys.heroSecondary,
                text: m.installedVersion == null
                    ? g.installHereButton
                    : g.updateHereButton,
                size: ActionButtonSize.lg,
                onPressed: m.installedVersion == null
                    ? actions.onInstallHere
                    : actions.onUpdateHere,
              ),
            ...launchToo,
          ],
          notes: [
            if (m.libraryDownloadFailed)
              _Note(FluentIcons.info_16_regular, g.libraryRetryNote),
            // הכפתור הראשי כבר מנסה אותם שוב.
            if (m.failedDownloads != null) failedNote(retry: false),
            ...recheckNote,
            ...appNotes,
            ...libraryNotes,
            ..._syncOffNotes(context),
            if (m.personalMode && m.personalMachines > 0)
              _Note(
                key: ShellKeys.personalDownloadNote,
                FluentIcons.person_16_regular,
                context.strings.libraryScreen.personalDownloadNote(
                  m.personalMachines,
                ),
                link: context.strings.libraryScreen.personalChange,
                onLink: actions.onOpenSettings,
              ),
            if (hereToo)
              _Note(
                FluentIcons.info_16_regular,
                g.updateHereTooNote(
                  _g.hereItems.contains(GuidanceItem.app) &&
                          m.driveAppVersion != null
                      ? displayVersion(
                          m.driveAppVersion!,
                          other: m.onlineAppVersion,
                        )
                      : null,
                ),
              ),
          ],
        );
      case GuidancePrimary.newerHereThanDrive:
        return _HeroSpec(
          title: switch (m.appAwaitsNewerStable) {
            final stable? => g.newerChannelTitle(stable: stable),
            null => g.newerTitle,
          },
          // הכונן מחזיק שני ערוצים; במצב הזה משווים לערוץ שנבחר בלבד.
          body: switch (m.appAwaitsNewerStable) {
            final stable? => context.strings.pages.appAwaitsNewer(
                stable: stable,
              ),
            null => g.newerBody(
                displayVersion(
                  m.installedVersion ?? '',
                  other: m.driveAppVersion,
                ),
                displayVersion(
                  m.driveAppVersion ?? '',
                  other: m.installedVersion,
                ),
              ),
          },
          actions: quietActions,
          notes: [
            ...recheckNote,
            if (m.online != true)
              _Note(FluentIcons.usb_stick_20_regular, g.newerNote),
            ..._quietNotes(context, offline: false),
            ...libraryNotes,
            ...downloadNotes,
          ],
        );
      case GuidancePrimary.upToDate:
        final others = _otherItems(context);
        // "הכול מעודכן" רק כשכל רכיב שנבחר נבדק ברשת; אחרת — מה שידוע.
        final proven = _g.onlineProven;
        final foundNothingTitle = proven && others.isEmpty;
        return _HeroSpec(
          title: others.isNotEmpty
              ? g.othersPendingTitle
              : !proven
                  ? g.driveInstalledTitle
                  : switch (m.foundNothing) {
                      FoundNothing.rechecked => g.recheckNothingTitle,
                      FoundNothing.earlierCheck => g.nothingNewTitle,
                      null => g.upToDateTitle,
                    },
          body: !proven
              ? g.driveInstalledBody(installed())
              : switch ((
                  foundNothingTitle ? m.foundNothing : null,
                  m.onlineCheckedAt
                )) {
                  (FoundNothing.rechecked, final at?) => g.recheckNothingBody(
                      formatClock(at),
                      upToDate: !m.semanticOffer,
                    ),
                  (FoundNothing.earlierCheck, final at?) => g.nothingNewBody(
                      formatClock(at),
                      upToDate: !m.semanticOffer,
                    ),
                  _ => g.upToDateBody(installed()),
                },
          items: others,
          eyebrow: !offline,
          actions: quietActions,
          notes: [
            if (!foundNothingTitle) ...recheckNote,
            ..._quietNotes(context, offline: true),
            ...libraryNotes,
            ...downloadNotes,
          ],
        );
      case GuidancePrimary.checkFailed:
        bool failed(GuidanceItem i) => _g.uncheckedItems.contains(i);
        bool checked(GuidanceItem i) => _g.checkedItems.contains(i);
        return _HeroSpec(
          title: g.checkFailedTitle,
          body: g.checkFailedBody(
            appFailed: failed(GuidanceItem.app),
            libraryFailed: failed(GuidanceItem.library),
            pluginsFailed: failed(GuidanceItem.plugins),
            appChecked: checked(GuidanceItem.app),
            libraryChecked: checked(GuidanceItem.library),
            pluginsChecked: checked(GuidanceItem.plugins),
          ),
          actions: [
            launch,
            secondary(
              context.strings.common.retry,
              recheck,
              icon: FluentIcons.arrow_sync_24_regular,
            ),
          ],
          notes: [...recheckNote, ...libraryNotes, ...downloadNotes],
        );
      case GuidancePrimary.attention when _g.attentionItem == GuidanceItem.app:
        // הבדיקה של התוכנה בלבד: "בדוק עכשיו" מריץ גם התקנה אוטומטית.
        return _HeroSpec(
          title: g.attentionAppTitle,
          extra: [
            if (m.appError case final error?)
              Material(
                type: MaterialType.transparency,
                child:
                    InfoErrorRow(key: ShellKeys.heroAppError, message: error),
              ),
          ],
          actions: [
            primary(
              g.recheckButton,
              m.checkBlocked ? null : actions.onRecheckApp,
              icon: FluentIcons.arrow_sync_24_regular,
            ),
            if (pickFolder)
              ActionButton.ghost(
                key: ShellKeys.heroAppAdvanced,
                text: context.strings.pages.appAdvancedPageTitle,
                onPressed: () => actions.onOpenSection(ShellSection.otzaria),
              ),
            ...launchToo,
          ],
          notes: [...recheckNote, ...attentionNotes],
        );
      case GuidancePrimary.attention:
        final t = context.strings.pages;
        final s = context.strings.libraryScreen;
        final toLibrary = ActionButton.ghost(
          key: ShellKeys.heroSecondary,
          text: g.attentionLibraryButton,
          onPressed: () => actions.onOpenSection(ShellSection.library),
        );
        if (m.libraryNotFound) {
          return _HeroSpec(
            title: t.libNotFoundTitle,
            body: t.libNotFoundBody,
            actions: [
              primary(
                t.libPickFolderButton,
                m.checkBlocked ? null : actions.onPickLibraryFolder,
                icon: FluentIcons.folder_open_24_regular,
              ),
              toLibrary,
            ],
            notes: [...recheckNote, ...attentionNotes],
          );
        }
        if (m.libraryElsewhereFrom case final from?) {
          return _HeroSpec(
            title: s.personalOtherMachineTitle,
            body: _elsewhereBody(context, m, from),
            actions: [
              primary(
                s.personalVersionButton,
                m.readOnly || m.checkBlocked
                    ? null
                    : actions.onRegisterThisComputer,
              ),
              ActionButton.ghost(
                key: ShellKeys.heroSecondary,
                text: s.personalOtherMachineSettingsButton,
                onPressed: actions.onOpenSettings,
              ),
            ],
            notes: [...recheckNote, ...attentionNotes],
          );
        }
        return _HeroSpec(
          title: g.attentionLibraryTitle,
          body: g.attentionBody,
          actions: [
            primary(
              g.attentionLibraryButton,
              () => actions.onOpenSection(ShellSection.library),
            ),
          ],
          notes: [...recheckNote, ...attentionNotes],
        );
      case GuidancePrimary.taskInProgress:
        Widget showProgress() => ActionButton.recommended(
              key: ShellKeys.heroShowProgress,
              text: context.strings.task.showProgress,
              onPressed: actions.onShowProgress,
            );
        return switch (m.task) {
          // ההורדה מוצגת במסך המשימה, שמכסה את הבית; כאן רק למקרה ביניים.
          HomeTask.downloading => _HeroSpec(
              title: g.taskDownloadingTitle,
              body: g.taskDownloadingBody,
              items: _downloadItems(context),
            ),
          // ההתקדמות ו"הפסק להמתין" בגיבור עצמו — `HomeTaskProgress`.
          HomeTask.installingApp => _HeroSpec(
              title: g.taskInstallingAppTitle,
            ),
          HomeTask.updatingLibrary => _HeroSpec(
              title: g.taskUpdatingLibraryTitle,
              actions: [showProgress()],
            ),
          HomeTask.restartingElevated => _HeroSpec(
              title: g.taskRestartingElevatedTitle,
            ),
          final task => _HeroSpec(
              title: switch (task) {
                HomeTask.syncingPlugins => g.taskSyncingPluginsTitle,
                HomeTask.updatingPlugins => g.taskUpdatingPluginsTitle,
                HomeTask.exportingStore => g.taskExportingStoreTitle,
                HomeTask.downloadingCustomApps =>
                  g.taskDownloadingCustomAppsTitle,
                HomeTask.customApps => g.taskCustomAppsTitle,
                HomeTask.installingLauncher => g.taskInstallingLauncherTitle,
                _ => g.taskBusyTitle,
              },
              body: task == HomeTask.other ? g.taskBusyBody : g.taskNamedBody,
              actions: [
                if (task.section case final section?)
                  ActionButton.recommended(
                    key: ShellKeys.heroShowProgress,
                    text: context.strings.task.showProgress,
                    onPressed: () => actions.onOpenSection(section),
                  ),
              ],
            ),
        };
    }
  }

  /// קבצים נלווים שחסרים בכונן — אין כאן מה ללחוץ, ולכן הערה מתחת לפעולה.
  /// [failedShown] — הגיבור כבר אומר אותם ב"נסה שוב" של קבצים שלא ירדו.
  List<_Note> _libraryNotes(BuildContext context, {required bool failedShown}) {
    final g = context.strings.guide;
    final m = model;
    final prepared = [
      if (m.personalPreparedHere)
        _Note(
          key: ShellKeys.personalPreparedHere,
          FluentIcons.person_16_regular,
          context.strings.libraryScreen.personalPreparedHere,
        ),
      if (m.personalPendingNeedsClick)
        _Note(
          key: ShellKeys.personalPendingNote,
          FluentIcons.person_16_regular,
          context.strings.libraryScreen.personalPendingRegisterNote,
          link: context.strings.libraryScreen.personalVersionButton,
          onLink: m.readOnly || m.checkBlocked
              ? null
              : actions.onRegisterThisComputer,
        )
      else if (m.personalPending)
        _Note(
          key: ShellKeys.personalPendingNote,
          FluentIcons.person_16_regular,
          context.strings.libraryScreen.personalPendingNote,
        ),
    ];
    if (failedShown && m.failedDownloads != null) return prepared;
    return [
      ...prepared,
      if (m.libraryMissingNames case final names?)
        _Note(
          key: ShellKeys.libraryMissingNotice,
          FluentIcons.warning_16_regular,
          g.libraryMissingFilesBody(names),
        ),
      if (m.libraryCompanionsAbsent)
        _Note(
          key: ShellKeys.libraryAbsentNotice,
          FluentIcons.warning_16_regular,
          g.libraryCompanionsAbsentBody,
        ),
    ];
  }

  List<_Note> _quietNotes(BuildContext context, {required bool offline}) {
    final g = context.strings.guide;
    return switch (_g.secondary) {
      GuidanceSecondary.offlineHint when offline => [
          _Note(FluentIcons.usb_stick_20_regular, g.offlineNote),
        ],
      GuidanceSecondary.checkOnlineNow => [
          _Note(FluentIcons.info_16_regular, g.checkOnlineNowNote),
        ],
      GuidanceSecondary.siteClosedForShabbat => [
          _Note(
            FluentIcons.info_16_regular,
            context.strings.pluginsDomain.siteClosedForShabbat,
          ),
        ],
      GuidanceSecondary.noSyncSelection => [
          _Note(
            FluentIcons.info_16_regular,
            g.noSyncSelectionNote,
            link: g.chooseInSettingsLink,
            onLink: actions.onOpenSettings,
          ),
        ],
      GuidanceSecondary.syncOff => _syncOffNotes(context, quiet: true),
      _ => const [],
    };
  }

  /// מה שיש ברשת ואינו מסומן להורדה — נאמר, כדי שלא ידלג בשקט. [quiet] — אין
  /// הורדה לצידו, ולכן הנוסח אומר שיש חדש ולא "לא יירד".
  List<_Note> _syncOffNotes(BuildContext context, {bool quiet = false}) {
    final g = context.strings.guide;
    final m = model;
    final app = m.onlineAppVersion != null && !m.syncApp;
    final library =
        (m.onlineLibraryVersion != null || m.onlineCompanionNames != null) &&
            !m.syncLibrary;
    final plugins = (m.onlinePluginChanges > 0 ||
            m.onlinePluginCatalogChanged ||
            m.onlineStoreApp) &&
        !m.syncPlugins;
    if (!app && !library && !plugins) return const [];
    return [
      _Note(
        FluentIcons.info_16_regular,
        quiet
            ? g.syncOffOnlyNote(
                app: app,
                library: library,
                plugins: plugins,
                libraryFilesOnly: m.onlineLibraryVersion == null,
              )
            : g.syncOffNote(app: app, library: library, plugins: plugins),
        key: quiet ? ShellKeys.homeSyncOffNote : null,
        link: g.changeInSettingsLink,
        onLink: actions.onOpenSettings,
      ),
    ];
  }

  static Widget _itemIcon(GuidanceItem item) => switch (item) {
        GuidanceItem.app => IconTile(size: IconTileSize.sm, child: _logo(20)),
        GuidanceItem.library => const IconTile(
            size: IconTileSize.sm,
            icon: FluentIcons.library_24_regular,
          ),
        GuidanceItem.plugins => const IconTile(
            size: IconTileSize.sm,
            icon: FluentIcons.puzzle_piece_24_regular,
          ),
      };

  /// מה שיותקן כאן — בלי גדלים, הכול כבר בכונן.
  List<_Item> _hereItems(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    final firstInstall = m.installedVersion == null;
    final drive = m.driveAppVersion;
    // סדר התצוגה קבוע (תוכנה, ספרייה, תוספים), גם כשהעדכון רץ בסדר אחר.
    final items = [..._g.hereItems]..sort((a, b) => a.index - b.index);
    return [
      for (final item in items)
        switch (item) {
          GuidanceItem.app => _item(
              _itemIcon(item),
              g.tileApp,
              subtitle: drive == null
                  ? null
                  : firstInstall
                      ? g.tileFactVersion(displayVersion(drive))
                      : g.itemUpdateTo(
                          displayVersion(drive, other: m.installedVersion),
                        ),
            ),
          GuidanceItem.library => _item(
              _itemIcon(item),
              g.tileLibrary,
              subtitle: firstInstall || m.libraryFreshInstall
                  ? g.itemLibraryFull
                  : m.driveCompanionNames ??
                      (m.driveLibraryVersion == null
                          ? g.itemLibraryUpdate
                          : g.itemLibraryUpdateTo(m.driveLibraryVersion!)),
            ),
          GuidanceItem.plugins => _item(
              _itemIcon(item),
              g.tilePlugins,
              subtitle: g.itemPluginUpdates(m.pluginUpdatesOnDrive),
            ),
        },
    ];
  }

  /// מה שיירד לכונן. תוספים בלי שינוי שאפשר לנקוב בו אינם שורה.
  List<GuidanceItem> _shownDownloads(GuidanceStrings g) => [
        for (final item in _g.downloadItems)
          if (item != GuidanceItem.plugins ||
              _onlinePluginsText(model, g) != null)
            item,
      ];

  /// חסם עליון שידוע בלי למדוד ברשת; לתוספים אין.
  int? _bytesOf(GuidanceItem item) => switch (item) {
        GuidanceItem.app => model.appDownloadBytes,
        GuidanceItem.library => model.libraryDownloadBytes,
        GuidanceItem.plugins => null,
      };

  List<_Item> _downloadItems(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    final s = context.strings.libraryScreen;
    final library = [
      if (m.onlineLibraryVersion != null)
        context.strings.pages.libVersion(m.onlineLibraryVersion!),
      if (m.personalMode && m.onlineLibraryVersion != null)
        switch (m.personalFloor) {
          final floor? => s.personalDownloadItem(m.personalMachines, '$floor'),
          null => s.personalDownloadItemNone,
        }
      else if (m.onlineCompanionNames != null)
        m.onlineCompanionNames!,
    ];
    return [
      for (final item in _shownDownloads(g))
        _item(
          _itemIcon(item),
          switch (item) {
            GuidanceItem.app => g.tileApp,
            GuidanceItem.library => g.tileLibrary,
            GuidanceItem.plugins => g.tilePlugins,
          },
          subtitle: switch (item) {
            GuidanceItem.app => m.onlineAppVersion == null
                ? null
                : g.tileFactVersion(
                    displayVersion(
                      m.onlineAppVersion!,
                      other: m.installedVersion,
                    ),
                  ),
            GuidanceItem.library =>
              library.isEmpty ? null : library.join(' · '),
            GuidanceItem.plugins => _onlinePluginsText(m, g),
          },
          size: switch (_bytesOf(item)) {
            final bytes? => g.itemUpTo(formatBytes(bytes)),
            null => null,
          },
        ),
    ];
  }

  /// הסכום לצד כמה פריטים; פריט בלי חסם נאמר בשמו ("ועוד התוספים").
  String? _total(BuildContext context) {
    final g = context.strings.guide;
    final items = _shownDownloads(g);
    final known = items.map(_bytesOf).whereType<int>();
    if (items.length < 2 || known.isEmpty) return null;
    bool unknown(GuidanceItem item) =>
        items.contains(item) && _bytesOf(item) == null;
    return g.downloadTotal(
      formatBytes(known.fold(0, (sum, bytes) => sum + bytes)),
      plusApp: unknown(GuidanceItem.app),
      plusLibrary: unknown(GuidanceItem.library),
      plusPlugins: unknown(GuidanceItem.plugins),
    );
  }

  /// הכלי עצמו ותוכנות נוספות — כדי ש"הכול מעודכן" לא יסתיר אותם.
  List<_Item> _otherItems(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    final launcher = m.launcher;
    final version =
        launcher?.version == null ? null : displayVersion(launcher!.version!);
    return [
      for (final other in _g.otherUpdates)
        switch (other) {
          OtherUpdate.launcher => _item(
              const IconTile(
                size: IconTileSize.sm,
                icon: FluentIcons.usb_stick_24_regular,
              ),
              g.otherLauncherTitle,
              subtitle: switch (launcher?.kind) {
                LauncherLineKind.downloading => g.launcherDownloading,
                LauncherLineKind.ready ||
                LauncherLineKind.readyManual when version != null =>
                  g.otherLauncherOnDrive(version),
                _ when version != null => g.otherLauncherOnline(version),
                _ => null,
              },
              onTap: actions.onOpenLauncherUpdate,
            ),
          OtherUpdate.customApps => _item(
              const IconTile(
                size: IconTileSize.sm,
                icon: FluentIcons.apps_24_regular,
              ),
              g.tileCustomApps,
              subtitle: g.chipAppsPending(m.customAppsPending),
              onTap: () => actions.onOpenSection(ShellSection.customApps),
            ),
        },
    ];
  }
}

/// התוספים וחנות התוספים שבאוצריא — שורה אחת.
String? _onlinePluginsText(HomeViewModel m, GuidanceStrings g) {
  final changes = m.onlinePluginChanges;
  if (changes > 0) {
    return m.onlineStoreApp
        ? g.itemPluginsWithStore(changes)
        : g.itemPlugins(changes);
  }
  if (m.onlinePluginCatalogChanged) return g.itemPluginsCatalog;
  return m.onlineStoreApp ? g.itemStoreApp : null;
}

/// רשימת הגיבור — שורות על רקע נבחר, ושורת סיכום בתחתית.
class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, this.total, this.free});

  final List<_Item> items;
  final String? total;
  final String? free;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return AppCard.section(
      key: ShellKeys.heroItems,
      selected: true,
      children: [
        for (final item in items)
          AppRow(
            leading: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            trailing: item.size == null ? null : Text(item.size!, style: meta),
            onTap: item.onTap,
          ),
        if (total != null || free != null)
          Padding(
            key: ShellKeys.heroTotal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text(total ?? '', style: meta)),
                if (free != null) ...[
                  const SizedBox(width: 14),
                  Text(free!, style: meta),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// הסמל העגול שבצד הגיבור (`.emblem`): 72, טבעת 6, ותג קטן בפינה.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.icon, this.mini, this.done = false});

  final IconData icon;
  final IconData? mini;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disc = done ? cs.primary : cs.secondaryContainer;
    final ring = done
        ? AppSurfaces.badgeRing(cs.primary)
        : AppSurfaces.emblemRing(cs.secondaryContainer);
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
          ),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
            child: Icon(
              icon,
              size: done ? 34 : 32,
              color: done ? cs.onPrimary : cs.onSecondaryContainer,
            ),
          ),
          if (mini != null)
            PositionedDirectional(
              bottom: 1,
              end: -1,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppSurfaces.card(context),
                ),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
                  child: Icon(mini, size: 16, color: cs.onPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroNote extends StatelessWidget {
  const _HeroNote(this.note, {super.key});

  final _Note note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(note.icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(note.text, style: style),
              if (note.link != null)
                TextLink(text: note.link!, onTap: note.onLink),
            ],
          ),
        ),
      ],
    );
  }
}

// ── האריחים ───────────────────────────────────────────────────────────────────

typedef _TileSpec = ({
  ShellSection section,
  Widget icon,
  String name,
  StatusKind kind,
  String label,
  IconData? chipIcon,
  List<String> facts,
});

class _Tiles extends StatelessWidget {
  const _Tiles({required this.model, required this.onOpen});

  final HomeViewModel model;
  final ValueChanged<ShellSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final tiles = _specs(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520 ? 1 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          final row = tiles.sublist(i, (i + columns).clamp(0, tiles.length));
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (j, spec) in row.indexed) ...[
                    if (j > 0) const SizedBox(width: 10),
                    Expanded(child: _Tile(spec: spec, onOpen: onOpen)),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  /// לא נבדק או בבדיקה — הגרסאות עוד לא ידועות, ושורות העובדות היו מטעות.
  static bool _factsKnown(TileStatus s) =>
      s != TileStatus.unknown && s != TileStatus.checking;

  List<String> _appFacts(BuildContext context) {
    final m = model;
    if (!_factsKnown(m.appTile)) return const [];
    final g = context.strings.guide;
    final t = context.strings.pages;
    String version(String v, String? other) =>
        g.tileFactVersion(displayVersion(v, other: other));
    return [
      g.tileFactHere(
        m.installedVersion == null
            ? t.libNotInstalled
            : version(m.installedVersion!, m.driveAppVersion),
      ),
      g.tileFactDrive(
        m.driveAppVersion == null
            ? t.nothingYet
            : version(m.driveAppVersion!, m.installedVersion),
      ),
      if (m.onlineAppLatest != null)
        g.tileFactOnline(version(m.onlineAppLatest!, m.driveAppVersion)),
    ];
  }

  List<String> _libraryFacts(BuildContext context) {
    final m = model;
    if (!_factsKnown(m.libraryTile)) return const [];
    final g = context.strings.guide;
    final t = context.strings.pages;
    final online = m.onlineLibraryLatest != null
        ? t.libVersion(m.onlineLibraryLatest!)
        : m.onlineCompanionNames;
    return [
      g.tileFactHere(
        m.libraryHereVersion != null
            ? t.libVersion(m.libraryHereVersion!)
            : m.libraryFreshInstall
                ? t.libNotInstalled
                : context.strings.common.unknownValue,
      ),
      g.tileFactDrive(
        m.driveLibraryVersion != null
            ? t.libVersion(m.driveLibraryVersion!)
            : t.nothingYet,
      ),
      if (online != null) g.tileFactOnline(online),
    ];
  }

  List<_TileSpec> _specs(BuildContext context) {
    final g = context.strings.guide;
    final common = context.strings.common;
    final m = model;

    // אותו אוצר מילים לתוכנה ולספרייה: השבב הוא הפעולה, העובדות בשורות.
    (StatusKind, String, IconData?) shared(TileStatus status) =>
        switch (status) {
          TileStatus.unknown || TileStatus.notCheckedOnline => (
              StatusKind.unknown,
              common.notCheckedYet,
              null
            ),
          TileStatus.checking => (StatusKind.working, g.chipChecking, null),
          TileStatus.working => (StatusKind.working, g.chipUpdating, null),
          TileStatus.attention => (StatusKind.error, g.chipAttention, null),
          TileStatus.preparedElsewhere => (
              StatusKind.needsAction,
              context.strings.libraryScreen.personalChipElsewhere,
              FluentIcons.person_16_regular,
            ),
          TileStatus.installHere => (
              StatusKind.needsAction,
              g.chipReadyToInstall,
              FluentIcons.arrow_download_16_regular,
            ),
          TileStatus.updateHere => (
              StatusKind.updateAvailable,
              context.strings.pages.chipUpdateOnDrive,
              null,
            ),
          TileStatus.nothingOnDrive => (
              StatusKind.needsAction,
              g.chipNotOnDrive,
              null,
            ),
          TileStatus.onlineAvailable => (
              StatusKind.updateAvailable,
              g.chipNewOnline,
              FluentIcons.arrow_download_16_regular,
            ),
          TileStatus.newerHere => (StatusKind.ok, g.chipNewerHere, null),
          TileStatus.needsConsent => (
              StatusKind.needsAction,
              context.strings.libraryDomain.semanticConsentRequired,
              FluentIcons.sparkle_16_regular,
            ),
          TileStatus.upToDate => (StatusKind.ok, g.chipLibraryUpToDate, null),
        };
    final app = m.appTile == TileStatus.working
        ? (StatusKind.working, g.chipInstalling, null)
        : shared(m.appTile);
    final library = shared(m.libraryTile);
    final plugins = switch (m.pluginsTile) {
      TileStatus.checking => (StatusKind.working, g.chipChecking, null),
      TileStatus.onlineAvailable => shared(TileStatus.onlineAvailable),
      TileStatus.updateHere => (
          StatusKind.updateAvailable,
          g.chipPluginUpdates(m.pluginUpdatesOnDrive),
          null,
        ),
      _ when m.pluginsOnDrive == 0 => (
          StatusKind.needsAction,
          g.chipNoPlugins,
          FluentIcons.puzzle_piece_16_regular,
        ),
      _ when m.installedVersion == null || m.pluginsInstalled == 0 => (
          StatusKind.needsAction,
          g.chipPluginsOnDrive(m.pluginsOnDrive),
          FluentIcons.puzzle_piece_16_regular,
        ),
      _ => (StatusKind.ok, g.chipPluginsInstalled(m.pluginsInstalled), null),
    };

    _TileSpec spec(
      ShellSection section,
      Widget icon,
      String name,
      (StatusKind, String, IconData?) chip, {
      List<String> facts = const [],
    }) =>
        (
          section: section,
          icon: icon,
          name: name,
          kind: chip.$1,
          label: chip.$2,
          chipIcon: chip.$3,
          facts: facts,
        );

    return [
      spec(
        ShellSection.otzaria,
        IconTile(child: _logo(26)),
        g.tileApp,
        app,
        facts: _appFacts(context),
      ),
      spec(
        ShellSection.library,
        const IconTile(icon: FluentIcons.library_24_regular),
        g.tileLibrary,
        library,
        facts: _libraryFacts(context),
      ),
      spec(
        ShellSection.plugins,
        const IconTile(icon: FluentIcons.puzzle_piece_24_regular),
        g.tilePlugins,
        plugins,
      ),
      if (m.customApps > 0)
        spec(
          ShellSection.customApps,
          const IconTile(icon: FluentIcons.apps_24_regular),
          g.tileCustomApps,
          m.customAppsPending > 0
              ? (
                  m.customAppsUnannounced
                      ? StatusKind.updateAvailable
                      : StatusKind.needsAction,
                  g.chipAppsPending(m.customAppsPending),
                  FluentIcons.arrow_download_16_regular,
                )
              : (StatusKind.ok, g.chipAppsInstalled(m.customApps), null),
        ),
      if (m.showsReportsTile)
        spec(
          ShellSection.reports,
          const IconTile(icon: FluentIcons.bug_24_regular),
          g.tileReports,
          m.reportsSending
              ? (StatusKind.working, g.chipReportsSending, null)
              // בכונן מוגן אין איסוף ואין שליחה: שליחה מוחקת מהכונן.
              : m.readOnly
                  ? (StatusKind.locked, g.chipReportsLocked, null)
                  : m.reportsToCollect > 0
                      ? (
                          StatusKind.updateAvailable,
                          g.chipReportsToCollect(m.reportsToCollect),
                          FluentIcons.arrow_upload_16_regular,
                        )
                      : (
                          StatusKind.updateAvailable,
                          g.chipReportsToSend(
                            m.reportsToSend + m.toolReportsPending,
                          ),
                          FluentIcons.send_16_regular,
                        ),
        ),
    ];
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.spec, required this.onOpen});

  final _TileSpec spec;
  final ValueChanged<ShellSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      key: ShellKeys.tile(spec.section),
      onTap: () => onOpen(spec.section),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              spec.icon,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.name,
                      style: AppTextStyles.rowValue.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(
                      kind: spec.kind,
                      label: spec.label,
                      icon: spec.chipIcon,
                    ),
                    if (spec.facts.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final fact in spec.facts)
                        Text(
                          fact,
                          style: AppTextStyles.meta.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_20_filled,
                size: 20,
                color: cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "לעזרה במקום" בתחתית הבית: שורה שקטה אחת, כדי לא להתחרות בגיבור.
class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return Padding(
      key: ShellKeys.homeContact,
      padding: const EdgeInsets.only(top: 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(FluentIcons.person_16_regular, size: 16, color: cs.primary),
          Text(context.strings.faq.contactLead, style: style),
          if (name.isNotEmpty)
            Text(name, style: style.copyWith(color: cs.onSurface)),
          if (phone.isNotEmpty)
            Text(
              phone,
              textDirection: TextDirection.ltr,
              style: style.copyWith(color: cs.onSurface),
            ),
        ],
      ),
    );
  }
}

// ── שורת המצב ─────────────────────────────────────────────────────────────────

/// שורת המצב שבתחתית החלון: עדכון הכלי בהתחלה; חיבור, כונן ו"נבדק ב-" בקצה.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.model,
    required this.actions,
    this.launcherProgress,
  });

  final HomeViewModel model;
  final HomeActions actions;
  final Widget? launcherProgress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final style = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    // שעת הבדיקה ברשת — במחשב מחובר בלבד.
    final checkedAt = model.online == true ? model.onlineCheckedAt : null;
    final drive = model.driveName;
    final online = model.online;

    final canCheck = !model.readOnly &&
        !model.checkBlocked &&
        model.guidance.primary != GuidancePrimary.taskInProgress;

    Widget item(IconData icon, String text, {Key? key}) => Row(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(text, style: style),
          ],
        );

    final meta = <Widget>[
      if (online != null && !model.readOnly)
        item(
          online
              ? FluentIcons.globe_desktop_20_regular
              : FluentIcons.desktop_16_regular,
          online ? g.eyebrowOnline : g.eyebrowOffline,
          key: ShellKeys.connectionLine,
        ),
      if (drive != null)
        Row(
          key: ShellKeys.driveLine,
          mainAxisSize: MainAxisSize.min,
          children: [
            item(FluentIcons.usb_stick_20_regular, g.drive(drive)),
            if (model.readOnly) ...[
              const SizedBox(width: 8),
              StatusChip(
                key: ShellKeys.driveLockedChip,
                kind: StatusKind.error,
                icon: model.driveFull
                    ? FluentIcons.storage_16_regular
                    : FluentIcons.lock_closed_16_regular,
                label:
                    model.driveFull ? g.driveFullSuffix : g.driveReadOnlySuffix,
              ),
            ],
          ],
        ),
      if (checkedAt != null || canCheck)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (checkedAt != null)
              Tooltip(
                key: ShellKeys.checkedAt,
                message: g.recheckHint,
                child: Text(g.checkedAt(formatClock(checkedAt)), style: style),
              ),
            if (checkedAt != null && canCheck) const SizedBox(width: 8),
            if (canCheck && model.checkingNow)
              Row(
                key: ShellKeys.checkNow,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(g.chipChecking, style: style),
                ],
              )
            else if (canCheck)
              TextLink(
                key: ShellKeys.checkNow,
                text: g.checkNowLink,
                onTap: actions.onRecheck,
                style: AppTextStyles.meta,
              ),
          ],
        ),
    ];

    final launcher = model.launcher;
    return Container(
      key: ShellKeys.statusBar,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppSurfaces.topBarBackground(context),
        border:
            Border(top: BorderSide(color: AppSurfaces.shellDivider(context))),
      ),
      child: Row(
        children: [
          if (launcher != null) ...[
            _launcher(context, launcher, style),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 20,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: meta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// כמו "עדכון זמין" שבאוצריא: כפתור בולט, גם כשהגרסה החדשה רק בכונן.
  Widget _launcher(BuildContext context, LauncherLine line, TextStyle style) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final busy = model.guidance.primary == GuidancePrimary.taskInProgress;
    final version = line.version == null ? '' : displayVersion(line.version!);
    if (line.kind == LauncherLineKind.downloading) {
      return Row(
        key: ShellKeys.launcherLine,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.arrow_download_16_regular,
              size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(g.launcherDownloading, style: style),
          if (launcherProgress != null) ...[
            const SizedBox(width: 8),
            launcherProgress!,
          ],
        ],
      );
    }
    final tooltip = busy
        ? context.strings.pages.pageBusyNote
        : switch (line.kind) {
            LauncherLineKind.online => g.launcherOnline(version),
            LauncherLineKind.error => line.error ?? '',
            _ => g.launcherOnDrive(version),
          };
    return Tooltip(
      key: ShellKeys.launcherLine,
      message: tooltip,
      child: ActionButton.neutral(
        key: ShellKeys.launcherUpdateButton,
        text: g.updateAvailableButton,
        icon: line.kind == LauncherLineKind.error
            ? FluentIcons.warning_24_regular
            : FluentIcons.arrow_download_24_regular,
        size: ActionButtonSize.sm,
        onPressed: busy ? null : actions.onOpenLauncherUpdate,
      ),
    );
  }
}

/// שם השפה האחרת בשמה שלה — הכפתור שבמסך הפתיחה.
String otherLanguageName(AppStrings strings) =>
    strings.language == AppLanguage.hebrew
        ? strings.settings.languageEnglish
        : strings.settings.languageHebrew;
