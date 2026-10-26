import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../services/byte_size.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_fields.dart';
import 'installer_kind_label.dart';

/// מקור "GitHub": כתובת הריפו ו"הצגת הקבצים" בשורה אחת, ומתחתיה הקבצים של
/// ה-release האחרון לבחירה.
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
    final cs = Theme.of(context).colorScheme;
    final hint = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormTextField(
          label: t.githubUrlLabel,
          controller: urlController,
          hint: t.githubUrlHint,
          onChanged: onUrlChanged,
          ltr: true,
          trailing: ActionButton.neutral(
            text: t.fetchAssetsButton,
            isLoading: isFetching,
            onPressed: isFetching ? null : onFetch,
          ),
        ),
        // בעריכה, כל עוד לא הובאה רשימה חדשה, אומרים במפורש מה יישאר.
        if (release == null && hasKeptAsset)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: Text(t.githubAssetKept, style: hint),
          ),
        if (error case final message?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: InfoErrorRow(message: message),
          ),
        if (release case final release?)
          FormLabelled(
            label: t.assetsFromRelease(release.tagName),
            help: t.assetHint,
            child: release.assets.isEmpty
                ? Text(t.noAssetsFound, style: AppTextStyles.body)
                // ⚠️ הבחירה כאן היא כל ההבדל בין "מוריד את הקובץ הנכון" לבין
                // "מוריד את הראשון ברשימה" — ל-release יש גם x86, portable ו-sha.
                : RowsCard(
                    children: [
                      for (final asset in release.assets)
                        _AssetRow(
                          asset: asset,
                          selected: asset == selectedAsset,
                          onTap: () => onSelectAsset(asset),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final GithubAsset asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        overlayColor: AppSurfaces.stateLayer(cs.primary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected
                    ? FluentIcons.radio_button_20_filled
                    : FluentIcons.circle_20_regular,
                size: 20,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  asset.name,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatBytes(asset.sizeBytes),
                style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// מקור "קובץ": הקובץ שנבחר, או זה שכבר בכונן, ומה שזוהה בו.
class CustomAppLocalFileSection extends StatelessWidget {
  const CustomAppLocalFileSection({
    super.key,
    required this.path,
    required this.kept,
    required this.sniffedKind,
    required this.onPick,
    this.error,
  });

  final String? path;
  final StoredInstaller? kept;
  final CustomInstallerKind? sniffedKind;
  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final path = this.path;
    final kept = this.kept;
    // מה שזוהה בקובץ. ל-ZIP זה השינוי הגדול — הוא מועתק לתיקיית ההורדות ואינו
    // מותקן, וכדאי לדעת זאת לפני ולא אחרי.
    final kind = sniffedKind;

    return FormLabelled(
      label: t.fileLabel,
      help: error ??
          (kind == null
              ? null
              : t.installerKindSniffed(installerKindLabelOf(kind, t))),
      child: Row(
        children: [
          Expanded(
            child: path != null
                ? PathText(path)
                : Text(
                    // מה שנבחר עכשיו קודם למה ששמור; בלי שניהם — הזמנה לבחור.
                    kept != null
                        ? t.installerKept(kept.fileName)
                        : t.pickInstallerDialogTitle,
                    style: AppTextStyles.body.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          ActionButton.neutral(
            text: t.pickInstallerButton,
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}
