import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:seforim_library_updater/src/services/fast_sha256.dart';
import 'package:test/test.dart';

/// אוסף את ה-Digest מ-sink מוזרם, וסופר קריאות כדי לאמת את חוזה ה-sink.
class _Collector implements Sink<Digest> {
  Digest? value;
  int adds = 0;
  int closes = 0;

  @override
  void add(Digest data) {
    value = data;
    adds++;
  }

  @override
  void close() => closes++;
}

Uint8List _bytes(int length, [int seed = 7]) {
  final out = Uint8List(length);
  var x = seed;
  for (var i = 0; i < length; i++) {
    // גנרטור דטרמיניסטי — הבדיקה חייבת להיות חוזרת על עצמה.
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = x & 0xFF;
  }
  return out;
}

String _streamed(List<int> data, int chunkSize) {
  final collector = _Collector();
  final sink = FastSha256.start(collector);
  for (var i = 0; i < data.length; i += chunkSize) {
    final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
    sink.add(data.sublist(i, end));
  }
  sink.close();
  return collector.value!.toString();
}

void main() {
  // גדלים סביב גבול הבלוק (64), גבול ה-padding (56) וגבול החוצץ הפנימי (1MB).
  const sizes = <int>[
    0,
    1,
    55,
    56,
    63,
    64,
    65,
    1000,
    (1 << 20) - 1,
    1 << 20,
    (1 << 20) + 1,
    3 << 20,
  ];

  group('FastSha256 מסכים עם package:crypto', () {
    for (final size in sizes) {
      test('חד-פעמי, $size בתים', () {
        final data = _bytes(size);
        expect(FastSha256.convert(data).toString(),
            sha256.convert(data).toString());
      });
    }

    test('וקטור מוכר: "abc"', () {
      expect(
        FastSha256.convert(utf8.encode('abc')).toString(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('טקסט עברי עם BOM מוביל — בדיוק מה שה-hasher הלוגי מזרים', () {
      final data = utf8.encode('﻿בראשית ברא אלוהים');
      expect(
          FastSha256.convert(data).toString(), sha256.convert(data).toString());
    });
  });

  group('הזרמה', () {
    test('חלוקה לגושים אינה משנה את התוצאה', () {
      final data = _bytes(2 << 20, 99);
      final expected = sha256.convert(data).toString();
      for (final chunkSize in <int>[1, 7, 64, 4096, 1 << 20, 3 << 20]) {
        expect(_streamed(data, chunkSize), expected,
            reason: 'גוש של $chunkSize בתים');
      }
    });

    test('גוש גדול מהחוצץ הפנימי מוזרם במקטעים', () {
      // 1MB הוא גודל החוצץ; 2.5MB מכריח שלושה מקטעים בקריאה אחת.
      final data = _bytes((2 << 20) + (1 << 19), 5);
      final collector = _Collector();
      FastSha256.start(collector)
        ..add(data)
        ..close();
      expect(collector.value!.toString(), sha256.convert(data).toString());
    });

    test('קלט ריק לגמרי — sink שנסגר בלי שום add', () {
      final collector = _Collector();
      FastSha256.start(collector).close();
      expect(collector.value!.toString(),
          sha256.convert(const <int>[]).toString());
    });

    test('addSlice מכבד start/end', () {
      final data = _bytes(5000, 3);
      final collector = _Collector();
      FastSha256.start(collector)
        ..addSlice(data, 100, 4000, false)
        ..close();
      expect(collector.value!.toString(),
          sha256.convert(data.sublist(100, 4000)).toString());
    });

    test('addSlice עם isLast סוגר את ה-sink', () {
      final data = _bytes(300, 11);
      final collector = _Collector();
      FastSha256.start(collector).addSlice(data, 0, data.length, true);
      expect(collector.adds, 1);
      expect(collector.closes, 1);
      expect(collector.value!.toString(), sha256.convert(data).toString());
    });

    test('close חוזר אינו מפיק digest שני', () {
      final collector = _Collector();
      final sink = FastSha256.start(collector)..add(utf8.encode('אוצריא'));
      sink.close();
      sink.close();
      expect(collector.adds, 1);
    });

    test('add אחרי close נכשל במקום לכתוב לזיכרון משוחרר', () {
      final collector = _Collector();
      final sink = FastSha256.start(collector)..add(utf8.encode('אוצריא'));
      sink.close();
      // ב-`package:crypto` זה StateError; במסלול הנייטיבי החוצץ כבר שוחרר,
      // וכתיבה לתוכו הייתה שחיתות heap שקטה.
      expect(() => sink.add(utf8.encode('עוד')), throwsStateError);
    });

    test('dispose באמצע הזרמה משחרר, ואינו מפיק digest', () {
      final collector = _Collector();
      final sink = FastSha256.start(collector)..add(_bytes(5000, 7));
      sink.dispose();
      expect(collector.adds, 0);
      expect(collector.closes, 0);
      // אידמפוטנטי — הקוראים קוראים לו ב-`finally` גם אחרי close מוצלח.
      sink.dispose();
      sink.close();
      expect(collector.adds, 0);
    });

    test('dispose אחרי close אינו משנה את התוצאה', () {
      final data = _bytes(70000, 5);
      final collector = _Collector();
      final sink = FastSha256.start(collector)..add(data);
      sink.close();
      sink.dispose();
      expect(collector.adds, 1);
      expect(collector.value!.toString(), sha256.convert(data).toString());
    });

    test('List<int> שאינו Uint8List עובד גם כן', () {
      final data = List<int>.generate(3000, (i) => i & 0xFF);
      final collector = _Collector();
      FastSha256.start(collector)
        ..add(data)
        ..close();
      expect(collector.value!.toString(), sha256.convert(data).toString());
    });

    test('שני sinks במקביל אינם מזהמים זה את זה', () {
      final a = _bytes(70000, 1);
      final b = _bytes(90000, 2);
      final ca = _Collector();
      final cb = _Collector();
      final sa = FastSha256.start(ca);
      final sb = FastSha256.start(cb);
      // מזרימים לסירוגין — חוצץ native משותף בטעות היה נחשף כאן.
      for (var i = 0; i < 90000; i += 1000) {
        if (i < a.length) {
          sa.add(a.sublist(i, i + 1000 > a.length ? a.length : i + 1000));
        }
        sb.add(b.sublist(i, i + 1000 > b.length ? b.length : i + 1000));
      }
      sa.close();
      sb.close();
      expect(ca.value!.toString(), sha256.convert(a).toString());
      expect(cb.value!.toString(), sha256.convert(b).toString());
    });
  });

  test('המסלול הנייטיבי אכן בשימוש ב-Windows ו-macOS', () {
    // לינוקס נופלת ל-package:crypto בכוונה; בשתי הפלטפורמות שהאפליקציה
    // נשלחת אליהן זו רגרסיה שקטה אם המסלול הנייטיבי מפסיק להיטען.
    if (Platform.isWindows || Platform.isMacOS) {
      expect(FastSha256.isNativeAvailable, isTrue);
    } else {
      expect(FastSha256.isNativeAvailable, isFalse);
    }
  });
}
