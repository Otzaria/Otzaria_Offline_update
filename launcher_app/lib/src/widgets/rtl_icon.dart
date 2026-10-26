// אייקון RTL-מודע: מחליף או מהפך אייקון שאין לו היפוך משלו — פורט מאוצריא.
// ⚠️ אין להשתמש ב-const Map<IconData,...> כי IconData לא מימש ==.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

class RtlIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  const RtlIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  // חצים ו-chevron של Fluent נושאים matchTextDirection, ו-Icon מהפך אותם בעצמו.
  static final Map<IconData, IconData> _fluentMirrorMap = {
    FluentIcons.panel_left_24_regular: FluentIcons.panel_right_24_regular,
    FluentIcons.panel_right_24_regular: FluentIcons.panel_left_24_regular,
  };

  // אייקונים ללא גרסת RTL בספריה — מותר להפוך גאומטרית.
  static final Set<IconData> _flippableIcons = {
    FluentIcons.book_24_regular,
    FluentIcons.book_24_filled,
    FluentIcons.book_information_24_regular,
    FluentIcons.list_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final baseIcon = Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );

    if (!isRtl) return baseIcon;

    final mirroredIcon = _fluentMirrorMap[icon];
    if (mirroredIcon != null) {
      return Icon(
        mirroredIcon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }

    if (_flippableIcons.contains(icon)) {
      return Transform.flip(flipX: true, child: baseIcon);
    }

    return baseIcon;
  }
}
