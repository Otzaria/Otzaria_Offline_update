import 'dart:convert';

import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'app_descriptor_id.dart';
import 'app_detect_rules.dart';
import 'app_source_kind.dart';
import 'github_source.dart';

/// תוכנה נוספת שהמשתמש הוסיף — מה שהטופס "הוספת תוכנה" ממלא.
///
/// **זה תיאור, לא קוד.** אין entrypoint, אין הרשאות ואין מנוע ריצה: מי
/// התוכנה, מאיפה מגיע קובץ ההתקנה, כיצד מתקינים אותו בשקט, וכיצד מזהים
/// מה כבר מותקן. נשמר כ-JSON תחת `mirror/apps/<id>/descriptor.json`.
class AppDescriptor {
  const AppDescriptor({
    required this.id,
    required this.name,
    required this.sourceKind,
    this.description,
    this.publisher,
    this.github,
    this.installDir,
    this.portableFile = false,
    this.detect = const AppDetectRules(),
    this.schemaVersion = currentSchemaVersion,
  });

  /// גרסת הפורמט שהקוד הזה יודע לקרוא. קובץ עם מספר גבוה יותר נדחה
  /// בהודעה מפורשת — עדיף מלנחש שדות שלא היו קיימים כשהוא נכתב.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;

  /// מזהה ייחודי, והוא גם **שם התיקייה** במראה ובמרשם — ראו
  /// [AppDescriptorId].
  final String id;

  /// השם שהמשתמש רואה. **תוכן, לא מלל של התוכנה** — אינו מתורגם, בדיוק
  /// כמו שמות התוספים שמגיעים מ-otzaria.org.
  final String name;

  /// תיאור קצר שהמשתמש כתב לעצמו — "מה התוכנה הזאת". מוצג בכרטיס. גם הוא
  /// תוכן ואינו מתורגם.
  final String? description;

  /// מי מפרסם את התוכנה. תוכן, אינו מתורגם.
  final String? publisher;

  final AppSourceKind sourceKind;

  /// פרטי הריפו — קיים אך ורק כש-[sourceKind] הוא
  /// [AppSourceKind.github]. במקור ידני אין מה לבדוק ברשת.
  final GithubSource? github;

  /// לאן להתקין. `null` = ברירת המחדל של ה-installer עצמו, וזו בדרך כלל
  /// הבחירה **הנכונה**: היא מעדכנת התקנה קיימת במקומה במקום ליצור שנייה
  /// לידה. אותו שיקול בדיוק כמו ב-`OtzariaManager.resolveDefaultInstallDir`.
  final String? installDir;

  /// הקובץ ששמור אינו מתקין אלא **התוכנה עצמה** — ההתקנה מעתיקה אותו לאן
  /// שהמשתמש יבחר, ואינה מריצה אותו.
  ///
  /// ⚠️ זה השדה היחיד על הקובץ שכן נשמר ברשומה, ולא במקרה: כל השאר
  /// (`CustomInstallerKind`) נגזר מהבייטים בזמן ההתקנה, אבל **את זה אי אפשר
  /// להריח** — exe נייד ומתקין של framework לא מוכר נראים זהים, ושניהם
  /// נופלים ל-`interactive`. ההרצה של קובץ נייד "כמתקין" רק מפעילה אותו
  /// מהכונן, והוא לעולם לא מגיע למחשב.
  final bool portableFile;

  final AppDetectRules detect;

  /// פענוח מטקסט JSON גולמי — נקודת הכניסה לקובץ `.otzupdate`.
  factory AppDescriptor.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.descriptorNotJson,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.descriptorNotJson,
      );
    }
    return AppDescriptor.fromJson(decoded);
  }

  factory AppDescriptor.fromJson(Map<String, dynamic> json) {
    final t = AppL10n.strings.customAppsDomain;

    final schema = json['schemaVersion'];
    // גרסה חסרה נחשבת 1 — קובץ שנכתב ביד בלי השדה עדיין קריא.
    final schemaVersion = schema is int ? schema : currentSchemaVersion;
    if (schemaVersion > currentSchemaVersion) {
      throw AppDescriptorException(
        t.descriptorUnsupportedSchema(schemaVersion, currentSchemaVersion),
      );
    }

    String required(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) {
        throw AppDescriptorException(t.descriptorMissingField(field));
      }
      return value.trim();
    }

    final id = required('id');
    if (!AppDescriptorId.isValid(id)) {
      throw AppDescriptorException(t.descriptorInvalidId(id));
    }

    // `install.kind` **אינו** נקרא יותר, גם כשהוא קיים ברשומה ישנה: סוג
    // ההתקנה נקבע מהקובץ עצמו בזמן ההתקנה, ולא ממה שנרשם פעם.
    final install = json['install'] as Map<String, dynamic>? ?? const {};

    final source = json['source'] as Map<String, dynamic>? ?? const {};
    // מקור חסר נחשב `manual`: קובץ ישן, מלפני שהיה מקור GitHub, מתכוון אליו.
    final sourceId = source['kind'] as String? ?? AppSourceKind.manual.id;
    final sourceKind = AppSourceKind.byId(sourceId);
    if (sourceKind == null) {
      throw AppDescriptorException(
        t.descriptorUnknownSourceKind(
            sourceId, AppSourceKind.allIds.join(', ')),
      );
    }

    GithubSource? github;
    if (sourceKind == AppSourceKind.github) {
      if (source['owner'] is! String || source['repo'] is! String) {
        throw AppDescriptorException(t.descriptorMissingField('source.repo'));
      }
      github = GithubSource.fromJson(source);
    }

    final rawInstallDir = install['dir'] as String?;
    String? optional(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    return AppDescriptor(
      schemaVersion: schemaVersion,
      id: id,
      name: required('name'),
      description: optional('description'),
      publisher: optional('publisher'),
      sourceKind: sourceKind,
      github: github,
      installDir: (rawInstallDir != null && rawInstallDir.trim().isNotEmpty)
          ? rawInstallDir.trim()
          : null,
      // רשומה שנכתבה לפני שהשדה היה קיים מתכוונת ל"קובץ התקנה", וזה גם
      // ברירת המחדל — ולכן אין כאן שבירת תאימות ואין קפיצת schemaVersion.
      portableFile: install['portable'] == true,
      detect: AppDetectRules.fromJson(
        json['detect'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        if (publisher != null) 'publisher': publisher,
        'source': {
          'kind': sourceKind.id,
          if (github case final source?) ...source.toJson(),
        },
        if (installDir != null || portableFile)
          'install': {
            if (installDir != null) 'dir': installDir,
            if (portableFile) 'portable': true,
          },
        if (!detect.isEmpty) 'detect': detect.toJson(),
      };

  AppDescriptor copyWith({
    String? name,
    AppDetectRules? detect,
  }) =>
      AppDescriptor(
        schemaVersion: schemaVersion,
        id: id,
        name: name ?? this.name,
        description: description,
        publisher: publisher,
        sourceKind: sourceKind,
        github: github,
        installDir: installDir,
        portableFile: portableFile,
        detect: detect ?? this.detect,
      );

  /// טקסט הקובץ כפי שהוא נכתב לדיסק — עם הזחה, כדי שיישאר קריא לבן אדם
  /// שפותח אותו כדי להבין מה נשמר לו על הכונן.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// קובץ תוסף פגום או לא נתמך. שם ייעודי כדי שהממשק יוכל להציג את ההודעה
/// כמות שהיא — היא כבר מתורגמת ומסבירה מה בדיוק לא בסדר.
class AppDescriptorException implements Exception {
  const AppDescriptorException(this.message);
  final String message;

  @override
  String toString() => message;
}
