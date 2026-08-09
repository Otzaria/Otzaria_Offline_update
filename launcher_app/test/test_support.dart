import 'dart:io';

/// מוחק תיקייה זמנית בסבלנות. בווינדוס קובץ הלוג יכול להישאר תפוס עוד רגע
/// אחרי הכתיבה האחרונה, ואז המחיקה נכשלת ומפילה בדיקה שכבר עברה.
Future<void> deleteTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// חוסם **כל** גישה לרשת בבדיקה. שימושי בשתי צורות: להוכיח שמסלול
/// בדיקה/התקנה עובד בלי רשת בכלל (AGENTS §5 — "אין נפילה לרשת"), ולדמות
/// "אין חיבור" בבדיקות הקלות (`checkOnline`) בלי לגעת ברשת אמיתית.
class NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _NoNetworkClient();
}

class _NoNetworkClient implements HttpClient {
  static const _failure = SocketException('אין חיבור (חסום בבדיקה)');

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(_failure);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      Future.error(_failure);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => Future.error(_failure);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => Future.error(_failure);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
