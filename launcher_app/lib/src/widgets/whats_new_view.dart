import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';

/// "מה התחדש" בתוך דיאלוג — הערות הגרסה של אוצריא ויומן השינויים של
/// הלאנצ'ר. מביא גליל משלו, ולכן מתאים ל-`customContent` של [AppDialog].
class WhatsNewView extends StatelessWidget {
  const WhatsNewView({
    super.key,
    required this.markdown,
    required this.emptyText,
    this.maxHeight = 400,
  });

  final String? markdown;
  final String emptyText;

  /// גובה **מרבי** ולא קבוע: בחלון נמוך, ובעיקר בטקסט מוגדל, גובה קבוע גלש
  /// מהדיאלוג במקום להצטמצם אליו.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final data = markdown?.trim() ?? '';
    return SizedBox(
      width: 600,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: data.isEmpty
            ? Text(emptyText, style: Theme.of(context).textTheme.bodyMedium)
            // `Markdown` הגלילתי אומד את הגובה מהפריטים שנבנו בלבד, והאגודל
            // "רוקד" — כמו באוצריא, גליל חיצוני עם `MarkdownBody`.
            : SingleChildScrollView(
                child: MarkdownBody(
                  data: data,
                  styleSheet: whatsNewStyleSheet(context),
                ),
              ),
      ),
    );
  }
}

/// "מה התחדש:" וה-Markdown שמתחתיו — הקטע שדיאלוג "גרסה חדשה" מוסיף מתחת
/// לנוסח שלו, כמו ב-`hebrewDefaultDialog` של אוצריא.
class WhatsNewSection extends StatelessWidget {
  const WhatsNewSection({
    super.key,
    required this.heading,
    required this.markdown,
  });

  final String heading;
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTokens.spaceMD),
        Text(
          heading,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXS),
        // נמוך מדיאלוג יומן השינויים המלא: כאן יש גם נוסח וכפתורים.
        WhatsNewView(markdown: markdown, emptyText: '', maxHeight: 300),
      ],
    );
  }
}

/// גיליון סגנון ל"מה התחדש" — מבוסס על עיצוב הערכה (`fromTheme`) עם
/// דריסות לפי טוקני העיצוב של אוצריא (צבע/פונט כותרות כמו כותרת
/// [SettingsCard], והזחת בלט/מסגרת ציטוט לפי כיוון הכתיבה).
MarkdownStyleSheet whatsNewStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isRtl = context.isRtl;
  final headingStyle =
      TextStyle(color: cs.primary, fontWeight: FontWeight.bold);

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
    h1: theme.textTheme.headlineSmall?.merge(headingStyle),
    h2: theme.textTheme.titleLarge?.merge(headingStyle),
    h3: theme.textTheme.titleMedium?.merge(headingStyle),
    blockSpacing: AppTokens.spaceSM,
    listIndent: AppTokens.spaceLG,
    // ה-bullet הוא הילד הראשון ב-Row של הפריט; הריווח צריך להיות בצד
    // שאליו זורם הטקסט — שמאל ב-RTL, ימין ב-LTR.
    listBulletPadding: EdgeInsets.only(
      left: isRtl ? AppTokens.spaceXS : 0,
      right: isRtl ? 0 : AppTokens.spaceXS,
    ),
    blockquotePadding: const EdgeInsets.symmetric(
      horizontal: AppTokens.spaceMD,
      vertical: AppTokens.spaceXS,
    ),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: AppTokens.borderRadiusAll,
      border: BorderDirectional(
        start: BorderSide(color: cs.primary, width: 3),
      ),
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: AppTokens.borderRadiusAll,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.dividerColor)),
    ),
  );
}
