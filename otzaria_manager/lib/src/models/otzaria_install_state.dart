import 'package:equatable/equatable.dart';

/// מצב ההתקנה המנוהלת שנשמר מקומית (otzaria_install_state.json), כדי
/// שנדע בפעם הבאה מה מותקן ואיפה — בלי להסתמך על רישום Windows/registry
/// או על Launch Services של macOS.
class OtzariaInstallState extends Equatable {
  const OtzariaInstallState({
    required this.installedTagName,
    required this.installDir,
    required this.launchPath,
  });

  factory OtzariaInstallState.fromJson(Map<String, dynamic> json) {
    return OtzariaInstallState(
      installedTagName: json['installedTagName'] as String,
      installDir: json['installDir'] as String,
      // `exePath` הוא השם שנכתב בגרסאות קודמות של הלאנצ'ר (כשהיה Windows
      // בלבד) — נקרא גם הוא, כדי שמשתמש קיים לא "יאבד" את ההתקנה שלו
      // ויותקן לו מחדש בלי צורך אחרי עדכון הלאנצ'ר.
      launchPath: (json['launchPath'] ?? json['exePath']) as String,
    );
  }

  /// תג הגרסה שמותקנת כרגע בפועל (לפי מה שהותקן על ידינו).
  final String installedTagName;

  /// התיקייה המנוהלת שאליה הותקנה אוצריא (בווינדוס — הועברה ל-installer
  /// דרך /DIR=; ב-macOS — התיקייה שאליה חולצה חבילת ה-.app).
  final String installDir;

  /// הנתיב להפעלה שהתגלה לאחר ההתקנה: קובץ `.exe` בווינדוס, חבילת `.app`
  /// ב-macOS.
  final String launchPath;

  Map<String, dynamic> toJson() => {
        'installedTagName': installedTagName,
        'installDir': installDir,
        'launchPath': launchPath,
      };

  @override
  List<Object?> get props => [installedTagName, installDir, launchPath];
}
