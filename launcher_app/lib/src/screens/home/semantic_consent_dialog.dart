import 'package:flutter/material.dart';

import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../reports/reports_page.dart' show showReportsDisclosure;

/// החלון שלפני "עדכון המחשב הזה" כשהחיפוש החכם שבכונן מחכה להסכמה.
/// `true` הסכמה, `false` המשך בלי, `null` — סגירה בלי תשובה (Esc, מחוץ לחלון).
Future<bool?> showSemanticConsentAskDialog(BuildContext context) {
  final t = context.strings.libraryDomain;
  final cs = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog.custom(
      key: ShellKeys.semanticAskDialog,
      title: t.semanticAskTitle,
      width: AppTokens.dialogWideWidth,
      customContent: Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.semanticAskIntro),
              const SizedBox(height: AppTokens.spaceMD),
              Text(t.semanticConsentTerms),
              const SizedBox(height: AppTokens.spaceSM),
              TextLink(
                key: ShellKeys.semanticAskWhatIsSent,
                text: context.strings.pages.repWhatIsSent,
                onTap: () => showReportsDisclosure(
                  dialogContext,
                  reports: false,
                  search: true,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              Text(
                t.semanticAskLater,
                style: AppTextStyles.small.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.ghost(
          key: ShellKeys.semanticAskDecline,
          text: t.semanticAskDecline,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        ActionButton.recommended(
          key: ShellKeys.semanticAskApprove,
          text: t.semanticAskApprove,
          // בלי מיקוד מוקדם: Enter אינו הסכמה לשליחת נתונים.
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
}
