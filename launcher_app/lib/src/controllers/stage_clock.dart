/// שעון לשלב ארוך שאינו מדווח התקדמות כלל.
///
/// `quick_check` על מסד מלא חוסם דקות ואינו מדווח דבר, ולכן הטקסט קפא
/// והמסך נראה תקוע — בפורום נשאלנו על כך במפורש ("הוא מאמת מלא זמן, מה
/// זה?"). הזמן שחלף אינו אחוזים, אבל הוא עונה על השאלה שבאמת נשאלת: האם
/// התוכנה חיה. שלב שכן יודע לדווח אחוזים (אימות ה-hash במסלול הדלתא)
/// אינו עובר כאן.
///
/// השעון מחזיק את **שם** השלב, ולכן רצף דיווחים זהים אינו מאפס אותו.
class StageClock {
  StageClock({DateTime Function() now = DateTime.now}) : _now = now;

  final DateTime Function() _now;
  String? _base;
  DateTime? _start;

  bool get isRunning => _base != null;

  /// מתחיל מדידה לשלב [base]. מחזיר `true` רק כשזו התחלה חדשה — כך
  /// שהקורא מפעיל טיימר פעם אחת לשלב, ולא בכל דיווח.
  bool start(String base) {
    if (_base == base) return false;
    _base = base;
    _start = _now();
    return true;
  }

  void stop() {
    _base = null;
    _start = null;
  }

  /// שם השלב ולצידו `mm:ss` שחלפו. אסור לקרוא כשאינו רץ.
  String text(String Function(String stage, String elapsed) format) {
    final seconds = _now().difference(_start!).inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return format(_base!, '$minutes:$rest');
  }
}
