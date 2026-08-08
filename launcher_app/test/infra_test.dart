import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/progress_notifier.dart';
import 'package:launcher_app/src/services/app_logger.dart';

/// בדיקות לשתי תשתיות שהתנהגותן אינה נראית במסך: דילול דיווחי ההתקדמות,
/// וסדר/גודל הכתיבה ליומן הפעילות.
void main() {
  group('ProgressNotifier', () {
    test('סופר דיווחים רבים לכדי מעט הודעות, ומוסר את האחרון', () async {
      final notifier = _Counter();
      var notifications = 0;
      notifier.addListener(() => notifications++);

      // 1000 דיווחים באותו tick — כמו הורדה של 1GB בצ׳אנקים.
      for (var i = 1; i <= 1000; i++) {
        notifier.value = i;
      }

      // הראשון יוצא מיד; השאר מתקבצים.
      expect(notifications, 1);
      expect(notifier.lastSeen, 1);

      // אחרי חלון הדילול הערך האחרון נמסר — המד לא נשאר תקוע.
      await Future<void>.delayed(ProgressNotifier.interval * 2);
      expect(notifications, 2);
      expect(notifier.lastSeen, 1000);

      notifier.dispose();
    });

    test('דיווח אחרי dispose אינו מודיע ואינו זורק', () async {
      final notifier = _Counter();
      notifier.value = 1;
      notifier.value = 2; // משאיר טיימר תלוי
      notifier.dispose();

      await Future<void>.delayed(ProgressNotifier.interval * 2);
      // אין דרך "לתפוס" notifyListeners אחרי dispose חוץ מזה שהוא זורק —
      // הגעה לכאן בלי חריגה היא הבדיקה.
      expect(() => notifier.value = 3, returnsNormally);
    });
  });

  group('AppLogger', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('logger-test-');
      AppLogger.resetForTest();
    });
    tearDown(() async {
      AppLogger.resetForTest();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    File logFile() => File('${tmp.path}/logs/launcher.log');

    test('שורות שנרשמו באותו tick נכתבות בשלמותן ובסדר', () async {
      final logger = await AppLogger.init(tmp.path);
      for (var i = 0; i < 200; i++) {
        logger.info('שורה $i');
      }
      await logger.flush();

      final lines = logFile()
          .readAsLinesSync()
          .where((l) => l.contains('שורה '))
          .toList();
      expect(lines, hasLength(200));
      for (var i = 0; i < 200; i++) {
        expect(lines[i], endsWith('שורה $i'));
      }
    });

    test('maybeInstance הוא null לפני init ואינו זורק', () {
      expect(AppLogger.maybeInstance, isNull);
      expect(() => AppLogger.instance, throwsStateError);
    });

    test('קובץ שחרג מ-maxBytes מתגלגל ל-.1 ומתחיל מחדש', () async {
      final logger = await AppLogger.init(tmp.path);
      await logger.flush();

      // מנפחים את הקובץ ישירות ולא דרך הלוגר — כתיבת 2MB דרכו הייתה מציפה
      // את פלט הבדיקות (ב-debug כל שורה גם מודפסת) בלי להוסיף כיסוי.
      logFile().writeAsStringSync(
        'x' * (AppLogger.maxBytes + 1),
        mode: FileMode.append,
      );

      logger.info('אחרי הגלגול');
      await logger.flush();

      expect(File('${logFile().path}.1').existsSync(), isTrue);
      expect(logFile().lengthSync(), lessThan(AppLogger.maxBytes));
      expect(logFile().readAsStringSync(), contains('אחרי הגלגול'));
    });
  });
}

/// ChangeNotifier מינימלי שמדווח דרך [ProgressNotifier.notifyProgress].
class _Counter extends ChangeNotifier with ProgressNotifier {
  int _value = 0;
  int lastSeen = 0;

  set value(int next) {
    _value = next;
    notifyProgress();
  }

  _Counter() {
    addListener(() => lastSeen = _value);
  }
}
