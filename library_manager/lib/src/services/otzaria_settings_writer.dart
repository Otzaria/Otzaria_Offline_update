import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'otzaria_settings_reader.dart';

/// כותב הגדרות של אוצריא במקומן; הקורא אחראי לוודא שאוצריא סגורה.
class OtzariaSettingsWriter {
  const OtzariaSettingsWriter();

  /// מכוון את הספרייה למסד; יצירת שורש מותרת רק בהתקנה שטרם הופעלה.
  Future<bool> pointLibraryAt({
    required String dataRootPath,
    required String dbPath,
    bool allowCreate = false,
  }) {
    if (!p.isAbsolute(dbPath)) return Future.value(false);
    return _write(dataRootPath, allowCreate, {
      OtzariaSettingsReader.keyLibraryPath: p.dirname(dbPath),
      OtzariaSettingsReader.keyLibraryFolderName: '',
    });
  }

  /// נכתב רק לאחר הסכמה מפורשת של המשתמש לתנאי איסוף נתוני האימון.
  Future<bool> grantSearchFeedbackConsent({
    required String dataRootPath,
    bool allowCreate = false,
  }) =>
      _write(dataRootPath, allowCreate, {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
      });

  Future<bool> _write(
    String dataRootPath,
    bool allowCreate,
    Map<String, Object> values,
  ) =>
      OtzariaSettingsReader.runExclusively(() async {
        // Hive מזהה קופסאות לפי שם בלבד; קופסה קיימת אינה בבעלותנו.
        if (Hive.isBoxOpen(OtzariaSettingsReader.boxName)) return false;
        final root = Directory(dataRootPath);
        if (!await root.exists()) {
          if (!allowCreate) return false;
          try {
            await root.create(recursive: true);
          } catch (_) {
            return false;
          }
        }
        Box<dynamic>? box;
        try {
          Hive.init(dataRootPath);
          box = await Hive.openBox<dynamic>(
            OtzariaSettingsReader.boxName,
            path: dataRootPath,
            // שחזור אוטומטי עלול לקצץ קובץ פגום של המשתמש.
            crashRecovery: false,
          );
          final expected =
              p.join(dataRootPath, OtzariaSettingsReader.boxFileName);
          if (box.path == null || !p.equals(box.path!, expected)) return false;
          // שני ערכים נכתבים יחד כדי למנוע זוג הגדרות חלקי.
          await box.putAll(values);
          return true;
        } catch (_) {
          return false;
        } finally {
          try {
            await box?.close();
          } catch (_) {}
        }
      });
}
