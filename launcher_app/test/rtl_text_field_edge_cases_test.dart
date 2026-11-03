import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/widgets/rtl_text_field.dart';

import 'test_harness.dart';
import 'visual/visual_fonts.dart';

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  Future<TextEditingController> field(
    WidgetTester tester,
    String text,
    int offset, {
    int maxLines = 1,
  }) async {
    tester.view.physicalSize = const Size(950, 700);
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: text);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(wrap(Scaffold(
      body: RtlTextField(
        controller: controller,
        focusNode: focus,
        maxLines: maxLines,
      ),
    )));
    focus.requestFocus();
    await tester.pump();
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
    return controller;
  }

  double caretX(WidgetTester tester, TextEditingController controller) => tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable
      .getLocalRectForCaret(TextPosition(
        offset: controller.selection.extentOffset,
        affinity: controller.selection.affinity,
      ))
      .left;

  for (final (name, text, offset) in [
    ('start of Latin run', 'אב abc גד', 3),
    ('end of Latin run', 'אב abc גד', 6),
    ('start of numeric run', 'פרק 12 פסוק', 4),
    ('end of numeric run', 'פרק 12 פסוק', 6),
    ('emoji inside Latin run', 'אב abc😀def גד', 6),
    ('Latin grapheme with accent', 'אב a\u0301bc גד', 3),
  ]) {
    for (final arrow in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      for (final shift in [false, true]) {
        testWidgets('$name: ${arrow.keyLabel}, Shift=$shift', (tester) async {
          final controller = await field(tester, text, offset);
          final before = caretX(tester, controller);
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(arrow);
          if (shift) {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.pump();
          final after = caretX(tester, controller);
          expect(
            after,
            arrow == LogicalKeyboardKey.arrowLeft
                ? lessThanOrEqualTo(before)
                : greaterThanOrEqualTo(before),
            reason: '$text: $offset → ${controller.selection.extentOffset}',
          );
          if (shift) expect(controller.selection.baseOffset, offset);
          expect(tester.takeException(), isNull);
        }, variant: windows);
      }
    }
  }

  for (final text in ['', 'אבג']) {
    testWidgets('arrows remain bounded for "$text"', (tester) async {
      final controller = await field(tester, text, 0);
      for (var i = 0; i < text.length + 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(controller.selection.extentOffset, 0);
      }
      controller.selection = TextSelection.collapsed(offset: text.length);
      for (var i = 0; i < text.length + 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(controller.selection.extentOffset, text.length);
      }
      expect(tester.takeException(), isNull);
    }, variant: windows);
  }

  for (final text in ['אב abc גד', 'פרק 12 פסוק', 'אב a\u0301bc😀 גד']) {
    for (final shift in [false, true]) {
      testWidgets('repeated arrows traverse "$text", Shift=$shift',
          (tester) async {
        final controller = await field(tester, text, 0);
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final boundary = CharacterBoundary(text);
        final positions = [
          for (var offset = 0; offset <= text.length; offset++)
            if (boundary.getLeadingTextBoundaryAt(offset) == offset)
              for (final affinity in TextAffinity.values)
                render
                    .getLocalRectForCaret(
                        TextPosition(offset: offset, affinity: affinity))
                    .left,
        ]..sort();
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        for (final (arrow, edge) in [
          (LogicalKeyboardKey.arrowLeft, positions.first),
          (LogicalKeyboardKey.arrowRight, positions.last),
        ]) {
          for (var step = 0; step < 3 * text.length; step++) {
            final before = caretX(tester, controller);
            if ((before - edge).abs() < 0.01) break;
            await tester.sendKeyEvent(arrow);
            await tester.pump();
            expect(
              caretX(tester, controller),
              arrow == LogicalKeyboardKey.arrowLeft
                  ? lessThan(before)
                  : greaterThan(before),
              reason: '$text, $arrow, step $step: ${controller.selection}',
            );
            final offset = controller.selection.extentOffset;
            expect(boundary.getLeadingTextBoundaryAt(offset), offset);
          }
          expect(caretX(tester, controller), closeTo(edge, 0.01));
        }
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          expect(controller.selection.baseOffset, 0);
        }
      }, variant: windows);
    }
  }

  for (final reversed in [false, true]) {
    for (final arrow in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      testWidgets(
          'mixed selection collapses visually: $arrow, reverse=$reversed',
          (tester) async {
        final controller = await field(tester, 'אב abc גד', 0);
        controller.selection = TextSelection(
          baseOffset: reversed ? 3 : 0,
          extentOffset: reversed ? 0 : 3,
        );
        await tester.pump();
        await tester.sendKeyEvent(arrow);
        await tester.pump();
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.extentOffset,
            arrow == LogicalKeyboardKey.arrowRight ? 0 : 3);
        if (arrow == LogicalKeyboardKey.arrowLeft) {
          expect(controller.selection.affinity, TextAffinity.upstream);
        }
      }, variant: windows);
    }
  }

  testWidgets('arrows cross hard line breaks in one press', (tester) async {
    final controller = await field(tester, 'אבג\nדהו', 3, maxLines: 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.extentOffset, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.extentOffset, 3);
  }, variant: windows);

  testWidgets('arrows cross Latin hard line breaks in an RTL field',
      (tester) async {
    final controller = await field(tester, 'abc\ndef', 3, maxLines: 4);
    controller.selection = const TextSelection.collapsed(
      offset: 3,
      affinity: TextAffinity.upstream,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.extentOffset, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.extentOffset, 3);
  }, variant: windows);

  for (final dpr in [1.25, 1.5]) {
    for (final shift in [false, true]) {
      testWidgets('Segoe UI mixed traversal, DPR=$dpr, Shift=$shift',
          (tester) async {
        await tester.runAsync(loadVisualFonts);
        const text = 'אב a\u0301bc😀 גד 12';
        final controller = await field(tester, text, 0);
        tester.view.devicePixelRatio = dpr;
        await tester.pump();
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        const boundary = CharacterBoundary(text);
        final positions = [
          for (var offset = 0; offset <= text.length; offset++)
            if (boundary.getLeadingTextBoundaryAt(offset) == offset)
              for (final affinity in TextAffinity.values)
                render
                    .getLocalRectForCaret(
                        TextPosition(offset: offset, affinity: affinity))
                    .left,
        ]..sort();
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        for (final (arrow, edge) in [
          (LogicalKeyboardKey.arrowLeft, positions.first),
          (LogicalKeyboardKey.arrowRight, positions.last),
        ]) {
          for (var step = 0; step < 3 * text.length; step++) {
            final before = caretX(tester, controller);
            if ((before - edge).abs() < 0.01) break;
            await tester.sendKeyEvent(arrow);
            await tester.pump();
            expect(
              caretX(tester, controller),
              arrow == LogicalKeyboardKey.arrowLeft
                  ? lessThan(before)
                  : greaterThan(before),
              reason: '$arrow, step $step: ${controller.selection}',
            );
            final offset = controller.selection.extentOffset;
            expect(boundary.getLeadingTextBoundaryAt(offset), offset);
            if (shift) expect(controller.selection.baseOffset, 0);
          }
          expect(caretX(tester, controller), closeTo(edge, 0.01));
        }
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, text);
        expect(tester.takeException(), isNull);
      }, variant: windows, skip: !Platform.isWindows);
    }
  }
}
