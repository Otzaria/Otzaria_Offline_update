import 'package:otzaria_l10n/otzaria_l10n.dart';

/// ערוץ גרסאות של תוכנת אוצריא — ממופה ישירות לדגל `prerelease` של GitHub.
enum OtzariaReleaseChannel {
  /// release רגיל (`prerelease=false`).
  stable,

  /// pre-release (`prerelease=true`) — גרסה שאינה יציבה.
  prerelease;

  static OtzariaReleaseChannel fromPrerelease(bool isPrerelease) =>
      isPrerelease ? OtzariaReleaseChannel.prerelease : stable;

  /// תווית לתצוגה למשתמש.
  String get label => switch (this) {
        OtzariaReleaseChannel.stable => AppL10n.strings.appDomain.channelStable,
        OtzariaReleaseChannel.prerelease =>
          AppL10n.strings.appDomain.channelPrerelease,
      };
}

/// זוג פריטים לפי ערוץ — יציב ולא-יציב. משמש גם לגרסאות שנמצאו ברשת
/// ([OtzariaChannelReleases]) וגם לאלה שכבר יושבות במראה המקומית, כדי ששתי
/// השכבות ידברו באותם כללי בחירה.
///
/// [prerelease] מאוכלס **רק כשהוא חדש מ-[stable]** — pre-release ישן מהגרסה
/// היציבה אינו בחירה אמיתית, ואין טעם להוריד אותו.
class OtzariaChannelPair<T extends Object> {
  const OtzariaChannelPair({this.stable, this.prerelease});

  final T? stable;
  final T? prerelease;

  bool get isEmpty => stable == null && prerelease == null;

  /// שתי הגרסאות קיימות — רק אז מוצגת למשתמש בחירת ערוץ.
  bool get hasChoice => stable != null && prerelease != null;

  List<T> get all => [
        if (stable != null) stable!,
        if (prerelease != null) prerelease!,
      ];

  T? operator [](OtzariaReleaseChannel channel) =>
      channel == OtzariaReleaseChannel.stable ? stable : prerelease;

  /// הפריט לפי בחירת המשתמש, עם נפילה לערוץ השני כשהנבחר ריק — כדי
  /// שהעדפה "לא יציבה" לא תשאיר בלי כלום כשאין pre-release חדש יותר.
  T? select({required bool preferPrerelease}) =>
      preferPrerelease ? (prerelease ?? stable) : (stable ?? prerelease);

  /// הערוץ שאליו שייך [select] בפועל — לתצוגה ("מותקנת הגרסה הלא-יציבה").
  OtzariaReleaseChannel? selectedChannel({required bool preferPrerelease}) {
    final chosen = select(preferPrerelease: preferPrerelease);
    if (chosen == null) return null;
    return identical(chosen, prerelease)
        ? OtzariaReleaseChannel.prerelease
        : OtzariaReleaseChannel.stable;
  }
}
