// שורת בחירת צבע הבסיס והדיאלוג שלה — פורט מאוצריא
// (`otzaria/lib/settings/dialogs/color_picker_dialog.dart`). אותה פלטה, אותו
// סדר עיגולים ואותה התנהגות: הצבע חל מיד בלחיצה, בלי כפתור אישור.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'app_dialogs.dart';
import 'settings_card.dart';

/// שמו של צבע הפלטה במלל המתורגם. `switch` ממצה על [SeedColorLabel] —
/// צבע חדש בפלטה לא יתקמפל עד שיקבל שם בשתי השפות.
String seedColorName(SettingsScreenStrings t, Color color) {
  final label = AppSeedColors.labelOf(color);
  if (label == null) return t.seedColorCustom;
  return switch (label) {
    SeedColorLabel.red => t.colorRed,
    SeedColorLabel.orange => t.colorOrange,
    SeedColorLabel.amber => t.colorAmber,
    SeedColorLabel.green => t.colorGreen,
    SeedColorLabel.teal => t.colorTeal,
    SeedColorLabel.blue => t.colorBlue,
    SeedColorLabel.blueGrey => t.colorBlueGrey,
    SeedColorLabel.navy => t.colorNavy,
    SeedColorLabel.purple => t.colorPurple,
    SeedColorLabel.brown => t.colorBrown,
    SeedColorLabel.parchment => t.colorParchment,
    SeedColorLabel.grey => t.colorGrey,
    SeedColorLabel.darkBrown => t.colorDarkBrown,
  };
}

/// שורת הגדרה לבחירת צבע הבסיס — מציגה את שם הצבע הנבחר, ופותחת את הפלטה.
class ColorPickerTile extends StatelessWidget {
  const ColorPickerTile({
    super.key,
    required this.currentColor,
    required this.defaultColor,
    required this.onChanged,
  });

  final Color currentColor;
  final Color defaultColor;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;

    return SettingsActionTile.text(
      icon: FluentIcons.color_24_regular,
      title: t.seedColorTitle,
      subtitle: seedColorName(t, currentColor),
      actions: [
        ActionButton.neutral(
          text: t.seedColorButton,
          onPressed: () => showSingleActionDialog(
            context: context,
            title: t.seedColorDialogTitle,
            // כותרת הדיאלוג כאן היא מחרוזת (`AppDialog`), ולכן תצוגת הצבע
            // הנבחר וכפתור האיפוס — שבאוצריא יושבים בכותרת — פותחים את התוכן.
            customContent: SeedColorPalette(
              currentColor: currentColor,
              defaultColor: defaultColor,
              onChanged: onChanged,
            ),
            confirmText: context.strings.common.close,
          ),
        ),
      ],
    );
  }
}

/// גוף הדיאלוג: הצבע הנבחר, איפוס, ועיגולי הפלטה.
class SeedColorPalette extends StatefulWidget {
  const SeedColorPalette({
    super.key,
    required this.currentColor,
    required this.defaultColor,
    required this.onChanged,
  });

  final Color currentColor;
  final Color defaultColor;
  final ValueChanged<Color> onChanged;

  @override
  State<SeedColorPalette> createState() => _SeedColorPaletteState();
}

class _SeedColorPaletteState extends State<SeedColorPalette> {
  /// מצב מקומי: הדיאלוג הוא מסלול נפרד ואינו נבנה מחדש כשהשורה שמתחתיו כן.
  late Color _selected = widget.currentColor;

  void _select(Color color) {
    setState(() => _selected = color);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      // רוחב קבוע: בלעדיו מספר העיגולים בשורה משתנה לפי אורך הכותרת, ולכן
      // גם לפי השפה.
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Swatch(color: _selected, size: 22),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  seedColorName(t, _selected),
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              ActionButton.ghost(
                text: t.seedColorResetButton,
                icon: FluentIcons.arrow_reset_24_regular,
                onPressed: () => _select(widget.defaultColor),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          // הפלטה אינה טקסט — כיוון קבוע כדי שסדר העיגולים לא יתהפך באנגלית.
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceSM,
              alignment: WrapAlignment.center,
              children: [
                for (final option in AppSeedColors.options)
                  Tooltip(
                    message: seedColorName(t, option.color),
                    child: GestureDetector(
                      onTap: () => _select(option.color),
                      child: _Swatch(
                        color: option.color,
                        size: 40,
                        selected:
                            option.color.toARGB32() == _selected.toARGB32(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// עיגול צבע. הנבחר מקבל מסגרת `onSurface` **וגם** סימן וי — הסימן לבדו
/// נעלם על גוונים בהירים כמו פרגמנט.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.size,
    this.selected = false,
  });

  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: selected ? Border.all(color: cs.onSurface, width: 3) : null,
      ),
      child: selected
          ? Icon(FluentIcons.checkmark_24_filled, color: cs.onSurface, size: 18)
          : null,
    );
  }
}
