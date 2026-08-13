import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/stored_installer.dart';

/// תוכנה מותאמת אחת כפי שהיא יושבת על הדיסק: התיאור, ומה שכבר הורד עבורה.
class CustomAppEntry {
  const CustomAppEntry({required this.descriptor, this.installer});

  final AppDescriptor descriptor;

  /// קובץ ההתקנה השמור, או `null` כשעוד לא נוסף אחד. `null` הוא מצב תקין
  /// לגמרי — כך נראית תוכנה שהתוסף שלה הגיע אבל הקובץ עוד לא.
  final StoredInstaller? installer;

  bool get hasInstaller => installer != null;
}

/// המרשם של התוכנות המותאמות, תחת `<mirrorRoot>/apps/<id>/`.
///
/// **תיקייה אחת לכל תוכנה, ובה הכול** — התיאור וקובץ ההתקנה יחד. זו אינה
/// החלטה שרירותית: העתקת התיקייה הזו לבדה מעבירה תוכנה שלמה למישהו אחר,
/// וזו הדרך שבה משתמש אחד יפיץ לחברו תוכנה בלי שום שרת באמצע.
///
/// היושבת תחת המראה, כלומר תחת `OtzariaData` שליד קובץ ההרצה, ולכן היא
/// **נוסעת על הכונן** — המחשב המנותק אינו צריך שיתקינו לו את התוסף בנפרד.
class CustomAppStore {
  CustomAppStore({required this.mirrorRootDir});

  /// שורש המראה — אותו שורש שבו יושבות הספרייה, התוכנה והתוספים, כדי
  /// שהעתקה אחת ל-USB תעביר את כולם.
  final String mirrorRootDir;

  static const String _descriptorFileName = 'descriptor.json';
  static const String _installerMetaFileName = 'installer.json';

  String get appsDir => p.join(mirrorRootDir, 'apps');

  String dirFor(String id) => p.join(appsDir, id);

  String descriptorPathFor(String id) =>
      p.join(dirFor(id), _descriptorFileName);

  /// הנתיב המלא לקובץ ההתקנה השמור — מורכב בזמן ריצה משם הקובץ, ולא
  /// נקרא מהדיסק. ראו [StoredInstaller.fileName].
  String installerPathFor(String id, StoredInstaller installer) =>
      p.join(dirFor(id), installer.fileName);

  /// כל התוכנות הרשומות, ממוינות לפי שם. תיקייה פגומה מדולגת בשקט ואינה
  /// מפילה את הטעינה: תוסף אחד שנשבר לא ימנע מהמשתמש לראות את השאר.
  Future<List<CustomAppEntry>> loadAll() async {
    final dir = Directory(appsDir);
    if (!await dir.exists()) return const [];

    final entries = <CustomAppEntry>[];
    await for (final child in dir.list()) {
      if (child is! Directory) continue;
      final entry = await _loadEntry(p.basename(child.path));
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => a.descriptor.name.compareTo(b.descriptor.name));
    return entries;
  }

  Future<CustomAppEntry?> load(String id) => _loadEntry(id);

  Future<CustomAppEntry?> _loadEntry(String id) async {
    try {
      final file = File(descriptorPathFor(id));
      if (!await file.exists()) return null;
      final descriptor = AppDescriptor.parse(await file.readAsString());
      return CustomAppEntry(
        descriptor: descriptor,
        installer: await _loadInstaller(id),
      );
    } catch (_) {
      return null;
    }
  }

  Future<StoredInstaller?> _loadInstaller(String id) async {
    try {
      final meta = File(p.join(dirFor(id), _installerMetaFileName));
      if (!await meta.exists()) return null;
      final json = jsonDecode(await meta.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final installer = StoredInstaller.fromJson(json);
      // המטא-דאטה בלי הקובץ עצמו היא שקר — כך נראית תיקייה שהועתקה חלקית.
      if (!await File(installerPathFor(id, installer)).exists()) return null;
      return installer;
    } catch (_) {
      return null;
    }
  }

  /// רושם תוכנה חדשה. זורק כשכבר קיימת תוכנה עם אותו מזהה — עדכון תיאור
  /// קיים נעשה דרך [saveDescriptor], כדי ש"הוספה" לא תדרוס בשקט.
  Future<void> add(AppDescriptor descriptor) async {
    if (await load(descriptor.id) != null) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.appAlreadyRegistered(descriptor.name),
      );
    }
    await saveDescriptor(descriptor);
  }

  Future<void> saveDescriptor(AppDescriptor descriptor) async {
    await Directory(dirFor(descriptor.id)).create(recursive: true);
    await File(descriptorPathFor(descriptor.id))
        .writeAsString(descriptor.encode());
  }

  /// רושם קובץ התקנה שכבר הועתק לתיקיית התוכנה.
  Future<void> saveInstaller(String id, StoredInstaller installer) async {
    await Directory(dirFor(id)).create(recursive: true);
    await File(p.join(dirFor(id), _installerMetaFileName))
        .writeAsString(jsonEncode(installer.toJson()));
  }

  /// מסיר תוכנה מהמרשם, על קובץ ההתקנה שלה. **אינו נוגע בתוכנה המותקנת
  /// עצמה** — הסרה כאן פירושה "אל תנהל לי אותה יותר", לא "הסר אותה מהמחשב",
  /// והדיאלוג בממשק חייב לומר זאת.
  Future<void> remove(String id) async {
    final dir = Directory(dirFor(id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
