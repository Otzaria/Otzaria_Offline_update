import 'package:flutter/material.dart';

import '../../settings/faq_customization.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// מה שהוקלד בטופס. `showTwoActionsDialog` אינו מחזיר ערך משלו, ולכן התוצאה
/// נאספת לאובייקט משותף — כמו ב-`plugin_updates_dialog`.
class _FormDraft {
  _FormDraft(this.question, this.answer);

  String question;
  String answer;
}

/// הטופס להוספת שאלה או לעריכת שאלה שהמשתמש הוסיף. מחזיר את הרשומה, או
/// `null` אם בוטלה או אם נותרה חסרה.
Future<FaqUserEntry?> showFaqQuestionForm(
  BuildContext context, {
  FaqUserEntry? existing,
}) async {
  final t = context.strings.faq;
  final draft = _FormDraft(existing?.question ?? '', existing?.answer ?? '');

  final approved = await showTwoActionsDialog(
    context: context,
    title: existing == null ? t.formAddTitle : t.formEditTitle,
    confirmText: t.formSave,
    customContent: _FormFields(draft: draft),
  );
  if (!approved) return null;

  // ריק = אין מה לשמור. הודעה ולא שמירה שקטה של שאלה בלי תשובה, שהייתה
  // מופיעה בהדרכה כשורה מתה.
  if (draft.question.trim().isEmpty || draft.answer.trim().isEmpty) {
    UiSnack.showError(t.formIncompleteSnack);
    return null;
  }
  return FaqUserEntry(
    question: draft.question.trim(),
    answer: draft.answer.trim(),
  );
}

/// ה-controllers שייכים ל-widget ולא לפונקציה שמעליו: שחרור שלהם מיד עם
/// סגירת הדיאלוג הפיל את הבנייה, כי אנימציית היציאה עוד מציגה את השדות.
class _FormFields extends StatefulWidget {
  const _FormFields({required this.draft});

  final _FormDraft draft;

  @override
  State<_FormFields> createState() => _FormFieldsState();
}

class _FormFieldsState extends State<_FormFields> {
  late final TextEditingController _question =
      TextEditingController(text: widget.draft.question);
  late final TextEditingController _answer =
      TextEditingController(text: widget.draft.answer);

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.faq;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          RtlTextField(
            controller: _question,
            decoration: InputDecoration(labelText: t.formQuestionLabel),
            onChanged: (value) => widget.draft.question = value,
          ),
          const SizedBox(height: AppTokens.spaceMD),
          RtlTextField(
            controller: _answer,
            decoration: InputDecoration(labelText: t.formAnswerLabel),
            minLines: 3,
            maxLines: 6,
            onChanged: (value) => widget.draft.answer = value,
          ),
        ],
      ),
    );
  }
}
