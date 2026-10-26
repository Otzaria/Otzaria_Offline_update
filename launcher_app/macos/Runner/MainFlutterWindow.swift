import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // בהיר תמיד, כמו הממשק עצמו — בלי זה מסגרת המערכת מתכהה במצב כהה.
    self.appearance = NSAppearance(named: .aqua)

    // חלון בינוני, 1000x720, ממורכז באזור העבודה (קטן יותר אם האזור קטן).
    // כאן ולא מ-Dart: ה-runner מציג את החלון רק כשהפריים הראשון מוכן.
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      let width = min(1000, visible.width)
      let height = min(720, visible.height)
      let frame = NSRect(
        x: visible.minX + (visible.width - width) / 2,
        y: visible.minY + (visible.height - height) / 2,
        width: width,
        height: height)
      self.setFrame(frame, display: true)
    } else {
      self.setFrame(self.frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
