import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

/// שתי חבילות גוזרות נתיבים מאותה **התקנה ניידת** של אוצריא:
/// `LibraryDbLocator` מאתר בה את `seforim.db`, ו-`InstalledPluginsScanner`
/// את התוספים. הן אינן תלויות זו בזו, ורק הלאנצ'ר רואה את שתיהן — ולכן
/// הבדיקה שהסימון ותיקיית הנתונים לא נפרדו יושבת כאן, בדיוק כמו
/// `process_names_test.dart`.
///
/// דריפט היה מייצר באג שקט: הספרייה מתעדכנת בכונן הנייד, והתוספים נסרקים
/// מ-`%APPDATA%` של מחשב אחר לגמרי.
void main() {
  test('סימון ההתקנה הניידת ותיקיית הנתונים זהים בשתי החבילות', () {
    expect(
      InstalledPluginsScanner.portableMarkerFileName,
      LibraryDbLocator.portableMarkerFileName,
    );
    expect(
      InstalledPluginsScanner.portableDataFolderName,
      LibraryDbLocator.portableDataFolderName,
    );
  });
}
