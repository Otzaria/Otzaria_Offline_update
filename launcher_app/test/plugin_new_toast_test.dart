import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/plugins/plugin_new_toast.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

/// הטוסט "תוסף חדש בחנות" — הניסוח לפי הכמות, ושני הכפתורים שלו.
void main() {
  Widget toast({
    required int count,
    VoidCallback? onView,
    VoidCallback? onClose,
    AppLanguage language = AppLanguage.hebrew,
  }) =>
      wrap(
        Stack(children: [
          PluginNewToast(
            count: count,
            onView: onView ?? () {},
            onClose: onClose ?? () {},
          ),
        ]),
        language: language,
      );

  testWidgets('תוסף אחד: ניסוח יחיד', (tester) async {
    await tester.pumpWidget(toast(count: 1));
    await tester.pumpAndSettle();

    expect(find.text(stringsOf().plugins.newToastOne), findsOneWidget);
    expect(find.text(stringsOf().plugins.newToastView), findsOneWidget);
  });

  testWidgets('כמה תוספים: הכמות בניסוח, גם באנגלית', (tester) async {
    await tester.pumpWidget(toast(count: 3, language: AppLanguage.english));
    await tester.pumpAndSettle();

    final en = stringsOf(AppLanguage.english).plugins;
    expect(find.text(en.newToastMany(3)), findsOneWidget);
  });

  testWidgets('"צפה" ו-✕ קוראים לפעולות שלהם', (tester) async {
    var viewed = 0;
    var closed = 0;
    await tester.pumpWidget(toast(
      count: 2,
      onView: () => viewed++,
      onClose: () => closed++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(stringsOf().plugins.newToastView));
    await tester.tap(find.byTooltip(stringsOf().plugins.newToastClose));

    expect(viewed, 1);
    expect(closed, 1);
  });
}
