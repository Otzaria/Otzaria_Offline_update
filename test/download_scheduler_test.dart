import 'dart:async';

import 'package:seforim_library_updater/src/services/download_scheduler.dart';
import 'package:test/test.dart';

void main() {
  group('DownloadScheduler', () {
    test('מריץ עד maxConcurrent במקביל, ולא יותר', () async {
      var running = 0;
      var peak = 0;
      final gates = List.generate(8, (_) => Completer<void>());

      final future = DownloadScheduler(maxConcurrent: 3).run<int>([
        for (var i = 0; i < 8; i++)
          () async {
            running++;
            if (running > peak) peak = running;
            await gates[i].future;
            running--;
            return i;
          },
      ]);

      // משחררים אחת-אחת: אחרי כל שחרור נכנסת הבאה בתור, והשיא לא אמור לעלות.
      for (final gate in gates) {
        await Future<void>.delayed(Duration.zero);
        gate.complete();
      }
      expect(await future, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(peak, 3);
    });

    test('מחזיר תוצאות בסדר המקורי גם כשהן מסתיימות בסדר אחר', () async {
      final results = await DownloadScheduler(maxConcurrent: 4).run<String>([
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'a';
        },
        () async => 'b',
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'c';
        },
      ]);
      expect(results, ['a', 'b', 'c']);
    });

    test('רשימה ריקה אינה שגיאה', () async {
      expect(await DownloadScheduler().run<int>(const []), isEmpty);
    });

    test('maxConcurrent קטן מ-1 נכפה ל-1', () {
      expect(DownloadScheduler(maxConcurrent: 0).maxConcurrent, 1);
      expect(DownloadScheduler(maxConcurrent: -5).maxConcurrent, 1);
    });

    test('כישלון זורק, ולא מתחיל משימות נוספות', () async {
      final started = <int>[];
      final future = DownloadScheduler(maxConcurrent: 1).run<int>([
        () async {
          started.add(0);
          throw StateError('boom');
        },
        () async {
          started.add(1);
          return 1;
        },
      ]);
      await expectLater(future, throwsA(isA<StateError>()));
      expect(started, [0]);
    });

    test('כישלון ממתין למשימות שכבר רצות לפני שהוא זורק', () async {
      // בלי ההמתנה הזו הורדה שנשארה רצה ממשיכה לכתוב לדיסק אחרי שהקורא
      // כבר ניקה אחריו — ראו MirrorDownloadUndo.
      var finishedSlow = false;
      final slow = Completer<void>();
      final future = DownloadScheduler(maxConcurrent: 2).run<int>([
        () async {
          await slow.future;
          finishedSlow = true;
          return 0;
        },
        () async => throw StateError('boom'),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(finishedSlow, isFalse);
      slow.complete();
      await expectLater(future, throwsA(isA<StateError>()));
      expect(finishedSlow, isTrue);
    });

    test('השגיאה הראשונה היא זו שנזרקת', () async {
      final future = DownloadScheduler(maxConcurrent: 1).run<int>([
        () async => throw const FormatException('first'),
        () async => throw StateError('second'),
      ]);
      await expectLater(future, throwsA(isA<FormatException>()));
    });
  });

  group('ByteProgressAggregator', () {
    test('מסכם משבצות של הורדות שונות למונה אחד', () {
      final reports = <({int downloaded, int? total})>[];
      final aggregator = ByteProgressAggregator(
        totalBytes: 300,
        onProgress: (downloaded, total) =>
            reports.add((downloaded: downloaded, total: total)),
      );

      final a = aggregator.slot();
      final b = aggregator.slot();
      a(50, 100);
      b(80, 200);
      a(100, 100);

      expect(reports.last, (downloaded: 180, total: 300));
    });

    test('משבצת אינה יורדת אחורה — אימות שרץ מאפס אינו מפיל את המד', () {
      var last = -1;
      final aggregator = ByteProgressAggregator(
        totalBytes: 100,
        onProgress: (downloaded, _) => last = downloaded,
      );
      final slot = aggregator.slot();
      slot(100, 100); // הקובץ כבר שלם
      slot(0, 100); // ואז אימות sha256 מתחיל מאפס
      slot(40, 100);
      expect(last, 100);
    });

    test('בלי totalBytes ידוע — מסכם את ה-total-ים שדווחו', () {
      int? lastTotal;
      final aggregator = ByteProgressAggregator(
        onProgress: (_, total) => lastTotal = total,
      );
      final a = aggregator.slot();
      final b = aggregator.slot();
      a(10, 100);
      // כל עוד יש משבצת בלי total ידוע, אין סכום לדווח.
      expect(lastTotal, isNull);
      b(10, 50);
      expect(lastTotal, 150);
    });

    test('total מתוקן כלפי מעלה כשההורדה חורגת מהאומדן', () {
      int? lastTotal;
      final aggregator = ByteProgressAggregator(
        totalBytes: 100,
        onProgress: (_, total) => lastTotal = total,
      );
      aggregator.slot()(140, null);
      expect(lastTotal, 140);
    });
  });
}
