import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// `:focus-visible` של הדפדפן: טבעת המיקוד מוצגת רק כשהמשתמש עובד במקלדת.
/// ב-Flutter מיקוד מעכבר או מ-`autofocus` נראה זהה למיקוד מהמקלדת.
abstract final class FocusVisibility {
  static bool _keyboard = false;
  static bool _installed = false;

  /// האם הקלט האחרון היה מקש (ולא לחיצת עכבר או מגע).
  static bool get isKeyboard {
    ensureInstalled();
    return _keyboard;
  }

  /// מתחיל להאזין. מי שבודק רק כשהמיקוד משתנה קורא לזה מראש — אחרת המקש
  /// שהזיז את המיקוד כבר עבר.
  static void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _keyboard = true;
    return false;
  }

  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _keyboard = false;
  }

  /// בין בדיקות: ה-binding של הבדיקות מוחק את מטפלי המקלדת אחרי כל בדיקה.
  static void debugReset() {
    if (_installed) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    _installed = false;
    _keyboard = false;
  }
}
