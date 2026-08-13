// ה-stub מוסר את גרסת ה-payload שהוא נושא, והלאנצ'ר משווה אותה לשלו. זה
// מה שתופס `app-files` ישנה מתחת ל-exe חדש — עדכון שנקטע, או תיקייה שהועתקה
// בין מחשבים בלי כל הקבצים (הדיווח בפורום post/34063).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/self_update/launcher_install_layout.dart';
import 'package:launcher_app/src/self_update/payload_check.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:path/path.dart' as p;

void main() {
  const envVar = LauncherInstallLayout.payloadVersionEnvVar;

  PayloadMismatch? detect(Map<String, String> env, String running,
          {LauncherInstallLayout? layout}) =>
      PayloadCheck.detect(
        environment: env,
        runningVersion: running,
        layout: layout,
      );

  group('PayloadCheck.detect', () {
    test('גרסאות תואמות — אין תקלה', () {
      expect(detect({envVar: '0.1.9'}, '0.1.9'), isNull);
    });

    test('ה-stub נושא גרסה אחרת ממה שרץ — זו התקלה', () {
      final mismatch = detect({envVar: '0.1.9'}, '0.1.8');
      expect(mismatch, isNotNull);
      expect(mismatch!.stubVersion, '0.1.9');
      expect(mismatch.runningVersion, '0.1.8');
    });

    test('גם הכיוון ההפוך נחשב — exe ישן מעל payload חדש', () {
      expect(detect({envVar: '0.1.8'}, '0.1.9'), isNotNull);
    });

    test('בלי משתנה סביבה אין הכרזה על תקלה', () {
      // `flutter run`, בנייה לא ארוזה, או stub מגרסה שקדמה למשתנה — בכולם
      // אין ראיה, והכרזה על תקלה בלי ראיה גרועה מלא לבדוק.
      expect(detect(const {}, '0.1.8'), isNull);
      expect(detect({envVar: ''}, '0.1.8'), isNull);
    });

    test('המרקר שיימחק נלקח מהמבנה שאותר', () {
      final layout = LauncherInstallLayout(
        executablePath: p.join('E:', 'drive', 'Otzaria-Updates.exe'),
      );
      final mismatch = detect({envVar: '0.1.9'}, '0.1.8', layout: layout);
      expect(
        mismatch!.markerPath,
        p.join('E:', 'drive', LauncherInstallLayout.payloadDirName,
            LauncherInstallLayout.readyMarkerName),
      );
    });

    test('בלי מבנה מאותר אין מה למחוק, וזו אינה שגיאה', () {
      expect(detect({envVar: '0.1.9'}, '0.1.8')!.markerPath, isNull);
    });
  });

  group('PayloadCheck.requestReextract', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('payload_check'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('מוחק את המרקר, כדי שההרצה הבאה תחלץ מחדש', () async {
      final marker = File(p.join(temp.path, '.ready'))..writeAsStringSync('x');
      await PayloadCheck.requestReextract(PayloadMismatch(
        runningVersion: '0.1.8',
        stubVersion: '0.1.9',
        markerPath: marker.path,
      ));
      expect(marker.existsSync(), isFalse);
    });

    test('מרקר שאינו קיים אינו זורק', () async {
      await PayloadCheck.requestReextract(PayloadMismatch(
        runningVersion: '0.1.8',
        stubVersion: '0.1.9',
        markerPath: p.join(temp.path, 'nope', '.ready'),
      ));
    });
  });

  group('שורת הפתיחה של הלוג', () {
    test('נושאת את הגרסה שרצה בפועל', () {
      // בלעדיה אי אפשר לדעת מהלוג אם עדכון שהותקן באמת עלה.
      expect(AppLogger.startLine(version: '0.1.9'), contains('0.1.9'));
    });

    test('גרסת ה-stub נוספת רק כשהיא שונה', () {
      expect(
        AppLogger.startLine(version: '0.1.9', payloadVersion: '0.1.9'),
        isNot(contains('stub')),
      );
      expect(
        AppLogger.startLine(version: '0.1.8', payloadVersion: '0.1.9'),
        allOf(contains('0.1.8'), contains('0.1.9')),
      );
    });

    test('בלי גרסה — הנוסח הישן, בלי סוגריים ריקים', () {
      expect(AppLogger.startLine(), '--- launcher started ---');
    });
  });
}
