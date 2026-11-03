import 'app_l10n.dart';
import 'app_language.dart';

const _percentSentinel = 987654321;

/// האם [stage] הוא עבודה מקומית על הכונן (אימות/הרכבה) ולא הורדה. כל שורה
/// חייבת להתאים לתבנית במלואה, בכל השפות — שם נכס שמזכיר "מאמת" אינו אימות.
bool isLocalWorkStage(String stage) {
  final lines = stage.split('\n').where((line) => line.isNotEmpty).toList();
  return lines.isNotEmpty && lines.every(_isLocalWorkLine);
}

final _patterns = <RegExp>[];

List<RegExp> _localWorkPatterns() {
  if (_patterns.isNotEmpty) return _patterns;
  for (final language in AppLanguage.values) {
    final strings = AppL10n.stringsFor(language).libraryDomain;
    for (final template in [
      strings.exportVerifying('\u0001', '\u0002', _percentSentinel),
      strings.exportAssembling('\u0001', '\u0002', _percentSentinel),
      strings.companionVerifying('\u0001', _percentSentinel),
      strings.companionAssembling('\u0001', _percentSentinel),
    ]) {
      final pattern = RegExp.escape(template)
          .replaceAll('\u0001', '.+?')
          .replaceAll('\u0002', '.+?')
          .replaceAll('$_percentSentinel', r'\d{1,3}');
      _patterns.add(RegExp('^$pattern\$'));
    }
  }
  return _patterns;
}

bool _isLocalWorkLine(String line) =>
    _localWorkPatterns().any((pattern) => pattern.hasMatch(line));
