import 'dart:convert';
import 'dart:io';

import '../models/otzaria_install_state.dart';

/// שומר/טוען את קובץ ה-state המקומי שמתעד מה הותקן ואיפה. הרג'יסטרי משמש
/// לאיתור **התיקייה** בלבד ([WindowsInstallRegistry]) — הגרסה נקראת תמיד
/// מקובץ ההרצה עצמו, כי `DisplayVersion` משקף את מה שהמתקין רשם ולא את מה
/// שיושב על הדיסק.
///
/// הקובץ הוא נקודת פתיחה, **לא** מקור אמת: הוא יושב על הכונן הנייד ונוסע
/// בין מחשבים, ולכן כל קורא חייב לאמת אותו מול הדיסק —
/// `OtzariaManager._verifyStoredState`.
class OtzariaStateStore {
  const OtzariaStateStore(this.stateFilePath);

  final String stateFilePath;

  /// מחזיר null אם עדיין לא בוצעה אף התקנה על ידינו (אין קובץ state, או
  /// שהוא פגום/לא קריא — במקרה כזה מתייחסים לזה כ"אין התקנה ידועה" ולא
  /// זורקים, כדי שזרימת "אין עדכון ידוע -> תתקין" תמשיך לעבוד).
  Future<OtzariaInstallState?> load() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return OtzariaInstallState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(OtzariaInstallState state) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    // כותבים לקובץ זמני ואז מחליפים (rename), כדי לא להשאיר state.json
    // חצי-כתוב אם התהליך נקטע באמצע הכתיבה.
    final tmp = File('$stateFilePath.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()));
    await tmp.rename(stateFilePath);
  }
}
