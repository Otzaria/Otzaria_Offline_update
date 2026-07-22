import 'package:equatable/equatable.dart';

/// מצב ההתקנה המנוהלת שנשמר מקומית (otzaria_install_state.json), כדי
/// שנדע בפעם הבאה מה מותקן ואיפה — בלי להסתמך על רישום Windows/registry.
class OtzariaInstallState extends Equatable {
  const OtzariaInstallState({
    required this.installedTagName,
    required this.installDir,
    required this.exePath,
  });

  factory OtzariaInstallState.fromJson(Map<String, dynamic> json) {
    return OtzariaInstallState(
      installedTagName: json['installedTagName'] as String,
      installDir: json['installDir'] as String,
      exePath: json['exePath'] as String,
    );
  }

  /// תג הגרסה שמותקנת כרגע בפועל (לפי מה שהותקן על ידינו).
  final String installedTagName;

  /// התיקייה המנוהלת שאליה הותקנה אוצריא (הועברה ל-installer דרך /DIR=).
  final String installDir;

  /// הנתיב המלא לקובץ ה-exe להפעלה, שהתגלה לאחר ההתקנה.
  final String exePath;

  Map<String, dynamic> toJson() => {
        'installedTagName': installedTagName,
        'installDir': installDir,
        'exePath': exePath,
      };

  @override
  List<Object?> get props => [installedTagName, installDir, exePath];
}
