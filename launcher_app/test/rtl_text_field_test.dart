import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/widgets/rtl_text_field.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    String text = 'אבג דהו זחט',
    int offset = 1,
    TextDirection? direction,
    AppLanguage language = AppLanguage.hebrew,
    bool externalController = true,
  }) async {
    tester.view.physicalSize = const Size(1920, 1020);
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.reset);
    final controller =
        externalController ? TextEditingController(text: text) : null;
    if (controller != null) addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: RtlTextField(
            controller: controller,
            textDirection: direction,
          ),
        ),
        language: language,
      ),
    );
    await tester.tap(find.byType(RtlTextField));
    await tester.pump();
    final effective = tester.widget<EditableText>(find.byType(EditableText));
    if (controller == null) effective.controller.text = text;
    effective.controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
    expect(
        MediaQuery.textScalerOf(tester.element(find.byType(RtlTextField)))
            .scale(1),
        1);
    return effective.controller;
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey arrow, {
    bool shift = false,
    LogicalKeyboardKey? modifier,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(arrow);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  for (final (arrow, expected) in [
    (LogicalKeyboardKey.arrowLeft, 2),
    (LogicalKeyboardKey.arrowRight, 0),
  ]) {
    testWidgets('חץ $arrow בעברית זז בכיוון החזותי ב-DPR 1.25', (tester) async {
      final controller = await pumpField(tester);
      final editable =
          tester.state<EditableTextState>(find.byType(EditableText));
      final before = editable.renderEditable
          .getLocalRectForCaret(controller.selection.extent)
          .left;
      await press(tester, arrow);
      expect(controller.selection.extentOffset, expected);
      final after = editable.renderEditable
          .getLocalRectForCaret(controller.selection.extent)
          .left;
      expect(
          after,
          arrow == LogicalKeyboardKey.arrowLeft
              ? lessThan(before)
              : greaterThan(before));
    }, variant: windows);
  }

  for (final (text, offset, expected) in [
    ('שלום hello עולם', 7, 8),
    ('פרק 12 פסוק', 5, 6),
    ('פרק 12,345 פסוק', 7, 8),
    ('שלום мир עולם', 6, 7),
  ]) {
    testWidgets('ימינה בתוך רצף LTR בטקסט מעורב: $text', (tester) async {
      final controller = await pumpField(tester, text: text, offset: offset);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.extentOffset, expected);
    }, variant: windows);
  }

  for (final (language, direction) in [
    (AppLanguage.english, null),
    (AppLanguage.hebrew, TextDirection.ltr),
  ]) {
    testWidgets('LTR נשמר בשפה $language ובכיוון $direction', (tester) async {
      final controller = await pumpField(tester,
          text: 'abc@example.com', language: language, direction: direction);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.extentOffset, 2);
      await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 1));
    }, variant: windows);
  }

  testWidgets('Shift מרחיב ומצמצם בחירה בעברית', (tester) async {
    final controller = await pumpField(tester);
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2));
    await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
  }, variant: windows);

  testWidgets('Shift ברצף מספרי שומר על כיוון הבחירה', (tester) async {
    final controller = await pumpField(tester, text: 'פרק 12 פסוק', offset: 5);
    await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(controller.selection,
        const TextSelection(baseOffset: 5, extentOffset: 6));
  }, variant: windows);

  testWidgets('חץ בלי Shift מכווץ בחירה לקצה שבכיוון החץ', (tester) async {
    final controller = await pumpField(tester);
    for (final (arrow, expected) in [
      (LogicalKeyboardKey.arrowRight, 0),
      (LogicalKeyboardKey.arrowLeft, 7),
    ]) {
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();
      await press(tester, arrow);
      expect(controller.selection, TextSelection.collapsed(offset: expected));
    }
  }, variant: windows);

  testWidgets('תנועה עם Shift מדלגת על אות וניקוד יחד', (tester) async {
    final controller = await pumpField(tester, text: 'אָב', offset: 0);
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(controller.selection.extentOffset, 2);
  }, variant: windows);

  testWidgets('שדה ללא controller חיצוני מקבל את אותו תיקון', (tester) async {
    final controller = await pumpField(tester, externalController: false);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.extentOffset, 2);
  }, variant: windows);

  for (final (platform, modifier) in [
    (TargetPlatform.windows, LogicalKeyboardKey.controlLeft),
    (TargetPlatform.macOS, LogicalKeyboardKey.altLeft),
  ]) {
    for (final shift in [false, true]) {
      testWidgets('מילה עם $modifier ו-Shift=$shift ב-$platform',
          (tester) async {
        final controller = await pumpField(tester, offset: 0);
        await press(tester, LogicalKeyboardKey.arrowLeft,
            shift: shift, modifier: modifier);
        expect(controller.selection.baseOffset, shift ? 0 : 3);
        expect(controller.selection.extentOffset, 3);
        controller.selection = const TextSelection.collapsed(offset: 7);
        await tester.pump();
        await press(tester, LogicalKeyboardKey.arrowRight,
            shift: shift, modifier: modifier);
        expect(controller.selection.baseOffset, shift ? 7 : 4);
        expect(controller.selection.extentOffset, 4);
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
}
