import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/byte_size.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_fields.dart';
import 'installer_kind_label.dart';

/// מקור "גיטהאב": כתובת הריפו, ומתחתיה הקבצים של ה-release האחרון.
class CustomAppGithubSection extends StatelessWidget {
  const CustomAppGithubSection({
    super.key,
    required this.urlController,
    required this.onUrlChanged,
    required this.isFetching,
    required this.onFetch,
    required this.hasKeptAsset,
    required this.error,
    required this.release,
    required this.selectedAsset,
    required this.onSelectAsset,
  });

  final TextEditingController urlController;
  final ValueChanged<String> onUrlChanged;
  final bool isFetching;
  final VoidCallback onFetch;

  /// בעריכה, כשהתבנית שנשמרה עדיין חלה על הריפו שבשדה.
  final bool hasKeptAsset;
  final String? error;
  final GithubRelease? release;
  final GithubAsset? selectedAsset;
  final ValueChanged<GithubAsset> onSelectAsset;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormTextField(
          label: t.githubUrlLabel,
          controller: urlController,
          hint: t.githubUrlHint,
          onChanged: onUrlChanged,
        ),
        ActionButton.neutral(
          text: t.fetchAssetsButton,
          icon: FluentIcons.search_24_regular,
          isLoading: isFetching,
          onPressed: isFetching ? null : onFetch,
        ),
        // בעריכה, כל עוד לא הובאה רשימה חדשה, אומרים במפורש מה יישאר.
        if (release == null && hasKeptAsset) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Text(t.githubAssetKept, style: hint),
        ],
        if (error case final message?) ...[
          const SizedBox(height: AppTokens.spaceSM),
          InfoErrorRow(message: message),
        ],
        if (release case final release?) ...[
          const SizedBox(height: AppTokens.spaceMD),
          Text(
            t.assetsFromRelease(release.tagName),
            style: theme.textTheme.labelLarge,
          ),
          Text(t.assetHint, style: hint),
          const SizedBox(height: AppTokens.spaceSM),
          if (release.assets.isEmpty)
            Text(t.noAssetsFound, style: theme.textTheme.bodyMedium)
          else
            // ⚠️ הבחירה כאן היא כל ההבדל בין "מוריד את הקובץ הנכון" לבין
            // "מוריד את הראשון ברשימה" — ל-release טיפוסי יש גם x86, גם
            // portable וגם קובצי sha.
            for (final asset in release.assets)
              SettingsActionTile.text(
                icon: asset == selectedAsset
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.circle_24_regular,
                title: asset.name,
                subtitle: formatBytes(asset.sizeBytes),
                onTap: () => onSelectAsset(asset),
              ),
        ],
      ],
    );
  }
}

/// מקור "קובץ שלי": הקובץ שנבחר, או זה שכבר על הכונן, ומה שזוהה בו.
class CustomAppLocalFileSection extends StatelessWidget {
  const CustomAppLocalFileSection({
    super.key,
    required this.path,
    required this.kept,
    required this.sniffedKind,
    required this.onPick,
  });

  final String? path;
  final StoredInstaller? kept;
  final CustomInstallerKind? sniffedKind;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final path = this.path;
    final kept = this.kept;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // מה שנבחר עכשיו קודם לְמה ששמור, ובלי שניהם — הזמנה לבחור.
          path != null
              ? p.basename(path)
              : kept != null
                  ? t.installerKept(kept.fileName)
                  : t.pickInstallerDialogTitle,
          style: hint,
        ),
        // מה שזוהה בקובץ. ל-ZIP זה השינוי הגדול ביותר — הוא אינו מותקן
        // אלא מועתק לתיקיית ההורדות, וכדאי לדעת זאת לפני ולא אחרי.
        if (sniffedKind case final kind?) ...[
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            t.installerKindSniffed(installerKindLabelOf(kind, t)),
            style: hint,
          ),
        ],
        const SizedBox(height: AppTokens.spaceSM),
        ActionButton.neutral(
          text: t.pickInstallerButton,
          icon: FluentIcons.folder_open_24_regular,
          onPressed: onPick,
        ),
      ],
    );
  }
}
