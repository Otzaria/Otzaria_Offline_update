/// דוחות ומשוב כבויים רק כשגם תיקיות הנתונים אינן כתיבות: במראה נעולה
/// ([mirrorLocked]) הורדות כבויות אבל איסוף ממשיך. מקור אמת יחיד לכולם.
bool reportsBlockedFor({required bool readOnly, required bool mirrorLocked}) =>
    readOnly && !mirrorLocked;
