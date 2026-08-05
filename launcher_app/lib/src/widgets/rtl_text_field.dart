import 'package:flutter/material.dart';

/// שדה טקסט RTL — הרכיב היחיד שמותר להשתמש בו לקלט טקסט.
///
/// זו גרסה מצומצמת של `RtlTextField` של אוצריא: תיקוני מקשי החיצים,
/// ההבהוב ותפריט ההקשר של Flutter Desktop **לא** פורטו לכאן (עדיין אין
/// בלאנצ'ר שדה קלט אמיתי). כשיתווסף כזה — יש לפורט את המקור המלא מ-
/// `otzaria/lib/widgets/text/rtl_text_field.dart`.
class RtlTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const RtlTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
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
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.start,
      maxLines: 1,
    );
  }
}
