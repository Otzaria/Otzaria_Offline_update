import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/store_kit/store_body.dart';
import 'package:launcher_app/src/widgets/screen_body.dart';
import 'package:launcher_app/src/widgets/sub_page_header.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final store in [false, true]) {
    for (final language in AppLanguage.values) {
      for (final size in [const Size(760, 560), const Size(1400, 900)]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
              'pinned header: store=$store ${language.code} '
              '$size scale=$scale', (tester) async {
            useViewSize(tester, size);
            final strings = stringsOf(language);
            var back = 0;
            var home = 0;
            await tester.pumpWidget(wrap(
              Scaffold(
                body: MediaQuery.withClampedTextScaling(
                  minScaleFactor: scale,
                  maxScaleFactor: scale,
                  child: SubPageHeaderScope(
                    header: SubPageHeader(
                      onBack: () => back++,
                      onHome: () => home++,
                      trail: [(label: strings.settings.title, onTap: null)],
                    ),
                    child: store
                        ? StoreBody(slivers: [
                            SliverList.builder(
                              itemCount: 60,
                              itemBuilder: (_, i) => SizedBox(
                                height: 100,
                                child: Text('$i'),
                              ),
                            ),
                          ])
                        : ScreenBody(children: [
                            for (var i = 0; i < 60; i++)
                              SizedBox(height: 100, child: Text('$i')),
                          ]),
                  ),
                ),
              ),
              language: language,
            ));
            await tester.pumpAndSettle();
            final button = find.byTooltip(strings.shell.backTooltip);
            final initial = tester.getRect(button);
            final scrollable = find.byType(Scrollable);
            await tester.drag(scrollable, const Offset(0, -1200));
            await tester.pumpAndSettle();
            expect(tester.state<ScrollableState>(scrollable).position.pixels,
                greaterThan(0));
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getRect(button), initial);
            expect(tester.getRect(scrollable).top,
                greaterThanOrEqualTo(initial.bottom));
            await tester.tap(button);
            await tester.tap(find.text(strings.shell.breadcrumbHome));
            expect(back, 1);
            expect(home, 1);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
