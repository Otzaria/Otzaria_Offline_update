import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_status.dart';

/// כרטיס תוכנה אחת ברשת.
///
/// **פעולה ראשית אחת בלבד** — מה שנכון לעשות עכשיו לפי המצב. השאר
/// (הורדה, בדיקה ברשת, בחירת מיקום) יושבות בדף התוכנה, שנפתח בלחיצה על
/// הכרטיס; כרטיס בגובה קבוע ברשת אינו יכול לשאת ארבעה כפתורים בלי שהאחרון
/// ייחתך.
class CustomAppStoreCard extends StatelessWidget {
  const CustomAppStoreCard({
    super.key,
    required this.controller,
    required this.app,
    required this.readOnly,
    required this.onOpenDetail,
    required this.onInstall,
    required this.onLaunch,
    required this.onDownload,
    this.manageToolbar,
    this.highlighted = false,
  });

  final CustomAppsController controller;
  final CustomAppView app;

  /// ראו `CustomAppsScreen.readOnly`.
  final bool readOnly;

  final VoidCallback onOpenDetail;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;

  /// במסך הניהול: כלי הסדר והעריכה, במקום הפעולה הראשית ושורת התחתית.
  final Widget? manageToolbar;

  /// כרטיס שמעליו מרחף כרטיס נגרר — שם הוא ינחת.
  final bool highlighted;

  /// תקציב הגובה של שורת הגלולות, ושל שורת הקטגוריות. שניהם חלק מהחישוב
  /// של `kCustomAppCardContentHeight` — שינוי כאן דורש שינוי שם.
  static const double _badgesHeight = 30;
  static const double _categoriesHeight = 26;

  bool get _isDownloading => controller.downloadingId == app.descriptor.id;
  bool get _isFromGithub => app.descriptor.sourceKind == AppSourceKind.github;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manage = manageToolbar != null;
    final action = manageToolbar ?? _primaryAction(context);

    return AppCard(
      onTap: onOpenDetail,
      selected: highlighted,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // אייקון ולא תמונת חנות — ראו `StoreThumbnail.icon`. החסם על
            // הרוחב חייב להיות זהה לזה שנמסר ל-`StoreGridDelegate`, אחרת
            // האריח מקבל גובה שאינו הגובה שהכרטיס תופס בפועל.
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: kCustomAppIconFrameMaxWidth),
                child: StoreThumbnail.icon(
                  imagePath: controller.iconPathOf(app.descriptor),
                  placeholderIcon: FluentIcons.box_24_regular,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            // שורת גלולות אחת, בגובה קבוע: הכרטיס ברשת בגובה קבוע, ושורה
            // שנייה הייתה מגלישה אותו. הפירוט המלא בדף התוכנה.
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(_badgesHeight),
              child: Wrap(
                spacing: AppTokens.spaceXS,
                clipBehavior: Clip.hardEdge,
                children: [
                  StatusChip(
                    kind: customAppStatusKind(app),
                    label: customAppInstalledLabel(context, app),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
            Text(
              app.descriptor.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // התקציר בלבד. מה שעל הכונן נאמר בשורת התחתית, ושתי השורות
            // האלה אמרו את אותו הדבר פעמיים לתוכנה בלי תיאור.
            if (app.descriptor.description case final text?) ...[
              const SizedBox(height: AppTokens.spaceXS),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (app.descriptor.categorySlugs.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSM),
              SizedBox(
                height: _categoriesHeight,
                child: Wrap(
                  spacing: AppTokens.spaceXS,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final slug in app.descriptor.categorySlugs.take(3))
                      StoreTagPill(label: controller.categoryName(slug)),
                  ],
                ),
              ),
            ],
            const Spacer(),
            const SizedBox(height: AppTokens.spaceSM),
            if (action != null) SizedBox(width: double.infinity, child: action),
            // במצב ניהול הסרגל תופס את מקום שורת התחתית: הוא בגובה קבוע
            // והתקציב מוכפל בהגדלת הטקסט, ושניהם יחד גלשו ב-0.9.
            if (!manage) ...[
              if (action != null) const SizedBox(height: AppTokens.spaceSM),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: AppTokens.spaceSM),
              _footer(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.customApps;
    return Row(
      children: [
        Text(
          t.cardDetailsLink,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            customAppStoredLabel(context, app),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// מה שנכון לעשות עכשיו, ורק הוא.
  ///
  /// הסדר אינו שרירותי: עדכון שממתין על הכונן קודם להפעלה, אחרת תוכנה
  /// מותקנת לעולם לא הייתה מציעה את העדכון שכבר נסע אליה.
  Widget? _primaryAction(BuildContext context) {
    final t = context.strings.customApps;
    final common = context.strings.common;

    if (app.canInstall && app.pending == CustomAppPending.newerOnDrive) {
      return ActionButton.recommended(
        text: common.install,
        icon: FluentIcons.desktop_arrow_right_24_regular,
        onPressed: controller.isBusy ? null : onInstall,
      );
    }
    if (app.canLaunch) {
      return ActionButton.neutral(
        text: common.launch,
        icon: FluentIcons.play_24_regular,
        onPressed: controller.isBusy ? null : onLaunch,
      );
    }
    if (app.canInstall) {
      return ActionButton.recommended(
        text: common.install,
        icon: FluentIcons.desktop_arrow_right_24_regular,
        onPressed: controller.isBusy ? null : onInstall,
      );
    }
    // אין מה להתקין, אבל יש מאיפה להביא — וזה בדיוק מה שחסר לתוכנה הזו.
    if (_isFromGithub && !readOnly) {
      return ActionButton.neutral(
        text: t.downloadButton,
        icon: FluentIcons.arrow_download_24_regular,
        isLoading: _isDownloading,
        onPressed:
            controller.downloadingId != null || controller.isDownloadingAll
                ? null
                : onDownload,
      );
    }
    return null;
  }
}

/// גובה כל מה שאינו התמונה בכרטיס — ראו החישוב ב-[StoreGridDelegate].
///
/// נגזר מהתקציבים שלמעלה: גלולה (30), שם בשתי שורות, תקציר בשתיים,
/// שורת קטגוריות (26), כפתור, מפריד ושורת תחתית — עם המרווחים ביניהם.
/// נמדד מול הבדיקה "כרטיס עמוס" ב-`custom_apps_test.dart`.
const double kCustomAppCardContentHeight = 272;

/// הרוחב המינימלי של כרטיס ברשת; ממנו נגזר מספר העמודות.
///
/// צר מזה של חנות התוספים: שם הכרטיס נושא תמונת חנות רחבה, וכאן הוא נושא
/// אייקון ריבועי, שאינו זקוק לאותו רוחב.
const double kCustomAppMinCardWidth = 250;

/// החסם על רוחב מסגרת האייקון. בלעדיו כרטיס רחב (עמודה אחת בחלון צר)
/// היה מקבל מסגרת גבוהה עם אייקון קטן במרכזה — בדיוק הפס הריק שהיחס
/// ב-`kStoreIconRatio` נועד למנוע.
const double kCustomAppIconFrameMaxWidth = 260;
