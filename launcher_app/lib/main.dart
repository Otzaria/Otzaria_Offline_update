import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/screens/dashboard_screen.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final dataDir = p.join(supportDir.path, 'otzaria-launcher');
  runApp(LauncherApp(dataDir: dataDir));
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
