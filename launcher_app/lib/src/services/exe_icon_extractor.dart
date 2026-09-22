import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_logger.dart';

/// מריץ את סקריפט החילוץ ומחזיר את קוד היציאה. תפר לבדיקות — הסקריפט
/// עצמו מדבר עם ווינדוס ואי אפשר להריץ אותו בסוויטה.
typedef IconScriptRunner = Future<int> Function(
  String executable,
  List<String> arguments,
);

/// חילוץ אייקון מקובץ הרצה: מחזיר נתיב ל-PNG זמני, או `null`. הקונטרולר
/// מחזיק אחד כזה כדי שבדיקות לא יריצו PowerShell אמיתי.
typedef ExeIconExtraction = Future<String?> Function(String exePath);

/// חילוץ האייקון של קובץ הרצה לקובץ PNG.
///
/// **למה בכלל:** הרשומה של תוכנה נוספת נוצרת במחשב המקוון, שבו התוכנה
/// בדרך כלל אינה מותקנת — אבל קובץ ההתקנה כן שם, ומתקין של Inno או NSIS
/// נושא כמעט תמיד את האייקון של התוכנה עצמה. זה חוסך מהמשתמש לחפש
/// תמונה ברשת רק כדי שהכרטיס לא ייראה ריק.
///
/// ווינדוס בלבד: העבודה נעשית ב-PowerShell מול `PrivateExtractIcons`
/// (256×256, הגודל הגדול ביותר שיש בקובץ), עם נפילה חזרה ל-
/// `ExtractAssociatedIcon` שנותן 32×32. `flutter_svg` ואריזות תמונה
/// אינן בפרויקט, ולכן אין כאן פענוח PE משלנו.
abstract final class ExeIconExtractor {
  static bool get isSupported => Platform.isWindows;

  /// מחלץ את האייקון של [exePath] לקובץ PNG **זמני** ומחזיר את נתיבו, או
  /// `null` כשאין אייקון או שהחילוץ נכשל.
  ///
  /// הקובץ זמני בכוונה: מי שקורא מוסר אותו כמקור ל-`saveMedia`, שמעתיק
  /// אותו אל `media/` של התוכנה — אותו מסלול בדיוק כמו תמונה שנבחרה ביד.
  static Future<String?> extract(
    String exePath, {
    IconScriptRunner? runner,
  }) async {
    if (!isSupported) return null;
    if (!await File(exePath).exists()) return null;

    final dir = await Directory.systemTemp.createTemp('otzaria_icon_');
    final script = File(p.join(dir.path, 'extract_icon.ps1'));
    final out = p.join(dir.path, 'icon.png');

    try {
      await script.writeAsString(_script);
      final exitCode = await (runner ?? _run)('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Exe',
        exePath,
        '-Out',
        out,
      ]);

      final file = File(out);
      // קוד יציאה 1 הוא "לא נמצא אייקון" — מצב תקין לגמרי, ולא שגיאה.
      if (exitCode != 0 || !await file.exists()) return null;
      if (await file.length() == 0) return null;
      return out;
    } catch (e) {
      AppLogger.instance.warn('חילוץ האייקון מ-$exePath נכשל: $e');
      return null;
    }
  }

  static Future<int> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    return result.exitCode;
  }

  /// ⚠️ `PrivateExtractIcons` ולא `ExtractAssociatedIcon` כברירת מחדל:
  /// השני מחזיר 32×32 בלבד, והתמונה בדף התוכנה רחבה 340 — אייקון כזה
  /// נראה שם כמו כתם מטושטש.
  static const String _script = r'''
param([Parameter(Mandatory=$true)][string]$Exe, [Parameter(Mandatory=$true)][string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class OtzIconApi {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, int[] ids, int count, int flags);
  [DllImport("user32.dll")]
  public static extern bool DestroyIcon(IntPtr icon);
}
'@
function Save-Bitmap($icon, $path) {
  $bmp = $icon.ToBitmap()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}
$handles = New-Object IntPtr[] 1
$ids = New-Object int[] 1
$count = [OtzIconApi]::PrivateExtractIcons($Exe, 0, 256, 256, $handles, $ids, 1, 0)
if ($count -gt 0 -and $handles[0] -ne [IntPtr]::Zero) {
  $icon = [System.Drawing.Icon]::FromHandle($handles[0])
  Save-Bitmap $icon $Out
  $icon.Dispose()
  [void][OtzIconApi]::DestroyIcon($handles[0])
  exit 0
}
$assoc = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe)
if ($assoc -ne $null) { Save-Bitmap $assoc $Out; $assoc.Dispose(); exit 0 }
exit 1
''';
}
