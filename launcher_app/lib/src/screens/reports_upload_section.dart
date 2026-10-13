import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/error_reports_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

class ReportsUploadSection extends StatelessWidget {
  const ReportsUploadSection({
    super.key,
    required this.errorReports,
    required this.searchFeedback,
    required this.connection,
    required this.isUploadingAll,
    required this.busy,
    required this.onUpload,
    this.onStop,
  });

  final ErrorReportsController? errorReports;
  final SearchFeedbackController? searchFeedback;
  final bool? connection;
  final bool isUploadingAll;
  final bool busy;
  final Future<void> Function()? onUpload;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final listenable = Listenable.merge([
      if (errorReports != null) errorReports!,
      if (searchFeedback != null) searchFeedback!,
    ]);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final t = context.strings.errorReports;
        final reports = errorReports;
        final feedback = searchFeedback;
        final uploading = isUploadingAll ||
            (reports?.isUploading ?? false) ||
            (feedback?.isUploading ?? false);
        if (uploading) {
          final p = reports?.progress;
          final wait = p?.waitRemaining;
          final feedbackPhase =
              !(reports?.isUploading ?? false) && feedback?.isUploading == true;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTokens.spaceMD),
              InfoProgressRow(
                stage: feedbackPhase
                    ? t.uploadingFeedbackStage
                    : wait != null
                        ? t.uploadWaitingStage(
                            (wait.inMilliseconds / 1000).ceil(),
                          )
                        : t.uploadingStage(p?.done ?? 0, p?.total ?? 0),
                progress: feedbackPhase || p == null || p.total == 0
                    ? null
                    : p.done / p.total,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              ActionButton.warning(
                text: t.uploadStopButton,
                icon: FluentIcons.stop_24_regular,
                onPressed: () {
                  onStop?.call();
                  if (reports?.isUploading ?? false) reports!.stop();
                  if (feedback?.isUploading ?? false) feedback!.stop();
                },
              ),
            ],
          );
        }
        final total =
            (reports?.outboxCount ?? 0) + (feedback?.outboxCount ?? 0);
        if (total <= 0) return const SizedBox.shrink();
        if (connection != true) {
          return Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceMD),
            child: Text(
              connection == null
                  ? t.uploadPendingUnchecked(total)
                  : t.uploadPendingOffline(total),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceMD),
          child: ActionButton.neutral(
            text: t.uploadButton(total),
            icon: FluentIcons.arrow_upload_24_regular,
            onPressed: busy || onUpload == null ? null : () => onUpload!(),
          ),
        );
      },
    );
  }
}
