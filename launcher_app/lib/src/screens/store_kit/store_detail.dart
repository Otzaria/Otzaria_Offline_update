import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'store_body.dart';
import 'store_screenshot_lightbox.dart';
import 'store_visuals.dart';

class StoreDetailPage extends StatelessWidget {
  const StoreDetailPage({
    super.key,
    required this.backLabel,
    required this.title,
    required this.onBack,
    required this.panels,
  });

  final String backLabel;
  final String title;
  final VoidCallback onBack;
  final List<Widget> panels;

  @override
  Widget build(BuildContext context) {
    return StoreBody(
      header: StoreDetailHeader(
        backLabel: backLabel,
        title: title,
        onBack: onBack,
      ),
      slivers: [
        StoreBody.padded(
          SliverList.list(children: panels),
          top: AppTokens.spaceMD,
        ),
      ],
    );
  }
}

class StoreDetailHeader extends StatelessWidget {
  const StoreDetailHeader({
    super.key,
    required this.backLabel,
    required this.title,
    required this.onBack,
  });

  final String backLabel;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: StoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          ActionButton.ghost(
            text: backLabel,
            icon: context.backArrowIcon,
            onPressed: onBack,
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class StoreDetailPanel extends StatelessWidget {
  const StoreDetailPanel({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SettingsCard.titleStyleOf(context)),
            const SizedBox(height: AppTokens.spaceMD),
            child,
          ],
        ),
      ),
    );
  }
}

class StoreDetailHero extends StatelessWidget {
  const StoreDetailHero({
    super.key,
    required this.image,
    required this.imageWidth,
    this.imageMaxWidth,
    required this.details,
  });

  final Widget image;
  final double imageWidth;
  final double? imageMaxWidth;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < LayoutBreakpoints.medium;
            Widget framed = SizedBox(
              width: narrow ? double.infinity : imageWidth,
              child: image,
            );
            if (imageMaxWidth case final maxWidth?) {
              framed = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: framed,
              );
            }

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  framed,
                  const SizedBox(height: AppTokens.spaceMD),
                  details,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                framed,
                const SizedBox(width: AppTokens.spaceXL),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class StoreInfoEntry {
  const StoreInfoEntry({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;
}

class StoreInfoGrid extends StatelessWidget {
  const StoreInfoGrid({super.key, required this.entries});

  final List<StoreInfoEntry> entries;

  static const double singleColumnBelow = 420;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < singleColumnBelow ? 1 : 2;
        final cellWidth =
            (constraints.maxWidth - AppTokens.spaceSM * (columns - 1)) /
                columns;

        return Wrap(
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            for (final entry in entries)
              SizedBox(
                width: entry.wide || columns == 1
                    ? constraints.maxWidth
                    : cellWidth,
                child: StoreInfoCell(label: entry.label, value: entry.value),
              ),
          ],
        );
      },
    );
  }
}

class StoreInfoCell extends StatelessWidget {
  const StoreInfoCell({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM + 2,
      ),
      decoration: BoxDecoration(
        color: AppSurfaces.panelSection(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTokens.fontMD,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class StoreScreenshotsPanel extends StatelessWidget {
  const StoreScreenshotsPanel({
    super.key,
    required this.title,
    required this.paths,
  });

  final String title;
  final List<String> paths;

  static const double thumbWidth = 200;

  @override
  Widget build(BuildContext context) {
    return StoreDetailPanel(
      title: title,
      child: Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (var i = 0; i < paths.length; i++)
            SizedBox(
              width: thumbWidth,
              child: AppCard(
                onTap: () => showStoreScreenshots(
                  context,
                  paths: paths,
                  initialIndex: i,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(paths[i]),
                    fit: BoxFit.cover,
                    cacheWidth: decodeWidthFor(context, thumbWidth),
                    errorBuilder: (context, _, __) => const Center(
                      child: Icon(FluentIcons.image_off_24_regular),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
