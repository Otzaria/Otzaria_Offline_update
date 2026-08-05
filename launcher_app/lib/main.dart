import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/screens/dashboard_screen.dart';
import 'src/services/app_logger.dart';
import 'src/theme/app_theme.dart';

void main() {
  // ה-logger נוצר בתוך ה-zone אבל נדרש גם למטפל השגיאות שלו — ולכן מוחזק
  // כאן, מחוץ. nullable כי שגיאה יכולה לקרות עוד לפני שהוא נבנה.
  AppLogger? logger;

  void report(String context, Object error, StackTrace? stackTrace) {
    // העתקה מקומית: `logger` הוא משתנה שנתפס ומשתנה, ולכן promotion ל-non-null
    // לא חל עליו ישירות.
    final log = logger;
    if (log != null) {
      log.error(context, error, stackTrace);
    } else {
      // עוד אין לאן לכתוב — לפחות שזה יגיע ל-stderr ולקונסולת הדיבאגר.
      debugPrint('$context (לפני אתחול הלוג): $error\n$stackTrace');
    }
  }

  // **כל** האתחול חייב לרוץ בתוך אותו zone שממנו נקרא `runApp`. קודם
  // `ensureInitialized()` נקרא מחוץ ל-`runZonedGuarded`, וזה הפיל assertion
  // של "Zone mismatch" בכל הרצת debug (ב-release ה-assertion לא קיים, ולכן
  // זה לא נראה שם) — Flutter דורש שאתחול ה-bindings ו-`runApp` יהיו באותו
  // zone, אחרת קונפיגורציה zone-specific מתנהגת באופן לא צפוי.
  //
  // בונוס: עכשיו גם כשלים באתחול עצמו (למשל `getApplicationSupportDirectory`
  // שנכשל) נתפסים ונרשמים, במקום להפיל את האפליקציה בשקט לפני שיש לוג.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final supportDir = await getApplicationSupportDirectory();
      final dataDir = p.join(supportDir.path, 'otzaria-launcher');
      logger = await AppLogger.init(dataDir);

      // תופס שגיאות שה-widgets framework עצמו זורק (למשל בתוך build/layout).
      FlutterError.onError = (details) {
        report(
          'FlutterError: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };

      runApp(LauncherApp(dataDir: dataDir));
    },
    // תופס שגיאות אסינכרוניות שלא נתפסו ע"י שום try/catch — רשת חיצונית
    // (defense in depth): גם אם ניצור בעתיד בטעות עוד קריסת isolate/async
    // שבורחת מהטיפול הרגיל, היא עדיין תיכתב ללוג במקום להיעלם בשקט.
    (error, stackTrace) => report('Uncaught zone error', error, stackTrace),
  );
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key, required this.dataDir});

  final String dataDir;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "לאנצ'ר אוצריא",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: DashboardScreen(dataDir: dataDir),
      ),
    );
  }
}
