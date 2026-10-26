import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/faq_controller.dart';
import '../../settings/faq_customization.dart';
import '../../settings/safer_mode.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'faq_content.dart';
import 'faq_question_form.dart';

/// המתנה לפני שמירת שדות איש הקשר. שמירה בכל הקשה הייתה כתיבת קובץ להקשה,
/// על כונן נייד.
const Duration _contactSaveDelay = Duration(milliseconds: 500);

/// השאלות הנפוצות (`HelpPage`). תשובה אחת פתוחה בכל רגע; "עריכה" נכנסת
/// להסתרה, שאלות משלי ואיש הקשר, ובמצב סייפר דורשת סיסמה.
class FaqBody extends StatefulWidget {
  const FaqBody({
    super.key,
    required this.faq,
    this.saferMode,
    this.editRequests,
    this.active = true,
    this.readOnly = false,
  });

  final FaqController faq;

  /// שומר הסף של מצב הסייפר. `null` = אין נעילה (בדיקות).
  final SaferModeGate? saferMode;

  /// `true` מבקש להיכנס לעריכה ("עריכת השאלות הנפוצות" שבהגדרות); הגוף
  /// מאפס אותו כשטיפל. נקרא גם בבנייה הראשונה — הדף נבנה רק בכניסה אליו.
  final ValueNotifier<bool>? editRequests;

  /// הדף מוצג. הדף נשאר בעץ גם כשיוצאים ממנו, ולכן היציאה ממנו מסיימת את
  /// העריכה ושומרת — "?" אחר כך פותח את השאלות ולא את העריכה.
  final bool active;

  /// כונן מוגן: ההתאמות נשמרות במחשב הזה, וההסבר בעריכה אומר זאת.
  final bool readOnly;

  @override
  State<FaqBody> createState() => _FaqBodyState();
}

class _FaqBodyState extends State<FaqBody> {
  /// השאלה הפתוחה, לפי מזהה. `null` = הכול סגור.
  String? _openKey;
  bool _editing = false;

  late final TextEditingController _name =
      TextEditingController(text: widget.faq.value.contactName);
  late final TextEditingController _phone =
      TextEditingController(text: widget.faq.value.contactPhone);

  FaqCustomization get _custom => widget.faq.value;

  @override
  void initState() {
    super.initState();
    widget.faq.addListener(_onChange);
    widget.editRequests?.addListener(_onEditRequest);
    if (widget.editRequests?.value ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onEditRequest());
    }
  }

  @override
  void didUpdateWidget(FaqBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _editing) _finishEditing();
  }

  @override
  void dispose() {
    unawaited(widget.faq.flush());
    widget.faq.removeListener(_onChange);
    widget.editRequests?.removeListener(_onEditRequest);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onEditRequest() {
    final request = widget.editRequests;
    if (!mounted || request == null || !request.value) return;
    request.value = false;
    if (!_editing) unawaited(_toggleEditing());
  }

  void _scheduleContactSave() => widget.faq.updateDeferred(
        _custom.copyWith(contactName: _name.text, contactPhone: _phone.text),
        _contactSaveDelay,
      );

  /// יציאה מהעריכה: מה שהוקלד ועוד לא נשמר נכתב מיד.
  void _finishEditing() {
    unawaited(widget.faq.flush());
    setState(() {
      _editing = false;
      _openKey = null;
    });
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

  /// במצב סייפר הכניסה *לעריכה* נשאלת סיסמה — היציאה ממנה לא, ומי שכבר
  /// אומת בהרצה הזו אינו נשאל שוב.
  Future<void> _toggleEditing() async {
    if (_editing) return _finishEditing();
    final gate = widget.saferMode;
    if (gate != null && gate.isLocked) {
      final unlocked = await showSaferModePasswordDialog(
        context,
        storedPassword: gate.settings.settings.saferModePassword,
        hint: context.strings.saferMode.verifyFaqHint,
        confirmText: context.strings.saferMode.enterButton,
      );
      if (!unlocked || !mounted) return;
      gate.unlock();
    }
    setState(() {
      _editing = true;
      _openKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _head(context),
        ...(_editing ? _editor(context) : _reader(context)),
      ],
    );
  }

  Widget _head(BuildContext context) {
    final t = context.strings.faq;
    final cs = Theme.of(context).colorScheme;
    final locked = widget.saferMode?.isLocked ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? t.editTitle : t.title,
                style: AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                _editing
                    ? (widget.readOnly ? t.editIntroThisComputer : t.editIntro)
                    : t.intro,
                style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (_editing)
          ActionButton.recommended(
            key: const ValueKey('faq.edit'),
            text: t.editDoneButton,
            icon: FluentIcons.checkmark_24_regular,
            onPressed: () => unawaited(_toggleEditing()),
          )
        else
          ActionButton.ghost(
            key: const ValueKey('faq.edit'),
            text: t.editButton,
            icon: locked
                ? FluentIcons.lock_closed_24_regular
                : FluentIcons.edit_24_regular,
            onPressed: () => unawaited(_toggleEditing()),
          ),
      ],
    );
  }

  // ── מצב קריאה ─────────────────────────────────────────────────────────────

  List<Widget> _reader(BuildContext context) {
    final t = context.strings.faq;
    final groups = faqGroups(context.strings, custom: _custom);
    return [
      // רק למי שמילא פרטים, ובראש הדף: אדם שאפשר להתקשר אליו עוזר יותר מכל
      // תשובה כתובה. "אפשר לפנות אלינו" בלי לומר למי אינו עוזר לאיש.
      if (_custom.hasContact) ...[
        SectionLabel(t.contactTitle),
        _ContactCard(key: const ValueKey('faq.contact'), custom: _custom),
      ],
      for (final group in groups) ...[
        SectionLabel(group.title),
        for (final entry in group.entries)
          _FaqItem(
            entry: entry,
            isOpen: _openKey == entry.id,
            onTap: () => setState(
              () => _openKey = _openKey == entry.id ? null : entry.id,
            ),
          ),
      ],
    ];
  }

  // ── מצב עריכה ─────────────────────────────────────────────────────────────

  /// השאלות המובנות מוצגות כאן **בלי** סינון — אחרת אי אפשר היה להחזיר
  /// שאלה שהוסתרה. לכן `faqGroups` נקרא בלי `custom`.
  List<Widget> _editor(BuildContext context) {
    final t = context.strings.faq;
    return [
      for (final group in faqGroups(context.strings)) ...[
        SectionLabel(group.title),
        for (final entry in group.entries)
          _FaqItem(
            entry: entry,
            hidden: _custom.hiddenIds.contains(entry.id),
            actions: [
              _IconAction(
                key: ValueKey('faq-hide-${entry.id}'),
                hidden: _custom.hiddenIds.contains(entry.id),
                onPressed: () => unawaited(
                  widget.faq.update(_custom.toggleHidden(entry.id)),
                ),
              ),
            ],
          ),
      ],
      SectionLabel(t.myQuestionsTitle),
      if (_custom.extras.isEmpty)
        SectionEmptyNote(t.noExtrasYet)
      else
        for (var i = 0; i < _custom.extras.length; i++)
          _FaqItem(
            entry: FaqEntry(
              extraEntryId(i),
              _custom.extras[i].question,
              _custom.extras[i].answer,
            ),
            actions: [
              IconButton(
                key: ValueKey('faq-extra-edit-$i'),
                style: _toolStyle,
                tooltip: t.editQuestionTooltip,
                icon: const Icon(FluentIcons.edit_20_regular, size: 18),
                onPressed: () => unawaited(_editQuestion(i)),
              ),
              IconButton(
                key: ValueKey('faq-extra-delete-$i'),
                style: _toolStyle,
                tooltip: t.deleteQuestionTooltip,
                color: Theme.of(context).colorScheme.error,
                icon: const Icon(FluentIcons.delete_20_regular, size: 18),
                onPressed: () => unawaited(_deleteQuestion(i)),
              ),
            ],
          ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.neutral(
            text: t.addQuestionButton,
            icon: FluentIcons.add_24_regular,
            onPressed: () => unawaited(_addQuestion()),
          ),
        ),
      ),
      SectionLabel(t.contactTitle),
      _ContactFields(
        name: _name,
        phone: _phone,
        onChanged: _scheduleContactSave,
      ),
    ];
  }
}

/// שאלה אחת (`.faq-item`): כרטיס, שאלה 14 וחץ; פתוחה — מודגשת ותשובה מתחת.
/// במצב עריכה בלי חץ ובלי תשובה, ועם כלים בקצה.
class _FaqItem extends StatelessWidget {
  const _FaqItem({
    required this.entry,
    this.isOpen = false,
    this.onTap,
    this.hidden = false,
    this.actions,
  });

  final FaqEntry entry;
  final bool isOpen;
  final VoidCallback? onTap;
  final bool hidden;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.faq;
    final question = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  entry.question,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: isOpen ? FontWeight.w600 : FontWeight.w400,
                    color: hidden ? cs.onSurfaceVariant : cs.onSurface,
                  ),
                ),
                if (hidden)
                  StatusChip(
                    kind: StatusKind.locked,
                    label: t.hiddenLabel,
                    icon: FluentIcons.eye_off_16_regular,
                  ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 12),
            // חץ למטה/למעלה — אינו כיווני, ולכן `Icon` ולא `RtlIcon`.
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: AppTokens.animFast,
              child: Icon(
                FluentIcons.chevron_down_20_regular,
                size: 20,
                color: cs.outline,
              ),
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: onTap == null
                      ? question
                      : Semantics(
                          button: true,
                          expanded: isOpen,
                          child: FocusRing(
                            borderRadius: BorderRadius.zero,
                            offset: -3,
                            child: InkWell(
                              onTap: onTap,
                              overlayColor: AppSurfaces.stateLayer(cs.primary),
                              child: question,
                            ),
                          ),
                        ),
                ),
                if (actions case final tools?)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: tools),
                  ),
              ],
            ),
            if (isOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  entry.answer,
                  style: AppTextStyles.body.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// כלי שורה בעריכה (`.ibtn.sm`): 32, כדי ששורת עריכה לא תהיה גבוהה משורת קריאה.
final ButtonStyle _toolStyle = IconButton.styleFrom(
  fixedSize: const Size.square(32),
  minimumSize: const Size.square(32),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// הסתרה/הצגה של שאלה מובנית.
class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.hidden,
    required this.onPressed,
  });

  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.faq;
    return IconButton(
      style: _toolStyle,
      tooltip: hidden ? t.restoreTooltip : t.hideTooltip,
      icon: Icon(
        hidden ? FluentIcons.eye_20_regular : FluentIcons.eye_off_20_regular,
        size: 18,
      ),
      onPressed: onPressed,
    );
  }
}

/// איש הקשר בקריאה: שם וטלפון בשורה אחת.
class _ContactCard extends StatelessWidget {
  const _ContactCard({super.key, required this.custom});

  final FaqCustomization custom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = custom.contactName.trim();
    final phone = custom.contactPhone.trim();
    final phoneText = Text(
      phone,
      textDirection: TextDirection.ltr,
      style: AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant),
    );
    return RowsCard(
      children: [
        AppRow(
          leading: const IconTile(icon: FluentIcons.person_24_regular),
          title: name.isEmpty ? phone : name,
          titleDirection: name.isEmpty ? TextDirection.ltr : null,
          below: name.isNotEmpty && phone.isNotEmpty ? phoneText : null,
        ),
      ],
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
    final cs = Theme.of(context).colorScheme;
    Widget field(String label, TextEditingController c, Key key, bool ltr) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: AppTextStyles.sectionLabel
                  .copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Semantics(
              label: label,
              child: RtlTextField(
                key: key,
                controller: c,
                textDirection: ltr ? TextDirection.ltr : null,
                keyboardType: ltr ? TextInputType.phone : null,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        );
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final nameField = field(t.contactNameLabel, name,
                  const ValueKey('faq.contact.name'), false);
              final phoneField = field(t.contactPhoneLabel, phone,
                  const ValueKey('faq.contact.phone'), true);
              if (box.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [nameField, const SizedBox(height: 12), phoneField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: 12),
                  Expanded(child: phoneField),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            t.contactAutoSaveNote,
            style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
