import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/faq_controller.dart';
import '../../settings/faq_customization.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'faq_content.dart';
import 'faq_question_form.dart';

/// גובה מרבי לרשימת השאלות. הכותרת, שורת ההסבר וכפתור הסגירה נשארים מחוץ
/// לגליל, כדי שלא ייעלמו כשגוללים.
///
/// חצי מגובה החלון הוא התקרה השנייה, ולא קוסמטיקה: `AppDialog` מעביר את
/// `customContent` כילד לא-גמיש בעמודה, כלומר בגובה בלתי חסום, ולכן גובה
/// קבוע כאן היה גולש מהדיאלוג בחלון נמוך במקום לגלול.
const double _listMaxHeight = 420;

/// רוחב הדיאלוג — רחב מדיאלוג רגיל, כי כאן יש פסקאות ולא שורת אישור.
const double _dialogMaxWidth = 560;

/// המתנה לפני שמירת שדות הפרטים. שמירה בכל הקשה הייתה כתיבת קובץ להקשה,
/// על כונן נייד.
const Duration _contactSaveDelay = Duration(milliseconds: 500);

double _listHeight(BuildContext context) =>
    math.min(_listMaxHeight, MediaQuery.sizeOf(context).height / 2);

/// ההדרכה עצמה — נפתחת מהכפתור הצף שבפינה.
Future<void> showFaqDialog(
  BuildContext context, {
  required FaqController faq,
}) =>
    showSingleActionDialog(
      context: context,
      title: context.strings.faq.title,
      confirmText: context.strings.common.close,
      customContent: FaqBody(faq: faq),
    );

/// רשימת השאלות, מקובצת. תשובה אחת פתוחה בכל רגע — רשימה שכולה פתוחה היא
/// שבעה מסכי גלילה, ואי אפשר לסרוק בה את השאלות.
///
/// גלגל השיניים שבראש מחליף למצב עריכה: הסתרת שאלות, שאלות משלי, והפרטים
/// שבתחתית. הוא בכוונה לא בולט — רוב המשתמשים רק קוראים כאן.
class FaqBody extends StatefulWidget {
  const FaqBody({super.key, required this.faq});

  final FaqController faq;

  @override
  State<FaqBody> createState() => _FaqBodyState();
}

class _FaqBodyState extends State<FaqBody> {
  /// השאלה הפתוחה, כ"קבוצה.שאלה". `null` = הכול סגור.
  String? _openKey;
  bool _editing = false;

  late final TextEditingController _name =
      TextEditingController(text: widget.faq.value.contactName);
  late final TextEditingController _phone =
      TextEditingController(text: widget.faq.value.contactPhone);
  Timer? _contactSave;

  FaqCustomization get _custom => widget.faq.value;

  @override
  void initState() {
    super.initState();
    widget.faq.addListener(_onChange);
  }

  @override
  void dispose() {
    // הקלדה שטרם נשמרה בגלל ההשהיה — הדיאלוג נסגר, וזה הרגע האחרון לשמור.
    if (_contactSave?.isActive ?? false) {
      _contactSave!.cancel();
      unawaited(_saveContact());
    }
    widget.faq.removeListener(_onChange);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _saveContact() => widget.faq.update(
        _custom.copyWith(contactName: _name.text, contactPhone: _phone.text),
      );

  void _scheduleContactSave() {
    _contactSave?.cancel();
    _contactSave = Timer(_contactSaveDelay, () => unawaited(_saveContact()));
  }

  Future<void> _addQuestion() async {
    final entry = await showFaqQuestionForm(context);
    if (entry == null) return;
    await widget.faq.update(
      _custom.copyWith(extras: [..._custom.extras, entry]),
    );
  }

  Future<void> _editQuestion(int index) async {
    final entry = await showFaqQuestionForm(
      context,
      existing: _custom.extras[index],
    );
    if (entry == null) return;
    final extras = [..._custom.extras]..[index] = entry;
    await widget.faq.update(_custom.copyWith(extras: extras));
  }

  Future<void> _deleteQuestion(int index) async {
    final t = context.strings.faq;
    final approved = await showWarningDialog(
      context: context,
      title: t.deleteConfirmTitle,
      content: t.deleteConfirmContent,
    );
    if (!approved) return;
    final extras = [..._custom.extras]..removeAt(index);
    await widget.faq.update(_custom.copyWith(extras: extras));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.faq;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _editing ? t.editIntro : t.intro,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSM),
              IconButton(
                tooltip: _editing ? t.editDoneTooltip : t.editTooltip,
                icon: Icon(
                  _editing
                      ? FluentIcons.checkmark_24_regular
                      : FluentIcons.settings_24_regular,
                ),
                onPressed: () {
                  if (_editing) unawaited(_saveContact());
                  setState(() {
                    _editing = !_editing;
                    _openKey = null;
                  });
                },
              ),
            ],
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _listHeight(context)),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _editing ? _editor(context) : _reader(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── מצב קריאה ─────────────────────────────────────────────────────────────

  List<Widget> _reader(BuildContext context) {
    final t = context.strings.faq;
    final groups = faqGroups(context.strings, custom: _custom);

    return [
      for (var g = 0; g < groups.length; g++)
        SettingsCard(
          title: groups[g].title,
          children: [
            for (final entry in groups[g].entries)
              _FaqTile(
                entry: entry,
                isOpen: _openKey == entry.id,
                onTap: () => setState(
                  () => _openKey = _openKey == entry.id ? null : entry.id,
                ),
              ),
          ],
        ),
      // רק למי שמילא פרטים. "אפשר לפנות אלינו" בלי לומר למי אינו עוזר לאיש,
      // ולכן אין כאן נוסח ברירת מחדל בכלל.
      if (_custom.hasContact) ...[
        const SizedBox(height: AppTokens.spaceLG),
        _ContactNote(title: t.contactTitle, custom: _custom),
      ],
    ];
  }

  // ── מצב עריכה ─────────────────────────────────────────────────────────────

  /// השאלות המובנות מוצגות כאן **בלי** סינון — אחרת אי אפשר היה להחזיר
  /// שאלה שהוסתרה. לכן `faqGroups` נקרא בלי `custom`.
  List<Widget> _editor(BuildContext context) {
    final t = context.strings.faq;

    return [
      for (final group in faqGroups(context.strings))
        SettingsCard(
          title: group.title,
          children: [
            for (final entry in group.entries)
              _HideRow(
                entry: entry,
                isHidden: _custom.hiddenIds.contains(entry.id),
                onToggle: () => unawaited(
                    widget.faq.update(_custom.toggleHidden(entry.id))),
              ),
          ],
        ),
      SettingsCard(
        title: t.myQuestionsTitle,
        actions: [
          ActionButton.neutral(
            text: t.addQuestionButton,
            icon: FluentIcons.add_24_regular,
            onPressed: () => unawaited(_addQuestion()),
          ),
        ],
        children: [
          if (_custom.extras.isEmpty)
            _PlainRow(text: t.noExtrasYet)
          else
            for (var i = 0; i < _custom.extras.length; i++)
              _ExtraRow(
                index: i,
                entry: _custom.extras[i],
                onEdit: () => unawaited(_editQuestion(i)),
                onDelete: () => unawaited(_deleteQuestion(i)),
              ),
        ],
      ),
      SettingsCard(
        title: t.contactCardTitle,
        hint: t.contactCardHint,
        children: [
          _ContactFields(
            name: _name,
            phone: _phone,
            onChanged: _scheduleContactSave,
          ),
        ],
      ),
    ];
  }
}

/// שורת שאלה אחת. סגורה — כותרת בלבד; פתוחה — התשובה מתחתיה.
class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.entry,
    required this.isOpen,
    required this.onTap,
  });

  final FaqEntry entry;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: _rowPadding,
        child: AnimatedSize(
          duration: AppTokens.animFast,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _questionText(context, entry.question)),
                  const SizedBox(width: AppTokens.spaceSM),
                  // חץ למטה/למעלה — אינו כיווני, ולכן `Icon` ולא `RtlIcon`.
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: AppTokens.animFast,
                    child: Icon(
                      FluentIcons.chevron_down_20_regular,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (isOpen) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(entry.answer, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// שורה במצב עריכה: שאלה מובנית + מתג הסתרה.
class _HideRow extends StatelessWidget {
  const _HideRow({
    required this.entry,
    required this.isHidden,
    required this.onToggle,
  });

  final FaqEntry entry;
  final bool isHidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.faq;

    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _questionText(context, entry.question, dimmed: isHidden),
                if (isHidden) ...[
                  const SizedBox(height: AppTokens.spaceXS),
                  Text(
                    t.hiddenLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          IconButton(
            // מפתח לפי המזהה — כך הבדיקות מגיעות לשורה אחת מתוך שבע-עשרה בלי
            // לטייל בעץ.
            key: ValueKey('faq-hide-${entry.id}'),
            tooltip: isHidden ? t.restoreTooltip : t.hideTooltip,
            icon: Icon(
              isHidden
                  ? FluentIcons.eye_off_24_regular
                  : FluentIcons.eye_24_regular,
            ),
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

/// שורה במצב עריכה: שאלה שהמשתמש הוסיף, עם עריכה ומחיקה.
class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.index,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final FaqUserEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.faq;

    return Padding(
      padding: _rowPadding,
      child: Row(
        children: [
          Expanded(child: _questionText(context, entry.question)),
          const SizedBox(width: AppTokens.spaceSM),
          IconButton(
            key: ValueKey('faq-extra-edit-$index'),
            tooltip: t.editQuestionTooltip,
            icon: const Icon(FluentIcons.edit_24_regular),
            onPressed: onEdit,
          ),
          IconButton(
            key: ValueKey('faq-extra-delete-$index'),
            tooltip: t.deleteQuestionTooltip,
            icon: const Icon(FluentIcons.delete_24_regular),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// שדות השם והטלפון. השמירה מושהית ב-[_contactSaveDelay] ולא נעשית בכל הקשה.
class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.name,
    required this.phone,
    required this.onChanged,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.faq;

    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RtlTextField(
            controller: name,
            decoration: InputDecoration(labelText: t.contactNameLabel),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          RtlTextField(
            controller: phone,
            decoration: InputDecoration(labelText: t.contactPhoneLabel),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: _rowPadding,
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

/// "עדיין יש לכם שאלה?" + הפרטים שנרשמו. מוצג **רק** כשיש מה לרשום בו — ראו
/// [_FaqBodyState._reader].
class _ContactNote extends StatelessWidget {
  const _ContactNote({required this.title, required this.custom});

  final String title;
  final FaqCustomization custom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.faq;
    final name = custom.contactName.trim();
    final phone = custom.contactPhone.trim();

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SettingsCard.titleStyleOf(context)),
          const SizedBox(height: AppTokens.spaceXS),
          if (name.isNotEmpty) Text(name, style: theme.textTheme.bodyMedium),
          if (phone.isNotEmpty)
            Text(t.contactPhoneLine(phone), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

const EdgeInsets _rowPadding = EdgeInsets.symmetric(
  horizontal: AppTokens.spaceMD,
  vertical: AppTokens.spaceSM + AppTokens.spaceXS,
);

Widget _questionText(BuildContext context, String text, {bool dimmed = false}) {
  final theme = Theme.of(context);
  return Text(
    text,
    style: theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: dimmed ? theme.colorScheme.onSurfaceVariant : null,
    ),
  );
}
