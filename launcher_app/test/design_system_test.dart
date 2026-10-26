// בדיקות מבניות לרכיבי שפת העיצוב: המידות, הרדיוס והרוחבים של המוקאפ.
// אין כאן goldens — רק מה שאפשר למדוד בעץ.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  final he = stringsOf();

  Future<void> pump(WidgetTester tester, Widget child) async {
    useViewSize(tester, const Size(1000, 720));
    await tester.pumpWidget(wrap(Scaffold(body: Center(child: child))));
    await tester.pump();
  }

  group('ActionButton', () {
    testWidgets('גובה 32/40/44 לפי הגודל, ורדיוס 8', (tester) async {
      for (final (size, height) in [
        (ActionButtonSize.sm, 32.0),
        (ActionButtonSize.md, 40.0),
        (ActionButtonSize.lg, 44.0),
      ]) {
        await pump(
          tester,
          ActionButton.recommended(
            text: he.common.install,
            size: size,
            icon: FluentIcons.arrow_download_24_regular,
            onPressed: () {},
          ),
        );
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          height,
          reason: '$size',
        );
        final style =
            tester.widget<FilledButton>(find.byType(FilledButton)).style!;
        expect(style.shape?.resolve({}), AppTokens.roundedShape);
        expect(style.elevation?.resolve({}), 0);
      }
    });

    testWidgets('expand ממלא את הרוחב, ומושבת בצבעי המוקאפ', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 352,
          child: ActionButton.recommended(
            text: he.common.install,
            expand: true,
            onPressed: null,
          ),
        ),
      );
      expect(tester.getSize(find.byType(FilledButton)).width, 352);
      final style =
          tester.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(
        style.backgroundColor?.resolve({WidgetState.disabled}),
        AppPalette.light.disabledContainer,
      );
      expect(
        style.foregroundColor?.resolve({WidgetState.disabled}),
        AppPalette.light.disabledText,
      );
    });

    testWidgets('ה-tonal מתבהר בלבן, הראשי ב-onPrimary', (tester) async {
      await pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionButton.neutral(text: he.common.retry, onPressed: () {}),
            ActionButton.recommended(text: he.common.install, onPressed: () {}),
          ],
        ),
      );
      final buttons =
          tester.widgetList<FilledButton>(find.byType(FilledButton));
      final cs = AppThemeData.colorScheme;
      final tonal = buttons.first.style!.overlayColor!;
      final primary = buttons.last.style!.overlayColor!;
      expect(
        Color.alphaBlend(
          tonal.resolve({WidgetState.hovered})!,
          cs.secondaryContainer,
        ).toARGB32(),
        AppPalette.light.tonalHover.toARGB32(),
      );
      expect(
        Color.alphaBlend(
          primary.resolve({WidgetState.hovered})!,
          cs.primary,
        ).toARGB32(),
        AppPalette.light.primaryHover.toARGB32(),
      );
    });
  });

  testWidgets('StatusChip: גלולה בגובה 24 בכל סוג', (tester) async {
    for (final kind in StatusKind.values) {
      await pump(tester, StatusChip(kind: kind, label: he.common.upToDate));
      final chip = find.byType(StatusChip);
      expect(tester.getSize(chip).height, 24, reason: '$kind');
      final box = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      expect((box.decoration! as BoxDecoration).borderRadius, AppTokens.pill);
    }
  });

  testWidgets('AppCard ו-RowsCard: שטוחים, רדיוס 8, רצועה של 2', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 400,
        child: RowsCard(
          children: [
            SizedBox(key: Key('a'), height: 20),
            SizedBox(key: Key('b'), height: 20),
          ],
        ),
      ),
    );
    final gap = tester.getTopLeft(find.byKey(const Key('b'))).dy -
        tester.getBottomLeft(find.byKey(const Key('a'))).dy;
    expect(gap, 2);
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
    expect(clip.borderRadius, AppTokens.borderRadiusAll);
    // ריפוד 4 בראש ובתחתית הכרטיס.
    expect(tester.getSize(find.byType(RowsCard)).height, 20 + 2 + 20 + 8);
  });

  testWidgets('AppRow: גובה לפחות 56, ובלחיצה — חץ', (tester) async {
    var taps = 0;
    await pump(
      tester,
      SizedBox(
        width: 500,
        child: AppRow(
          title: he.settings.languageTitle,
          onTap: () => taps++,
          leading: const IconTile(
            icon: FluentIcons.globe_24_regular,
            size: IconTileSize.sm,
            tone: IconTileTone.quiet,
          ),
        ),
      ),
    );
    expect(
        tester.getSize(find.byType(AppRow)).height, greaterThanOrEqualTo(56));
    expect(tester.getSize(find.byType(IconTile)), const Size(32, 32));
    await tester.tap(find.byType(AppRow));
    expect(taps, 1);
  });

  testWidgets('OptionCard: לפחות 68, והנבחר בצבע cardSelected', (
    tester,
  ) async {
    await pump(
      tester,
      SizedBox(
        width: 460,
        child: OptionCard(
          icon: FluentIcons.search_24_regular,
          title: he.common.install,
          selected: true,
          onSelected: () {},
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(OptionCard)).height,
      greaterThanOrEqualTo(68),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(OptionCard),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppPalette.light.cardSelected);
    expect(material.borderRadius, AppTokens.borderRadiusAll);
  });

  testWidgets('AppProgressBar: 8 רגיל, 4 דק, ומילוי מינימלי 8', (tester) async {
    await pump(
      tester,
      const SizedBox(width: 352, child: AppProgressBar(value: 0)),
    );
    expect(tester.getSize(find.byType(AppProgressBar)).height, 8);
    final fill = tester.widget<Container>(
      find.descendant(
        of: find.byType(AppProgressBar),
        matching: find.byType(Container),
      ),
    );
    expect(fill.constraints?.maxWidth, 8);

    await pump(
      tester,
      const SizedBox(width: 352, child: AppProgressBar(thin: true)),
    );
    expect(tester.getSize(find.byType(AppProgressBar)).height, 4);
    // פס בלי ערך מונפש לנצח, ולכן מפנים אותו לפני סוף הבדיקה.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ResultBadge: טבעת 72 ודיסק 64', (tester) async {
    await pump(
      tester,
      const ResultBadge(
        kind: ResultBadgeKind.ok,
        icon: FluentIcons.checkmark_24_regular,
      ),
    );
    expect(tester.getSize(find.byType(ResultBadge)), const Size(72, 72));
  });

  testWidgets('TaskFrame: תחתית של 68 עם קו עליון', (tester) async {
    useViewSize(tester, const Size(1000, 720));
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: TaskFrame(
            start: ActionButton.ghost(text: he.common.close, onPressed: () {}),
            end: ActionButton.recommended(
              text: he.common.install,
              onPressed: () {},
            ),
            child: const SizedBox(height: 100),
          ),
        ),
      ),
    );
    final footer = find.ancestor(
      of: find.byType(Row).last,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    expect(tester.getSize(footer.first).height, 68);
    expect(tester.getBottomLeft(footer.first).dy, 720);
    // הראשי בקצה הסוף — בעברית משמאל.
    expect(
      tester.getCenter(find.byType(FilledButton)).dx,
      lessThan(tester.getCenter(find.byType(TextButton)).dx),
    );
  });

  testWidgets('StageRow: 60, ו-48 בחלון נמוך', (tester) async {
    for (final (compact, height) in [(false, 60.0), (true, 48.0)]) {
      await pump(
        tester,
        SizedBox(
          width: 460,
          child: StageRow(
            icon: FluentIcons.library_24_regular,
            title: he.common.install,
            state: StageState.waiting,
            compact: compact,
          ),
        ),
      );
      expect(tester.getSize(find.byType(StageRow)).height, height);
    }
  });

  testWidgets('SectionLabel, NoticeBanner, EmptyState ו-PathText נבנים', (
    tester,
  ) async {
    await pump(
      tester,
      SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionLabel(he.settings.groupGeneral),
            NoticeBanner(
              kind: NoticeKind.banner,
              leading: const IconTile(icon: FluentIcons.info_24_regular),
              title: he.common.updateAvailable,
              actions: [
                ActionButton.recommended(
                  text: he.common.update,
                  onPressed: () {},
                ),
              ],
            ),
            EmptyState(
              icon: FluentIcons.puzzle_piece_24_regular,
              title: he.common.emptyValue,
            ),
            const PathText(r'C:\Users\User\OtzariaData'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final path = tester.widget<Text>(find.text(r'C:\Users\User\OtzariaData'));
    expect(path.textDirection, TextDirection.ltr);
    expect(path.maxLines, 1);
  });

  testWidgets('AdvancedSection מקופל, ונפתח בלחיצה', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 600,
        child: AdvancedSection(
          title: he.guide.whatsNewButton,
          child: Text(he.common.install),
        ),
      ),
    );
    expect(find.text(he.common.install), findsNothing);
    await tester.tap(find.text(he.guide.whatsNewButton));
    await tester.pumpAndSettle();
    expect(find.text(he.common.install), findsOneWidget);
  });

  group('דו-שיח', () {
    Future<void> open(WidgetTester tester, Widget dialog) async {
      useViewSize(tester, const Size(1000, 720));
      // דו-שיח קודם באותה בדיקה נשאר פתוח — מפנים את העץ.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => dialog,
              ),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();
    }

    double dialogWidth(WidgetTester tester) => tester
        .getSize(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;

    testWidgets('336 לאישור, 440 עם תוכן משלו', (tester) async {
      await open(
        tester,
        AppDialog.twoActions(
          title: he.settings.resetTitle,
          content: he.settings.resetDialogContent,
        ),
      );
      expect(dialogWidth(tester), 336);

      await open(
        tester,
        AppDialog.singleAction(
          title: he.settings.resetTitle,
          customContent: const SizedBox(height: 40),
        ),
      );
      expect(dialogWidth(tester), 440);
    });

    testWidgets('אזהרה: הבטוח ממוקד, והפעולה המסוכנת בקצה', (tester) async {
      await open(
        tester,
        AppDialog.warning(
          title: he.settings.resetDialogTitle,
          content: he.settings.resetDialogContent,
          confirmText: he.settings.resetDialogConfirm,
        ),
      );
      final safe = tester.getCenter(find.byType(FilledButton)).dx;
      final danger = tester.getCenter(find.byType(TextButton).last).dx;
      // בעברית הקצה הוא השמאל.
      expect(danger, lessThan(safe));
    });

    testWidgets('אישור רגיל: הביטול ghost והאישור בקצה', (tester) async {
      await open(
        tester,
        AppDialog.twoActions(
          title: he.settings.resetDialogTitle,
          content: he.settings.resetDialogContent,
        ),
      );
      expect(
        find.widgetWithText(TextButton, he.common.cancel),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.byType(FilledButton)).dx,
        lessThan(
          tester
              .getCenter(find.widgetWithText(TextButton, he.common.cancel))
              .dx,
        ),
      );
    });
  });

  // `:focus-visible`: מיקוד מעכבר או מ-autofocus אינו צובע את הכפתור כלחוץ,
  // והטבעת (2 ב-primary, במרחק 2) מופיעה רק ממקלדת.
  group('מיקוד', () {
    setUp(FocusVisibility.debugReset);

    testWidgets('כפתור ברירת המחדל בדו-שיח נשאר בצבע primary', (tester) async {
      useViewSize(tester, const Size(1000, 720));
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppDialog.warning(
                  title: he.settings.resetDialogTitle,
                  content: he.settings.resetDialogContent,
                  confirmText: he.settings.resetDialogConfirm,
                ),
              ),
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      final button = find.byType(FilledButton);
      expect(
        Focus.of(tester.element(find.text(he.common.cancel))).hasFocus,
        isTrue,
      );

      final style = tester.widget<FilledButton>(button).style!;
      final cs = AppThemeData.colorScheme;
      expect(style.overlayColor!.resolve({WidgetState.focused}),
          Colors.transparent);
      expect(style.backgroundColor!.resolve({WidgetState.focused}), cs.primary);
      expect(style.side!.resolve({WidgetState.focused}), isNull);
      // שום הדגשה לא צוירה מעל הכפתור.
      expect(
        find.descendant(of: button, matching: find.byType(InkWell)),
        findsOneWidget,
      );
      expect(_inkHighlights(tester, button), isEmpty);
    });

    testWidgets('Tab מצייר טבעת ולא שכבה, ולחיצת עכבר מסירה', (tester) async {
      await pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionButton.recommended(text: 'a', onPressed: () {}),
            ActionButton.ghost(text: 'b', onPressed: () {}),
          ],
        ),
      );
      final cs = AppThemeData.colorScheme;
      ButtonStyle styleOf(String text) => tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(text),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          )
          .style!;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ring = styleOf('a').side!.resolve({WidgetState.focused})!;
      expect(
          (ring.color, ring.width, ring.strokeAlign), (cs.primary, 2.0, 3.0));
      expect(styleOf('a').overlayColor!.resolve({WidgetState.focused}),
          Colors.transparent);

      await tester.tap(find.text('b'));
      await tester.pump();
      expect(styleOf('b').side!.resolve({WidgetState.focused}), isNull);
    });

    testWidgets('FocusRing סביב InkWell: רק ממקלדת', (tester) async {
      await pump(
        tester,
        FocusRing(
          child: InkWell(
            onTap: () {},
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      CustomPaint paint() => tester.widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(FocusRing),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(paint().foregroundPainter, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(paint().foregroundPainter, isNotNull);
    });

    testWidgets('FocusRing: לא כשהמיקוד בפקד פנימי', (tester) async {
      await pump(
        tester,
        FocusRing(
          child: InkWell(
            onTap: () {},
            child: SizedBox(
              width: 120,
              height: 40,
              child: Align(
                child: InkWell(
                  key: const ValueKey('inner'),
                  onTap: () {},
                  child: const SizedBox(width: 20, height: 20),
                ),
              ),
            ),
          ),
        ),
      );
      CustomPaint paint() => tester.widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(FocusRing),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(paint().foregroundPainter, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.byKey(const ValueKey('inner')))).hasFocus,
        isTrue,
      );
      expect(paint().foregroundPainter, isNull);
    });
  });

  testWidgets('חזרה מצביעה ימינה בעברית, והפירור מתקדם שמאלה', (tester) async {
    for (final (language, back, crumb) in [
      (AppLanguage.hebrew, AxisDirection.right, AxisDirection.left),
      (AppLanguage.english, AxisDirection.left, AxisDirection.right),
    ]) {
      await tester.pumpWidget(
        wrap(
          Material(
            child: SubPageHeader(
              onBack: () {},
              onHome: () {},
              trail: const [(label: 'דף', onTap: null)],
            ),
          ),
          language: language,
        ),
      );
      final backIcon = find.descendant(
        of: find.byType(RtlIcon),
        matching: find.byType(Icon),
      );
      expect(drawnArrow(tester, backIcon), back, reason: '$language');
      expect(
        drawnArrow(
          tester,
          find.byIcon(FluentIcons.chevron_right_16_regular),
        ),
        crumb,
        reason: '$language',
      );
    }
  });

  testWidgets('פירור: בריחוף primary וקו תחתון', (tester) async {
    await pump(
      tester,
      SubPageHeader(
        onBack: () {},
        onHome: () {},
        trail: const [(label: 'דף', onTap: null)],
      ),
    );
    final home = find.text(he.shell.breadcrumbHome);
    TextStyle style() => tester.widget<Text>(home).style!;
    expect(style().decoration, isNot(TextDecoration.underline));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(home));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(style().color, AppThemeData.colorScheme.primary);
    expect(style().decoration, TextDecoration.underline);
  });

  group('שדה קלט', () {
    testWidgets('44 גובה, מסגרת outline, רקע לבן; בפוקוס primary ב-2', (
      tester,
    ) async {
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: RtlTextField(
            decoration: InputDecoration(labelText: he.common.install),
          ),
        ),
      );
      final cs = AppThemeData.colorScheme;
      expect(tester.getSize(find.byType(TextField)).height, 44);

      final theme = AppThemeData.light().inputDecorationTheme;
      expect(theme.filled, isTrue);
      expect(theme.fillColor, cs.surfaceContainerLowest);
      final enabled = theme.enabledBorder! as OutlineInputBorder;
      expect(enabled.borderRadius, AppTokens.borderRadiusAll);
      expect(enabled.borderSide.color, cs.outline);
      expect(enabled.borderSide.width, 1);
      final focused = theme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, cs.primary);
      expect(focused.borderSide.width, 2);
      expect(theme.contentPadding,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final decorator =
          tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(decorator.isFocused, isTrue);
    });

    test('התווית במנוחה בסגנון הטקסט, וצפה ב-600', () {
      final theme = AppThemeData.light().inputDecorationTheme;
      expect(theme.labelStyle!.fontSize, AppTextStyles.field.fontSize);
      expect(theme.labelStyle!.height, AppTextStyles.field.height);
      expect(theme.labelStyle!.fontWeight, isNot(AppTextStyles.semibold));
      expect(theme.floatingLabelStyle!.fontWeight, AppTextStyles.semibold);
      // ה-hint והטקסט באותה שורה, כדי שלא יקפצו בתחילת ההקלדה.
      expect(theme.hintStyle!.fontSize, AppTextStyles.field.fontSize);
      expect(theme.hintStyle!.height, AppTextStyles.field.height);
    });

    testWidgets('התווית מצוירת ב-13 כשהיא צפה וב-14 במנוחה', (tester) async {
      // הגודל המצויר: גודל הגופן כפול ההקטנה שהטרנספורם של התווית מחיל.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: RtlTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'תווית'),
          ),
        ),
      );
      double paintedHeight() {
        final label = find.text('תווית');
        final paragraph = tester.renderObject<RenderParagraph>(label);
        final scale = tester.getRect(label).width / paragraph.size.width;
        return paragraph.text.style!.fontSize! * scale;
      }

      expect(paintedHeight(), moreOrLessEquals(14, epsilon: 0.01));
      controller.text = 'טקסט';
      await tester.pumpAndSettle();
      expect(paintedHeight(), moreOrLessEquals(13, epsilon: 0.01));
    });

    testWidgets('שדה עם סמל לפני ואחרי נשאר 44', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: RtlTextField(
            decoration: InputDecoration(
              hintText: 'חיפוש',
              prefixIcon: Icon(FluentIcons.search_20_regular, size: 18),
              suffixIcon: Icon(FluentIcons.dismiss_20_regular, size: 18),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(TextField)).height, 44);
    });
  });
}

/// הדגשות ה-ink (ריחוף/מיקוד) שצוירו בתוך [button].
List<InkFeature> _inkHighlights(WidgetTester tester, Finder button) {
  final ink = Material.of(
    tester.element(find.descendant(of: button, matching: find.byType(InkWell))),
  );
  final features = (ink as dynamic).debugInkFeatures as List<InkFeature>?;
  return [
    for (final f in features ?? const <InkFeature>[])
      if (f is InkHighlight && f.color.a > 0) f,
  ];
}
