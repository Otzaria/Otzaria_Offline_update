import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'home_page.dart' show otherLanguageName;

/// מסך הפתיחה של כונן ריק במחשב בלי אוצריא: שלושה שלבים, והפעולה של
/// המחשב הזה — הורדה כשיש אינטרנט, הסבר כשאין.
class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.offline,
    required this.narrow,
    required this.onDownload,
    required this.onHelp,
    required this.onToggleLanguage,
    this.busy = false,
    this.notices = const [],
    this.links = const [],
  });

  /// אין מכאן הורדה: אין אינטרנט, או שהכונן מוגן.
  final bool offline;
  final bool narrow;

  /// בדיקה ברשת רצה — "הורדה" ממתינה לה, כמו בבית.
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onHelp;
  final VoidCallback onToggleLanguage;

  /// הודעות הכונן (מוגן או מלא) והודעות הבית — מעל הכול.
  final List<Widget> notices;

  /// דפים שיש להם מה להציג גם בכונן ריק מאוצריא (תוכנות נוספות, דיווחים).
  final List<({String label, VoidCallback onTap})> links;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final small = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);
    final arrow = Icon(
      FluentIcons.chevron_right_20_filled,
      size: 20,
      color: cs.outline,
    );

    final steps = Padding(
      padding: EdgeInsets.symmetric(vertical: narrow ? 18 : 22),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Step(
                number: 1,
                icon: FluentIcons.desktop_24_regular,
                mini: FluentIcons.globe_16_regular,
                title: g.step1Title,
                body: offline ? g.step1BodyOffline : g.step1BodyOnline,
                here: !offline,
              ),
            ),
            SizedBox(width: 28, child: Center(child: arrow)),
            Expanded(
              child: _Step(
                number: 2,
                icon: FluentIcons.usb_stick_24_regular,
                title: g.step2Title,
                body: g.step2Body,
              ),
            ),
            SizedBox(width: 28, child: Center(child: arrow)),
            Expanded(
              child: _Step(
                number: 3,
                icon: FluentIcons.desktop_24_regular,
                mini: FluentIcons.checkmark_16_regular,
                title: g.step3Title,
                body: offline ? g.step3BodyOffline : g.step3BodyOnline,
                here: offline,
              ),
            ),
          ],
        ),
      ),
    );

    final cta = offline
        ? [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300),
              child: ActionButton.neutral(
                key: ShellKeys.welcomePrimary,
                text: g.welcomeHelpButton,
                icon: FluentIcons.question_circle_24_regular,
                size: ActionButtonSize.lg,
                autofocus: true,
                onPressed: onHelp,
              ),
            ),
            Text(g.welcomeOfflineNote,
                style: small, textAlign: TextAlign.center),
          ]
        : [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300),
              child: ActionButton.recommended(
                key: ShellKeys.welcomePrimary,
                text: g.welcomeDownloadButton,
                icon: busy
                    ? FluentIcons.arrow_sync_24_regular
                    : FluentIcons.arrow_download_24_regular,
                spinning: busy,
                size: ActionButtonSize.lg,
                autofocus: true,
                onPressed: busy ? null : onDownload,
              ),
            ),
            Text(
              g.welcomeDownloadNote,
              style: small,
              textAlign: TextAlign.center,
            ),
          ];
    if (links.isNotEmpty) {
      cta.add(
        Wrap(
          key: ShellKeys.welcomeLinks,
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            Text(g.welcomeAlsoOnDrive, style: small),
            for (final link in links)
              TextLink(text: link.label, onTap: link.onTap),
          ],
        ),
      );
    }
    final language = ActionButton.ghost(
      key: ShellKeys.welcomeLanguage,
      text: otherLanguageName(context.strings),
      icon: FluentIcons.globe_20_regular,
      size: ActionButtonSize.sm,
      onPressed: onToggleLanguage,
    );

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Stack(
              children: [
                Column(
                  children: [
                    // עם הודעות הכפתור עולה מעליהן ולא מוסתר: דווקא בכונן
                    // תקוע צריך להבין את ההודעה.
                    if (notices.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: language,
                        ),
                      ),
                    ...notices,
                    Image.asset(
                      'assets/images/welcome_book.png',
                      width: narrow ? 88 : 120,
                      height: narrow ? 88 : 120,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      g.welcomeTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heroTitle.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const _Ornament(),
                    Text(
                      offline ? g.welcomeLeadOffline : g.welcomeLeadOnline,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    steps,
                    for (final (i, child) in cta.indexed) ...[
                      if (i > 0) const SizedBox(height: 10),
                      child,
                    ],
                  ],
                ),
                if (notices.isEmpty)
                  PositionedDirectional(top: -10, end: -8, child: language),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// הקישוט שמתחת לכותרת: שני קווים דוהים ויהלום.
class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.of(context).ornament;
    Widget line(Alignment from) => Container(
          width: 40,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: from,
              end: -from,
              colors: [AppSurfaces.transparent(color), color],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          line(Alignment.centerLeft),
          const SizedBox(width: 8),
          Transform.rotate(
            angle: 0.785398,
            child: Container(width: 6, height: 6, color: color),
          ),
          const SizedBox(width: 8),
          line(Alignment.centerRight),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    this.mini,
    this.here = false,
  });

  final int number;
  final IconData icon;
  final IconData? mini;
  final String title;
  final String body;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: here ? Border.all(color: cs.primary, width: 2) : null,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.secondaryContainer,
                  ),
                  child: Icon(icon, size: 26, color: cs.onSecondaryContainer),
                ),
                if (mini != null)
                  PositionedDirectional(
                    bottom: -5,
                    end: -7,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppSurfaces.card(context),
                      ),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary,
                        ),
                        child: Icon(mini, size: 14, color: cs.onPrimary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            g.step(number),
            style: AppTextStyles.chip.copyWith(color: cs.primary),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
    if (!here) return card;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      alignment: Alignment.topCenter,
      children: [
        card,
        Positioned(
          top: -11,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: AppTokens.pill,
            ),
            child: Text(
              g.youAreHere,
              style: AppTextStyles.chip.copyWith(color: cs.onPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
