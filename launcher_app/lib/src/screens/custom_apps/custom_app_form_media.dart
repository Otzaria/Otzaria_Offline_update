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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            // תצוגה מקדימה קטנה ומרובעת, ולכן היחס נקבע כאן ולא מהכלל:
            // ריבוע 64 עם האוויר של הכרטיס היה משאיר אייקון של 32.
            child: StoreThumbnail.icon(
              imagePath: iconPath,
              placeholderIcon: FluentIcons.box_24_regular,
              aspectRatio: 1,
              ratio: 0.78,
              iconSize: 28,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceSM,
              children: [
                ActionButton.neutral(
                  text: t.pickIconButton,
                  icon: FluentIcons.image_24_regular,
                  onPressed: onPick,
                ),
                if (canExtract)
                  ActionButton.ghost(
                    text: t.extractIconButton,
                    icon: FluentIcons.wand_24_regular,
                    isLoading: isExtracting,
                    onPressed: isExtracting ? null : onExtract,
                  ),
                if (iconPath != null)
                  ActionButton.ghost(
                    text: t.removeIconTooltip,
                    icon: FluentIcons.dismiss_24_regular,
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
    final theme = Theme.of(context);

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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ActionButton.neutral(
            text: t.addScreenshotsButton,
            icon: FluentIcons.image_multiple_24_regular,
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
          SizedBox(
            width: 72,
            child: StoreThumbnail(
              imagePath: path,
              placeholderIcon: FluentIcons.image_off_24_regular,
              aspectRatio: 16 / 9,
              iconSize: 20,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Text(
              p.basename(path),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // ⚠️ חיצים ולא `RtlIcon`: אלה חיצי סדר ברשימה אנכית, ו-RTL
          // אינו הופך "למעלה" ו"למטה".
          SecondaryIconButton(
            icon: FluentIcons.arrow_up_24_regular,
            tooltip: t.moveScreenshotBackTooltip,
            onPressed: onMoveBack,
          ),
          SecondaryIconButton(
            icon: FluentIcons.arrow_down_24_regular,
            tooltip: t.moveScreenshotForwardTooltip,
            onPressed: onMoveForward,
          ),
          SecondaryIconButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: t.removeScreenshotTooltip,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
