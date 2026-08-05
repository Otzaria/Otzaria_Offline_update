import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// סוגי חיווי המצב של רכיב. לכל אחד סמל **וגם** טקסט — התכנון (§14) אוסר
/// להסתמך על צבע בלבד.
enum StatusKind { ok, updateAvailable, working, needsAction, error, unknown }

/// שבב חיווי מצב — אייקון + טקסט על רקע מעומעם בצבע המצב.
class StatusChip extends StatelessWidget {
  final StatusKind kind;
  final String label;

  const StatusChip({super.key, required this.kind, required this.label});

  IconData get _icon => switch (kind) {
        StatusKind.ok => FluentIcons.checkmark_circle_24_regular,
        StatusKind.updateAvailable => FluentIcons.arrow_download_24_regular,
        StatusKind.working => FluentIcons.arrow_sync_24_regular,
        StatusKind.needsAction => FluentIcons.info_24_regular,
        StatusKind.error => FluentIcons.error_circle_24_regular,
        StatusKind.unknown => FluentIcons.question_circle_24_regular,
      };

  Color _color(ColorScheme cs) => switch (kind) {
        StatusKind.ok => cs.primary,
        StatusKind.updateAvailable => cs.tertiary,
        StatusKind.working => cs.secondary,
        StatusKind.needsAction => cs.tertiary,
        StatusKind.error => cs.error,
        StatusKind.unknown => cs.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _color(cs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppSurfaces.statusChip(color),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          kind == StatusKind.working
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(_icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
