import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';

/// האייקון וצילומי המסך של תוכנה נוספת, תחת `apps/<id>/media/`.
///
/// **יושבים בתיקיית התוכנה ולא במקום מרכזי** — מאותה סיבה שקובץ ההתקנה
/// יושב שם: העתקת התיקייה הזו לבדה מעבירה תוכנה שלמה, עם התמונות שלה,
/// למישהו אחר בלי שום שרת באמצע.
class CustomAppMedia {
  const CustomAppMedia({required this.appDir});

  /// תיקיית התוכנה — `CustomAppStore.dirFor(id)`.
  final String appDir;

  static const String dirName = 'media';

  /// מה שמותר להעתיק לכאן. התמונות מוצגות ב-`Image.file`, וקובץ שאינו
  /// תמונה היה מגיע לממשק כריבוע שבור ולא כשגיאה.
  static const Set<String> allowedExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  String get dirPath => p.join(appDir, dirName);

  /// הנתיב המלא לאייקון, או `null` כשאין. מורכב בזמן ריצה משם הקובץ
  /// שברשומה — ברשומה עצמה נשמר שם בלבד, לא נתיב (ראו [AppDescriptor]).
  String? iconPathOf(AppDescriptor descriptor) {
    final name = descriptor.iconFile;
    return name == null ? null : p.join(dirPath, name);
  }

  List<String> screenshotPathsOf(AppDescriptor descriptor) => [
        for (final name in descriptor.screenshotFiles) p.join(dirPath, name),
      ];

  /// כותב את המדיה מחדש, כולה, ומחזיר את שמות הקבצים לרשומה.
  ///
  /// [iconSource] ו-[screenshotSources] הם נתיבים מלאים — גם לקבצים
  /// חדשים שהמשתמש בחר, וגם לאלה שכבר יושבים כאן ונשארים. `null` ורשימה
  /// ריקה פירושם "אין", והקבצים שהיו נמחקים.
  ///
  /// **הכול עובר דרך תיקיית ביניים.** השמות נגזרים מהסדר
  /// (`screenshot-1`, `screenshot-2`…), ולכן החלפת הסדר של שתי תמונות
  /// שכבר יושבות כאן הייתה דורסת אחת מהן באמצע.
  Future<({String? icon, List<String> screenshots})> save({
    String? iconSource,
    List<String> screenshotSources = const [],
  }) async {
    final staging = Directory(p.join(dirPath, '.staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    try {
      final iconName =
          iconSource == null ? null : await _stage(staging, iconSource, 'icon');
      final names = <String>[];
      for (var i = 0; i < screenshotSources.length; i++) {
        names.add(
          await _stage(staging, screenshotSources[i], 'screenshot-${i + 1}'),
        );
      }

      await _clear();
      for (final entity in staging.listSync()) {
        if (entity is! File) continue;
        await entity.rename(p.join(dirPath, p.basename(entity.path)));
      }
      return (icon: iconName, screenshots: names);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// מעתיק קובץ אחד לתיקיית הביניים תחת [baseName], ומחזיר את שמו החדש.
  Future<String> _stage(
    Directory staging,
    String source,
    String baseName,
  ) async {
    final t = AppL10n.strings.customAppsDomain;
    final file = File(source);
    if (!await file.exists()) {
      throw AppDescriptorException(t.mediaFileMissing(source));
    }
    final extension = p.extension(source).toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw AppDescriptorException(t.mediaNotAnImage(p.basename(source)));
    }
    final name = '$baseName$extension';
    await file.copy(p.join(staging.path, name));
    return name;
  }

  /// מוחק את קובצי המדיה עצמם בלבד — תיקיית הביניים היא שמחזיקה כרגע את
  /// מה שייכנס במקומם.
  Future<void> _clear() async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    for (final entity in dir.listSync()) {
      if (entity is File) await entity.delete();
    }
  }
}
