import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/widgets/coming_soon_card.dart';

void main() {
  testWidgets('ComingSoonCard מציג כותרת, תת-כותרת ותג "בקרוב"',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComingSoonCard(
            icon: Icons.extension_outlined,
            title: 'חנות התוספים',
            subtitle: 'ניהול והתקנת תוספים לאוצריא יתווסף כאן.',
          ),
        ),
      ),
    );

    expect(find.text('חנות התוספים'), findsOneWidget);
    expect(find.text('בקרוב'), findsOneWidget);
  });
}
