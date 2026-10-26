import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_status.dart';

/// כרטיס תוכנה ברשת — אותו כרטיס של חנות התוספים: סמל, שם, גרסה · גודל ·
/// מקור, תיאור ופעולה אחת. השאר בדף התוכנה.
class CustomAppStoreCard extends StatelessWidget {
  const CustomAppStoreCard({
    super.key,
    required this.controller,
    required this.app,
    required this.readOnly,
    required this.onOpenDetail,
    required this.onInstall,
    required this.onLaunch,
    required this.onDownload,
    this.online = true,
  });

  final CustomAppsController controller;
  final CustomAppView app;

  /// הכונן מוגן מפני כתיבה — אין הורדה אליו.
  final bool readOnly;

  /// `false` — אין אינטרנט במחשב הזה, ואין הורדה.
  final bool online;

  final VoidCallback onOpenDetail;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return StoreItemCard(
      icon: StoreIcon(
        imagePath: controller.iconPathOf(app.descriptor),
        placeholderIcon: FluentIcons.box_24_regular,
      ),
      // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
      title: app.descriptor.name,
      meta: StoreMetaLine(
        items: [
          for (final item in customAppMeta(context, app)) StoreMetaItem(item),
        ],
      ),
      description: app.descriptor.description ?? '',
      onTap: onOpenDetail,
      action: CustomAppAction(
        controller: controller,
        app: app,
        readOnly: readOnly,
        onInstall: onInstall,
        onLaunch: onLaunch,
        onDownload: onDownload,
        online: online,
      ),
      note: customAppNoteOf(context, app),
    );
  }
}

/// הפעולה האחת שנכונה עכשיו. עדכון שממתין קודם להפעלה — אחרת תוכנה
/// מותקנת לא הייתה מציעה את העדכון שכבר בכונן.
class CustomAppAction extends StatelessWidget {
  const CustomAppAction({
    super.key,
    required this.controller,
    required this.app,
    required this.readOnly,
    required this.onInstall,
    required this.onLaunch,
    required this.onDownload,
    this.primary = false,
    this.online = true,
  });

  final CustomAppsController controller;
  final CustomAppView app;
  final bool readOnly;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;

  /// בדף התוכנה — כפתור ראשי.
  final bool primary;

  /// `false` — אין אינטרנט, ולכן אין "הורדה לכונן".
  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final common = context.strings.common;
    final busy = controller.isBusy;

    Widget button(String text, VoidCallback? onPressed, {IconData? icon}) =>
        primary
            ? ActionButton.recommended(
                text: text,
                icon: icon,
                onPressed: onPressed,
              )
            : ActionButton.neutral(
                text: text,
                icon: icon,
                onPressed: onPressed,
              );

    if (app.canInstall && app.pending == CustomAppPending.newerOnDrive) {
      final version = app.storedInstaller?.version;
      return button(
        version == null ? common.install : t.updateToButton(version),
        busy ? null : onInstall,
      );
    }
    if (app.canLaunch) {
      return button(
        common.launch,
        busy ? null : onLaunch,
        icon: FluentIcons.open_20_regular,
      );
    }
    if (app.canInstall) return button(common.install, busy ? null : onInstall);
    // אין מה להתקין, אבל יש מאיפה להביא — וזה בדיוק מה שחסר לתוכנה הזו.
    if (app.descriptor.sourceKind == AppSourceKind.github &&
        !readOnly &&
        online) {
      final downloading = controller.downloadingId == app.descriptor.id;
      final onPressed =
          controller.downloadingId != null || controller.isDownloadingAll
              ? null
              : onDownload;
      return primary
          ? ActionButton.recommended(
              text: t.downloadButton,
              icon: FluentIcons.arrow_download_20_regular,
              isLoading: downloading,
              onPressed: onPressed,
            )
          : ActionButton.neutral(
              text: t.downloadButton,
              icon: FluentIcons.arrow_download_20_regular,
              isLoading: downloading,
              onPressed: onPressed,
            );
    }
    return const SizedBox.shrink();
  }
}
