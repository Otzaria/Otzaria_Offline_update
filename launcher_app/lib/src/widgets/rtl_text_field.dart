import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_exports.dart';

/// שדה הטקסט היחיד שמותר להשתמש בו לקלט.
/// ניווט החיצים והבחירה ב-RTL תואמים ל-`RtlTextField` של אוצריא.
class RtlTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// מסתיר את התווים — שדה סיסמה. ראו `SaferModePasswordDialog`.
  final bool obscureText;

  /// כיוון קבוע לתוכן שהוא LTR מעצם טבעו (כתובת דואר), כמו הכלל ב-`Text`.
  final TextDirection? textDirection;
  final TextInputType? keyboardType;
  final bool autofocus;

  /// שורה אחת כברירת מחדל, כמו במקור. יותר מזה נדרש למי שמקליד פסקה — תשובה
  /// בהדרכה — ושם שדה בגובה שורה אינו קריא.
  final int minLines;
  final int maxLines;
  final int? maxLength;

  const RtlTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.obscureText = false,
    this.textDirection,
    this.keyboardType,
    this.autofocus = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final direction = textDirection ?? Directionality.of(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      // בלי decoration אין InputDecorator, וה-theme לא מצייר מסגרת — השדה
      // נעלם על רקע הדיאלוג.
      decoration: decoration ?? const InputDecoration(),
      // 14 כמו `.field input`; ברירת המחדל של M3 היא 16.
      style: AppTextStyles.field,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      obscureText: obscureText,
      autofocus: autofocus,
      textDirection: direction,
      keyboardType: keyboardType,
      textAlign: TextAlign.start,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
    );
    if (direction != TextDirection.rtl) return field;

    final wordByAlt = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return CallbackShortcuts(
      bindings: {
        for (final right in [false, true])
          for (final shift in [false, true])
            for (final word in [false, true])
              SingleActivator(
                right
                    ? LogicalKeyboardKey.arrowRight
                    : LogicalKeyboardKey.arrowLeft,
                shift: shift,
                control: word && !wordByAlt,
                alt: word && wordByAlt,
              ): () => _handleArrowKey(
                    isVisualRight: right,
                    extendSelection: shift,
                    byWord: word,
                  ),
      },
      child: field,
    );
  }

  void _handleArrowKey({
    required bool isVisualRight,
    required bool extendSelection,
    required bool byWord,
  }) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;
    final editable = context.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return;
    final selection = editable.widget.controller.selection;
    if (!byWord) {
      final position = !selection.isCollapsed && !extendSelection
          ? _visualSelectionEdge(editable, isVisualRight)
          : _visualStep(editable, isVisualRight);
      if (position != null) {
        Actions.invoke(
          context,
          UpdateSelectionIntent(
            editable.widget.controller.value,
            extendSelection
                ? selection.extendTo(position)
                : TextSelection.fromPosition(position),
            SelectionChangedCause.keyboard,
          ),
        );
        return;
      }
    }
    final forward = _isRtlAtCaret(editable) ? !isVisualRight : isVisualRight;
    Actions.invoke(
      context,
      byWord
          ? ExtendSelectionToNextWordBoundaryIntent(
              forward: forward,
              collapseSelection: !extendSelection,
            )
          : ExtendSelectionByCharacterIntent(
              forward: forward,
              collapseSelection: !extendSelection,
            ),
    );
  }

  TextPosition _visualSelectionEdge(EditableTextState editable, bool right) {
    final selection = editable.widget.controller.selection;
    final base = editable.renderEditable.getLocalRectForCaret(selection.base);
    final extent =
        editable.renderEditable.getLocalRectForCaret(selection.extent);
    final extentIsRight = base.top == extent.top
        ? extent.left > base.left
        : extent.top < base.top;
    final edge = right == extentIsRight ? selection.extent : selection.base;
    final downstream = TextPosition(offset: edge.offset);
    return editable.renderEditable.getLocalRectForCaret(downstream) ==
            editable.renderEditable.getLocalRectForCaret(edge)
        ? downstream
        : edge;
  }

  TextPosition? _visualStep(EditableTextState editable, bool right) {
    final controller = editable.widget.controller;
    if (controller.text.isEmpty || !controller.selection.isValid) return null;
    final render = editable.renderEditable;
    // TextSelection.extent replaces affinity for a non-collapsed selection.
    final current = TextPosition(
      offset: controller.selection.extentOffset,
      affinity: controller.selection.affinity,
    );
    final caret = render.getLocalRectForCaret(current);
    final pixel = 1 / View.of(editable.context).devicePixelRatio;
    final hit = render.getPositionForPoint(render.localToGlobal(Offset(
      right ? caret.right + pixel : caret.left - pixel,
      caret.center.dy,
    )));
    final index = (hit.offset - (hit.affinity == TextAffinity.upstream ? 1 : 0))
        .clamp(0, controller.text.length - 1);
    final range = CharacterBoundary(controller.text).getTextBoundaryAt(index);
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    if (boxes.isEmpty) return null;
    final forward = boxes.first.direction == TextDirection.ltr ? right : !right;
    final position = TextPosition(
      offset: forward ? range.end : range.start,
      affinity: forward ? TextAffinity.upstream : TextAffinity.downstream,
    );
    final target = render.getLocalRectForCaret(position);
    if ((target.top - caret.top).abs() >= pixel ||
        (right ? target.left > caret.left : target.left < caret.left)) {
      return position;
    }
    final line = render.getLineAtOffset(current);
    final forwardAtCaret = _isRtlAtCaret(editable) ? !right : right;
    if (!forwardAtCaret && current.offset == line.start && line.start > 0) {
      return null;
    }
    final edge = TextPosition(offset: right ? line.start : line.end);
    final edgeCaret = render.getLocalRectForCaret(edge);
    if ((edgeCaret.top - caret.top).abs() >= pixel ||
        (right ? edgeCaret.left > caret.left : edgeCaret.left < caret.left)) {
      return edge;
    }
    // Only a real line transition may fall back to logical character movement.
    return (forwardAtCaret ? line.end < controller.text.length : line.start > 0)
        ? null
        : current;
  }

  bool _isRtlAtCaret(EditableTextState editable) {
    final controller = editable.widget.controller;
    final selection = controller.selection;
    final length = controller.text.length;
    if (!selection.isValid || length == 0) return true;
    final index = (selection.affinity == TextAffinity.downstream
            ? selection.extentOffset
            : selection.extentOffset - 1)
        .clamp(0, length - 1);
    final range = CharacterBoundary(controller.text).getTextBoundaryAt(index);
    // בחירה של חלק מגרפמה (למשל חצי emoji) אינה מחזירה תיבה.
    final boxes = editable.renderEditable.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    return boxes.firstOrNull?.direction != TextDirection.ltr;
  }
}
