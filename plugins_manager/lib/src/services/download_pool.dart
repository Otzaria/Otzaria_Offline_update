import 'dart:async';

/// מריץ את [tasks] כשעד [maxConcurrent] מהן רצות בו-זמנית, ומחכה לכולן.
///
/// **למה מקביליות דווקא כאן.** סנכרון החנות הוא עשרות קבצים *קטנים* —
/// תמונה, צילומי מסך וקובץ `.otzplugin` לכל תוסף — וכל אחד מהם משלם סיבוב
/// הלוך-חזור מלא לשרת. בטור, זמן ההמתנה הוא רוב הסנכרון; במקביל הוא נחלק.
/// זו גם הסיבה שאין כאן פיצול של קובץ בודד לכמה חיבורים: הקבצים קטנים מכדי
/// שזה יעזור (ומול GitHub זה גם לא אפשרי — ראו `DownloadScheduler` בחבילה
/// `seforim_library_updater`, שהיא המקבילה שם).
///
/// שגיאה במשימה עוצרת את *ההתחלה* של משימות נוספות, וממתינה לאלה שכבר רצות
/// לפני שהיא נזרקת. משימות שאינן זורקות כלל (כמו הורדות התוספים, שמדווחות
/// כשל כאזהרה) פשוט רצות עד הסוף.
Future<void> runPooled(
  List<Future<void> Function()> tasks, {
  required int maxConcurrent,
}) async {
  if (tasks.isEmpty) return;
  final limit = maxConcurrent < 1 ? 1 : maxConcurrent;

  var next = 0;
  Object? firstError;
  StackTrace? firstStack;

  Future<void> worker() async {
    while (firstError == null && next < tasks.length) {
      final index = next++;
      try {
        await tasks[index]();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        return;
      }
    }
  }

  final count = tasks.length < limit ? tasks.length : limit;
  await Future.wait([for (var i = 0; i < count; i++) worker()]);

  final error = firstError;
  if (error != null) Error.throwWithStackTrace(error, firstStack!);
}
