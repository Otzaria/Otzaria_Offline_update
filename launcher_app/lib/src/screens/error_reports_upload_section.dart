import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/error_reports_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

/// שורת דיווחי הטעויות בתוך כרטיס ההורדות: כפתור העלאה כשיש מה לשלוח,
/// ובזמן ההעלאה — התקדמות וכפתור עצירה. כשהתיבה ריקה אין כאן כלום.
class ErrorReportsUploadSection extends StatelessWidget {
  const ErrorReportsUploadSection({
    super.key,
    required this.controller,
    required this.onUpload,
  });

  final ErrorReportsController controller;
  final Future<void> Function()? onUpload;

  @override
  Widget build(BuildContext context) {
    // מאזין בעצמו: ההתקדמות מתעדכנת כל שנייה, ואין סיבה לבנות מחדש את הכרטיס.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = context.strings.errorReports;
        if (controller.isUploading) {
          final p = controller.progress;
          final wait = p?.waitRemaining;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTokens.spaceMD),
              InfoProgressRow(
                stage: wait != null
                    ? t.uploadWaitingStage((wait.inMilliseconds / 1000).ceil())
                    : t.uploadingStage(p?.done ?? 0, p?.total ?? 0),
                progress: p == null || p.total == 0 ? null : p.done / p.total,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              ActionButton.warning(
                text: t.uploadStopButton,
                icon: FluentIcons.stop_24_regular,
                onPressed: controller.stop,
              ),
            ],
          );
        }
        if (controller.outboxCount <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceMD),
          child: ActionButton.neutral(
            text: t.uploadButton(controller.outboxCount),
            icon: FluentIcons.arrow_upload_24_regular,
            onPressed: onUpload == null ? null : () => onUpload!(),
          ),
        );
      },
    );
  }
}
