import 'package:flutter/material.dart';

/// שדה הטקסט היחיד שמותר להשתמש בו לקלט.
///
/// זו גרסה מצומצמת של `RtlTextField` של אוצריא: תיקוני מקשי החיצים,
/// ההבהוב ותפריט ההקשר של Flutter Desktop **לא** פורטו לכאן (עדיין אין
/// בלאנצ'ר שדה קלט אמיתי). כשיתווסף כזה — יש לפורט את המקור המלא מ-
/// `otzaria/lib/widgets/text/rtl_text_field.dart`.
///
/// הכיוון אינו נכפה יותר ל-RTL אלא נגזר מהשפה (ה-`Directionality` שסביב) —
/// אחרת חיפוש באנגלית היה נכתב מימין לשמאל.
class RtlTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// שורה אחת כברירת מחדל, כמו במקור. יותר מזה נדרש למי שמקליד פסקה — תשובה
  /// בהדרכה — ושם שדה בגובה שורה אינו קריא.
  final int minLines;
  final int maxLines;

  const RtlTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      textDirection: Directionality.of(context),
      textAlign: TextAlign.start,
      minLines: minLines,
      maxLines: maxLines,
    );
  }
}
