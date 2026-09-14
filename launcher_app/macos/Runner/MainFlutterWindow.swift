import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // החלון נפתח בגודל אזור העבודה של המסך (בלי שורת התפריטים וה-Dock) —
    // המקבילה למה שה-runner של ווינדוס עושה ב-`Win32Window` (גודל לפי
    // work area + SW_SHOWMAXIMIZED). בלי זה נפתח כאן חלון בגודל שב-XIB,
    // שקטן מהמינימום שה-Dart מבקש (900x620) והתוכן נדחס בו.
    //
    // כאן ולא מ-Dart, מאותה סיבה: ה-runner מציג את החלון רק כשהפריים
    // הראשון מוכן, ולכן שינוי גודל לפני `runApp` מהבהב.
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      self.setFrame(visible, display: true)
    } else {
      self.setFrame(self.frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
