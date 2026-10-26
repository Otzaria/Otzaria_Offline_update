import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_form_fields.dart';

/// הסיומות שדיאלוג הבחירה מציע. אותה רשימה שמאשרת `CustomAppMedia` —
/// עדיף לסנן בדיאלוג מאשר לדחות אחרי שהמשתמש כבר בחר.
final List<String> customAppImageExtensions = [
  for (final extension in CustomAppMedia.allowedExtensions)
    extension.substring(1),
];

/// האייקון: תצוגה מקדימה, בחירה, חילוץ מקובץ ההרצה והסרה.
class CustomAppIconSection extends StatelessWidget {
  const CustomAppIconSection({
    super.key,
    required this.iconPath,
    required this.canExtract,
    required this.isExtracting,
    required this.onPick,
    required this.onExtract,
    required this.onRemove,
  });

  final String? iconPath;

  /// יש קובץ הרצה לחלץ ממנו, ואנחנו בווינדוס.
  final bool canExtract;
  final bool isExtracting;
  final VoidCallback onPick;
  final VoidCallback onExtract;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return FormLabelled(
      label: t.iconLabel,
      child: Row(
        children: [
          StoreIcon(
            imagePath: iconPath,
            placeholderIcon: FluentIcons.box_24_regular,
            size: 54,
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Wrap(
              spacing: AppTokens.spaceXS,
              runSpacing: AppTokens.spaceXS,
              children: [
                if (canExtract)
                  ActionButton.ghost(
                    text: t.extractIconButton,
                    size: ActionButtonSize.sm,
                    isLoading: isExtracting,
                    onPressed: isExtracting ? null : onExtract,
                  ),
                ActionButton.ghost(
                  text: t.pickIconButton,
                  size: ActionButtonSize.sm,
                  onPressed: onPick,
                ),
                if (iconPath != null)
                  ActionButton.ghost(
                    text: t.removeIconTooltip,
                    size: ActionButtonSize.sm,
                    onPressed: onRemove,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// צילומי המסך, בסדר שבו יוצגו בדף התוכנה.
class CustomAppScreenshotsSection extends StatelessWidget {
  const CustomAppScreenshotsSection({
    super.key,
    required this.screenshots,
    required this.onMove,
    required this.onRemove,
    required this.onAdd,
  });

  final List<String> screenshots;
  final void Function(int from, int to) onMove;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final cs = Theme.of(context).colorScheme;

    return FormLabelled(
      label: t.screenshotsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < screenshots.length; i++)
            _ScreenshotRow(
              path: screenshots[i],
              // התמונה הראשונה היא זו שנראית ראשונה בדף, ולכן הסדר כן
              // משנה — והדרך לשנות אותו היא הזזה ולא הסרה ובחירה מחדש.
              onMoveBack: i == 0 ? null : () => onMove(i, i - 1),
              onMoveForward:
                  i == screenshots.length - 1 ? null : () => onMove(i, i + 1),
              onRemove: () => onRemove(i),
            ),
          if (screenshots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
              child: Text(
                t.screenshotsChosen(screenshots.length),
                style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ActionButton.neutral(
            text: t.addScreenshotsButton,
            icon: FluentIcons.image_add_20_regular,
            size: ActionButtonSize.sm,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// שורת צילום מסך אחת בטופס: תצוגה מקדימה, הזזה בסדר, והסרה.
class _ScreenshotRow extends StatelessWidget {
  const _ScreenshotRow({
    required this.path,
    required this.onMoveBack,
    required this.onMoveForward,
    required this.onRemove,
  });

  final String path;
  final VoidCallback? onMoveBack;
  final VoidCallback? onMoveForward;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            child: Container(
              width: 72,
              height: 54,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: decodeWidthFor(context, 72),
                errorBuilder: (context, _, __) => const Icon(
                  FluentIcons.image_off_20_regular,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Text(
              p.basename(path),
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.meta,
            ),
          ),
          // ⚠️ חיצים ולא `RtlIcon`: אלה חיצי סדר ברשימה אנכית, ו-RTL
          // אינו הופך "למעלה" ו"למטה".
          AppIconButton(
            icon: FluentIcons.arrow_up_20_regular,
            tooltip: t.moveScreenshotBackTooltip,
            small: true,
            onPressed: onMoveBack,
          ),
          AppIconButton(
            icon: FluentIcons.arrow_down_20_regular,
            tooltip: t.moveScreenshotForwardTooltip,
            small: true,
            onPressed: onMoveForward,
          ),
          AppIconButton(
            icon: FluentIcons.delete_20_regular,
            tooltip: t.removeScreenshotTooltip,
            small: true,
            danger: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
