import 'dart:async';

import 'package:flutter/foundation.dart';

/// מקטעי הגוף. כל מקטע נבנה בכניסה הראשונה אליו ונשאר בעץ.
enum ShellSection {
  home,
  otzaria,
  library,
  plugins,
  customApps,
  reports,
  settings,
  help,

  /// עדכון הכלי הזה — מהשורה שבתחתית הבית.
  launcher,
}

/// יעד בתוך גוף החלון. אין `Navigator.push`: שורת הכותרת נשארת תמיד.
sealed class ShellRoute {
  const ShellRoute();

  /// המקטע שהיעד שייך אליו — פרטי תוסף נשארים בתוך מקטע התוספים, כך
  /// שהרשימה שמתחתם נשמרת.
  ShellSection get section;
}

final class HomeRoute extends ShellRoute {
  const HomeRoute();

  @override
  ShellSection get section => ShellSection.home;

  @override
  bool operator ==(Object other) => other is HomeRoute;

  @override
  int get hashCode => (HomeRoute).hashCode;
}

final class SectionRoute extends ShellRoute {
  const SectionRoute(this.section);

  @override
  final ShellSection section;

  @override
  bool operator ==(Object other) =>
      other is SectionRoute && other.section == section;

  @override
  int get hashCode => Object.hash(SectionRoute, section);
}

final class PluginDetailRoute extends ShellRoute {
  const PluginDetailRoute(this.id);

  final String id;

  @override
  ShellSection get section => ShellSection.plugins;

  @override
  bool operator ==(Object other) =>
      other is PluginDetailRoute && other.id == id;

  @override
  int get hashCode => Object.hash(PluginDetailRoute, id);
}

final class CustomAppDetailRoute extends ShellRoute {
  const CustomAppDetailRoute(this.id);

  final String id;

  @override
  ShellSection get section => ShellSection.customApps;

  @override
  bool operator ==(Object other) =>
      other is CustomAppDetailRoute && other.id == id;

  @override
  int get hashCode => Object.hash(CustomAppDetailRoute, id);
}

/// ניהול התוכנות הנוספות — תחת ההגדרות, ולכן מאחורי אותו שער סייפר.
final class CustomAppsManageRoute extends ShellRoute {
  const CustomAppsManageRoute();

  @override
  ShellSection get section => ShellSection.settings;

  @override
  bool operator ==(Object other) => other is CustomAppsManageRoute;

  @override
  int get hashCode => (CustomAppsManageRoute).hashCode;
}

/// עריכת השאלות הנפוצות מתוך ההגדרות — דף העזרה מעל ההגדרות, כך שחזרה
/// מובילה אליהן.
final class FaqEditRoute extends ShellRoute {
  const FaqEditRoute();

  @override
  ShellSection get section => ShellSection.help;

  @override
  bool operator ==(Object other) => other is FaqEditRoute;

  @override
  int get hashCode => (FaqEditRoute).hashCode;
}

/// שכבת משימה (הורדה/עדכון) מעל המקטע. נסגרת רק ב-[ShellNavigator.endTask].
final class TaskRoute extends ShellRoute {
  const TaskRoute(this.section);

  /// המקטע שמתחת לשכבה.
  @override
  final ShellSection section;

  @override
  bool operator ==(Object other) =>
      other is TaskRoute && other.section == section;

  @override
  int get hashCode => Object.hash(TaskRoute, section);
}

/// שער כניסה למקטע (מצב הסייפר). תשובה סינכרונית משאירה את הניווט סינכרוני.
typedef ShellGate = FutureOr<bool> Function(ShellSection section);

/// מחסנית היעדים של הגוף. הבסיס תמיד [HomeRoute]; כל כניסה למקטע עוברת
/// ב-[canEnter], כך ששום נתיב (סרגל, אריח, שורת כותרת) לא עוקף אותו.
class ShellNavigator extends ChangeNotifier {
  ShellNavigator({this.canEnter});

  final ShellGate? canEnter;
  final List<ShellRoute> _stack = [const HomeRoute()];
  final Set<ShellSection> _built = {ShellSection.home};

  List<ShellRoute> get stack => List.unmodifiable(_stack);
  ShellRoute get current => _stack.last;
  ShellSection get section => current.section;

  bool get showsTask => current is TaskRoute;
  bool get canGoBack => _stack.length > 1 && !showsTask;

  bool isBuilt(ShellSection section) => _built.contains(section);
  Set<ShellSection> get builtSections => Set.unmodifiable(_built);

  /// מעבר למקטע מהסרגל או מאריח: המחסנית מתאפסת ל"בית ← מקטע".
  Future<bool> select(ShellSection section) => _enter(section, [
        const HomeRoute(),
        if (section != ShellSection.home) SectionRoute(section),
      ]);

  /// דף משנה בתוך מקטע (פרטי תוסף, ניהול תוכנות) — מעל "בית ← מקטע", כך
  /// שחזרה מובילה לרשימה.
  Future<bool> push(ShellRoute route) {
    switch (route) {
      case HomeRoute():
        return select(ShellSection.home);
      case SectionRoute(:final section):
        return select(section);
      case TaskRoute():
        showTask();
        return SynchronousFuture(showsTask);
      case FaqEditRoute():
        // ההגדרות נכנסות למחסנית, ולכן עוברות את השער שלהן — אחרת "חזרה"
        // הייתה נוחתת בהן בלי סיסמה.
        return _enter(
          route.section,
          [
            const HomeRoute(),
            const SectionRoute(ShellSection.settings),
            route,
          ],
          via: ShellSection.settings,
        );
      case PluginDetailRoute() ||
            CustomAppDetailRoute() ||
            CustomAppsManageRoute():
        return _enter(route.section, [
          const HomeRoute(),
          if (route.section != ShellSection.home) SectionRoute(route.section),
          route,
        ]);
    }
  }

  /// חזרה צעד אחד. לא פועלת בזמן משימה ולא מהבית.
  bool back() {
    if (!canGoBack) return false;
    _stack.removeLast();
    _changed();
    return true;
  }

  void showTask() {
    if (showsTask) return;
    _stack.add(TaskRoute(section));
    _changed();
  }

  void endTask() {
    if (!showsTask) return;
    _stack.removeLast();
    _changed();
  }

  Future<bool> _enter(
    ShellSection section,
    List<ShellRoute> routes, {
    ShellSection? via,
  }) async {
    if (showsTask) return false;
    for (final gated in [if (via != null) via, section]) {
      final allowed = canEnter?.call(gated) ?? true;
      if (!(allowed is bool ? allowed : await allowed) || showsTask) {
        return false;
      }
    }
    _replace(routes);
    return true;
  }

  void _replace(List<ShellRoute> routes) {
    if (listEquals(routes, _stack)) return;
    _stack
      ..clear()
      ..addAll(routes);
    _changed();
  }

  void _changed() {
    _built.add(section);
    notifyListeners();
  }
}
