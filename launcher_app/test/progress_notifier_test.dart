import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/progress_notifier.dart';

/// המלכודת (AGENTS §5): `PatchDownloader` מדווח על כל צ׳אנק — עשרות אלפי
/// קריאות בהורדת מסד של 1GB. כל אחת מהן הפכה ל-`setState` על `AppShell`,
/// כלומר בנייה מחדש של כל עץ ה-widgets, ועלתה יותר CPU מההורדה עצמה.
/// שתי התכונות הנדרשות: **מעט** הודעות, ו**הערך האחרון תמיד נמסר**.
void main() {
  group('ProgressNotifier — דילול', () {
    test('חלון הדילול הוא 100ms, כלומר עד ~10 הודעות בשנייה', () {
      expect(ProgressNotifier.interval, const Duration(milliseconds: 100));
    });

    test('הצפה של 5000 דיווחים באותו tick = שתי הודעות בלבד', () {
      fakeAsync((async) {
        final notifier = _Counter();
        var notifications = 0;
        notifier.addListener(() => notifications++);

        for (var i = 1; i <= 5000; i++) {
          notifier.value = i;
        }

        // הראשונה יוצאת מיד — כדי שהמד לא יישאר ריק עד לחלון הבא.
        expect(notifications, 1);
        expect(notifier.lastSeen, 1);

        async.elapse(ProgressNotifier.interval);

        expect(notifications, 2);
        expect(notifier.lastSeen, 5000, reason: 'הערך האחרון חייב להימסר');
        // ולא נשאר טיימר תלוי שימשיך להעיר את העץ.
        expect(async.pendingTimers, isEmpty);

        notifier.dispose();
      });
    });

    test('גם המתנה ארוכה אינה מייצרת הודעה נוספת אחרי האחרונה', () {
      fakeAsync((async) {
        final notifier = _Counter();
        var notifications = 0;
        notifier.addListener(() => notifications++);

        notifier.value = 1;
        notifier.value = 2;
        async.elapse(const Duration(seconds: 5));

        expect(notifications, 2);
        expect(notifier.lastSeen, 2);

        notifier.dispose();
      });
    });

    test('שתי הצפות בזו אחר זו = שלוש הודעות, לא 2000', () {
      fakeAsync((async) {
        final notifier = _Counter();
        var notifications = 0;
        notifier.addListener(() => notifications++);

        for (var i = 1; i <= 1000; i++) {
          notifier.value = i;
        }
        async.elapse(ProgressNotifier.interval);
        for (var i = 1001; i <= 2000; i++) {
          notifier.value = i;
        }
        async.elapse(ProgressNotifier.interval);

        // 1 מיידית + הודעה מקובצת לכל הצפה. ההצפה השנייה מתחילה בתוך החלון
        // שנפתח בהודעה הקודמת, ולכן גם היא מתקבצת ולא יוצאת מיד.
        expect(notifications, 3);
        expect(notifier.lastSeen, 2000);

        notifier.dispose();
      });
    });

    test('dispose מבטל טיימר תלוי — ואין הודעה אחריו', () {
      fakeAsync((async) {
        final notifier = _Counter();
        var notifications = 0;
        notifier.addListener(() => notifications++);

        notifier.value = 1;
        notifier.value = 2; // משאיר טיימר תלוי
        notifier.dispose();

        async.elapse(ProgressNotifier.interval * 3);

        expect(notifications, 1);
        expect(async.pendingTimers, isEmpty);
        // דיווח מאוחר (callback של הורדה שנקטעה) אינו זורק.
        expect(() => notifier.value = 3, returnsNormally);
      });
    });
  });

  group('שינויי מצב אינם עוברים דרך הדילול', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('progress-'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('checkForUpdate מודיע מיד פעמיים — "בודק" ואז התוצאה', () async {
      final controller = OtzariaModuleController(dataDir: tempDir.path);
      var notifications = 0;
      controller.addListener(() => notifications++);

      // כל הריצה קצרה בהרבה מחלון הדילול; אם המצב היה עובר דרכו, היינו
      // רואים הודעה אחת במקום שתיים.
      await controller.checkForUpdate();

      expect(notifications, 2);
      expect(controller.status, OtzariaModuleStatus.needsDownload);

      controller.dispose();
    });
  });
}

/// ChangeNotifier מינימלי שמדווח דרך [ProgressNotifier.notifyProgress].
class _Counter extends ChangeNotifier with ProgressNotifier {
  _Counter() {
    addListener(() => lastSeen = _value);
  }

  int _value = 0;
  int lastSeen = 0;

  set value(int next) {
    _value = next;
    notifyProgress();
  }
}
