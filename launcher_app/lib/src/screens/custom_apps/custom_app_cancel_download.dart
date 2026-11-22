import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';

/// "ביטול ההורדה" שמתחת לשורת ההתקדמות — בדף התוכנות ובדף של תוכנה אחת.
class CustomAppCancelDownloadButton extends StatelessWidget {
  const CustomAppCancelDownloadButton({super.key, required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ActionButton.ghost(
          key: const ValueKey('custom-app-cancel-download'),
          text: context.strings.customApps.cancelDownloadButton,
          icon: FluentIcons.dismiss_20_regular,
          onPressed:
              controller.cancelRequested ? null : controller.cancelDownload,
        ),
      );
}
