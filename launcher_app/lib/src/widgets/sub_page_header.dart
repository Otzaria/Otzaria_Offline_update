import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'focus_ring.dart';
import 'rtl_icon.dart';

/// פריט בפירור הלחם. בלי [onTap] — המיקום הנוכחי.
typedef Crumb = ({String label, VoidCallback? onTap});

/// מוסר את ראש דף המשנה פנימה, אל [ScreenBody] או [StoreBody] — המסגרת עוטפת
/// בו מסך קיים, והמסך עצמו אינו צריך לדעת שהוא דף משנה.
class SubPageHeaderScope extends InheritedWidget {
  const SubPageHeaderScope({
    super.key,
    required this.header,
    required super.child,
  });

  /// `null` — מסך שכבר הציג את הראש בעצמו (מעל שכבה שמכסה את גופו).
  final Widget? header;

  static Widget? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubPageHeaderScope>()?.header;

  /// בתוך דף משנה: החזרה והפירור כבר בראש הדף, ואין צורך בכפתור חזרה משלו.
  static bool isSubPage(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubPageHeaderScope>() != null;

  @override
  bool updateShouldNotify(SubPageHeaderScope oldWidget) =>
      header != oldWidget.header;
}

/// ראש דף משנה (`.subhead`): כפתור חזרה ופירור "בית › … › הדף".
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({
    super.key,
    required this.onBack,
    required this.onHome,
    required this.trail,
  });

  final VoidCallback onBack;
  final VoidCallback onHome;
  final List<Crumb> trail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.strings.shell;

    Widget link(String label, VoidCallback onTap) =>
        _CrumbLink(label: label, onTap: onTap);

    final crumbs = <Widget>[link(s.breadcrumbHome, onHome)];
    for (final (i, crumb) in trail.indexed) {
      crumbs.add(
        Icon(
          // הפירור מתקדם בכיוון הקריאה; Icon מהפך את ה-chevron ב-RTL.
          FluentIcons.chevron_right_16_regular,
          size: 14,
          color: cs.outline,
        ),
      );
      final isLast = i == trail.length - 1;
      crumbs.add(
        isLast || crumb.onTap == null
            ? Text(
                crumb.label,
                style: AppTextStyles.small.copyWith(
                  color: cs.onSurface,
                  fontWeight: AppTextStyles.semibold,
                ),
              )
            : link(crumb.label, crumb.onTap!),
      );
    }

    // המוקאפ מושך את השורה 10 אל מחוץ לקצה ההתחלה ו-8 למעלה, כדי שהחץ
    // יתיישר עם הכותרת שמתחתיו.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Transform.translate(
        offset: Offset(context.isRtl ? 10 : -10, -8),
        child: Row(
          children: [
            Tooltip(
              message: s.backTooltip,
              child: IconButton(
                onPressed: onBack,
                icon:
                    const RtlIcon(FluentIcons.arrow_left_24_regular, size: 20),
                color: cs.onSurfaceVariant,
                style: IconButton.styleFrom(
                  fixedSize: const Size(40, 40),
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: crumbs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// קישור בפירור (`.crumbs .link`): בריחוף הטקסט נצבע ב-primary ומקבל קו
/// תחתון, בלי רקע.
class _CrumbLink extends StatefulWidget {
  const _CrumbLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_CrumbLink> createState() => _CrumbLinkState();
}

class _CrumbLinkState extends State<_CrumbLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(4));
    return FocusRing(
      borderRadius: radius,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovered) => setState(() => _hovered = hovered),
        borderRadius: radius,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: Text(
          widget.label,
          style: AppTextStyles.small.copyWith(
            color: _hovered ? cs.primary : cs.onSurfaceVariant,
            decoration: _hovered ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}
