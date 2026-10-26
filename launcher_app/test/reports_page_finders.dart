import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';

import 'test_harness.dart';

/// כרטיס המצב בדף הדיווחים מציע "שליחה עכשיו" ל-[count] דיווחים: הכותרת
/// עם הספירה, והכפתור. בלי אחד מהם — לא נמצא כלום.
Finder sendOffer(int count) => _when(
      find.text(stringsOf().pages.repWaitingTitle(count)),
      find.byKey(ShellKeys.reportsSend),
    );

/// [count] דיווחים שמורים בכונן, ואין חיבור — הסבר בלי כפתור שליחה.
Finder storedOffline(int count) => _when(
      find.text(stringsOf().pages.repStoredTitle(count)),
      find.text(stringsOf().pages.repStoredBody),
    );

/// [count] דיווחים שמורים, ועוד לא נבדק חיבור.
Finder storedUnchecked(int count) => _when(
      find.text(stringsOf().pages.repStoredTitle(count)),
      find.text(stringsOf().pages.repUncheckedBody),
    );

Finder _when(Finder condition, Finder target) =>
    condition.evaluate().isEmpty ? find.byKey(const ValueKey('none')) : target;
