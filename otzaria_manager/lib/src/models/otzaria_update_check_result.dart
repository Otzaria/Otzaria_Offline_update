import 'otzaria_install_state.dart';
import 'otzaria_release.dart';

/// תוצאת בדיקת עדכון: מה מותקן כרגע (אם בכלל) מול מה זמין ב-GitHub.
class OtzariaUpdateCheckResult {
  const OtzariaUpdateCheckResult({
    required this.latestRelease,
    required this.currentState,
  });

  final OtzariaRelease latestRelease;

  /// null אם עדיין לא בוצעה אף התקנה על ידי הלאנצ'ר הזה.
  final OtzariaInstallState? currentState;

  /// true גם כשאין התקנה קודמת בכלל (currentState == null) — אז "צריך
  /// עדכון" פשוט אומר "צריך התקנה ראשונית".
  bool get updateAvailable =>
      currentState == null || currentState!.installedTagName != latestRelease.tagName;
}
