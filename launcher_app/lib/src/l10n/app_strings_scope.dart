import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// מספק את [AppStrings] לעץ ה-widgets.
///
/// InheritedWidget ולא קריאה ישירה ל-`AppL10n.strings`: מסך שנבנה כ-`const`
/// לא נבנה מחדש כשההגדרות משתנות, ובלי התלות הזו החלפת שפה הייתה משאירה
/// חלקים מהמסך בשפה הקודמת עד לבנייה מחדש מסיבה אחרת.
///
/// מוצב ב-`MaterialApp.builder` — כלומר **מעל** ה-Navigator — כדי שגם
/// דיאלוגים ומסלולים שנפתחים מעליו ימצאו אותו.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'AppStringsScope חסר מעל ה-context הזה');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      strings.language != oldWidget.strings.language;
}

extension AppStringsContext on BuildContext {
  /// כל המלל של הממשק. ראו [AppStringsScope].
  AppStrings get strings => AppStringsScope.of(this);

  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
