import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/screens/dashboard_screen.dart';
import 'src/services/app_logger.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final dataDir = p.join(supportDir.path, 'otzaria-launcher');
  final logger = await AppLogger.init(dataDir);

  // תופס שגיאות שה-widgets framework עצמו זורק (למשל בתוך build/layout).
  FlutterError.onError = (details) {
    logger.error(
      'FlutterError: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
    FlutterError.presentError(details);
  };

  // תופס שגיאות אסינכרוניות שלא נתפסו ע"י שום try/catch — רשת חיצונית
  // (defense in depth): גם אם ניצור בעתיד בטעות עוד קריסת isolate/async
  // שבורחת מהטיפול הרגיל, היא עדיין תיכתב ללוג במקום להיעלם בשקט.
  runZonedGuarded(
    () => runApp(LauncherApp(dataDir: dataDir)),
    (error, stackTrace) => logger.error('Uncaught zone error', error, stackTrace),
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
