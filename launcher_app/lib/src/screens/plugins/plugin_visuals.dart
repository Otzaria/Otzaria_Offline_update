import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';

/// רכיבי התצוגה **של התוספים בלבד**: מטא, מצב מול ההתקנה והפעולה שנגזרת
/// ממנו. מה שמשותף לשתי החנויות יושב ב-`screens/store_kit/`.

/// תווית סטטוס התוסף. בטא וניסיוני הם "ניסיוני" אחד — כמו בסינון.
/// המפתחות מגיעים מה-API ואינם מתורגמים — רק התוויות שמוצגות.
String pluginStatusLabel(String status) {
  final t = AppL10n.strings.plugins;
  if (status == 'stable') return t.statusStable;
  return isExperimentalPluginStatus(status)
      ? t.statusExperimental
      : t.statusUnknown;
}

/// הממוצע כפי שהאתר מציג אותו — ספרה אחת אחרי הנקודה, תמיד.
String formatRating(double value) => value.toStringAsFixed(1);

/// מספר כמו באתר: עם מפריד אלפים.
String formatCount(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// חמישה כוכבים עם מילוי חלקי לפי [value]. **תצוגה בלבד** — הדירוג עצמו
/// נעשה באתר (דורש חשבון), ואין כאן שום דרך לדרג.
class PluginRatingStars extends StatelessWidget {
  const PluginRatingStars({super.key, required this.value, this.size = 16});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clamped = value.clamp(0.0, 5.0);

    return Semantics(
      label: AppL10n.strings.plugins.ratingStarsLabel(formatRating(clamped)),
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          _stars(cs.outlineVariant),
          // ב-RTL ה-start הוא הצד הימני, ולכן המילוי מתחיל מאותו כוכב כמו באתר.
          ClipRect(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: clamped / 5,
              child: _stars(AppPalette.of(context).rating),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stars(Color color) {
    final icon =
        size < 20 ? FluentIcons.star_16_filled : FluentIcons.star_24_filled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Icon(icon, size: size, color: color),
        ],
      ],
    );
  }
}

/// מה התוסף מציע עכשיו במחשב הזה — נגזר מההתקנה, מהכונן ומאוצריא.
enum PluginCardState {
  /// נשלח כרגע לאוצריא.
  sending,

  /// נשלח, ואוצריא עוד לא סיימה.
  sent,
  development,

  /// אין בילד שירוץ על אוצריא שבמחשב הזה.
  incompatible,
  update,
  disabled,
  installed,
  install,

  /// אוצריא עוד לא מותקנת כאן.
  needsOtzaria,

  /// הקובץ לא ירד לכונן, ובמחשב הזה אין אינטרנט להביא אותו.
  missingOffline,

  /// התוסף אינו תומך בהתקנה ישירה — רק שמירת קובץ.
  saveOnly,
}

PluginCardState pluginCardStateOf(
  PluginsModuleController controller,
  StorePlugin plugin, {
  required bool busy,
  required bool otzariaInstalled,
  bool? online,
}) {
  if (busy) return PluginCardState.sending;
  if (controller.isAwaitingInstallOf(plugin)) return PluginCardState.sent;
  if (controller.isDevelopmentInOtzaria(plugin)) {
    return PluginCardState.development;
  }
  final direct = controller.canDirectInstall(plugin);
  final state = switch (controller.statusOf(plugin)) {
    PluginInstallStatus.incompatible => PluginCardState.incompatible,
    PluginInstallStatus.updateAvailable =>
      direct ? PluginCardState.update : PluginCardState.saveOnly,
    PluginInstallStatus.upToDate => controller.isDisabledInOtzaria(plugin)
        ? PluginCardState.disabled
        : PluginCardState.installed,
    PluginInstallStatus.notInstalled || PluginInstallStatus.unknown => !direct
        ? PluginCardState.saveOnly
        : otzariaInstalled
            ? PluginCardState.install
            : PluginCardState.needsOtzaria,
  };
  final fetchable =
      state == PluginCardState.install || state == PluginCardState.update;
  return fetchable && online == false && !controller.hasFileFor(plugin)
      ? PluginCardState.missingOffline
      : state;
}

/// הגרסה המינימלית של אוצריא שהתוסף דורש — לשורת ההסבר כשאינו מתאים.
String? pluginRequiredAppVersion(StorePlugin plugin) =>
    plugin.compatibleWith.isEmpty ? null : plugin.compatibleWith;

/// שורת ההסבר הקצרה מתחת לפעולה, או `null`.
String? pluginNoteOf(
  BuildContext context,
  PluginsModuleController controller,
  StorePlugin plugin,
  PluginCardState state, {
  bool? online,
}) {
  final t = context.strings.plugins;
  switch (state) {
    case PluginCardState.incompatible:
      final needs = pluginRequiredAppVersion(plugin);
      return needs == null ? t.noteIncompatible : t.noteNeedsApp(needs);
    case PluginCardState.needsOtzaria:
      return t.noteNeedsOtzaria;
    case PluginCardState.saveOnly:
      return t.noteSaveOnly;
    case PluginCardState.missingOffline:
      return t.noteNextDriveDownload;
    case PluginCardState.update || PluginCardState.install:
      if (state == PluginCardState.update &&
          controller.isDisabledInOtzaria(plugin)) {
        return t.noteDisabled;
      }
      if (controller.hasFileFor(plugin)) return null;
      return online == true ? t.noteFileMissingOnline : t.noteFileMissing;
    case PluginCardState.sending ||
          PluginCardState.sent ||
          PluginCardState.development ||
          PluginCardState.disabled ||
          PluginCardState.installed:
      return null;
  }
}

/// הפעולה או המצב של התוסף: כפתור (tonal בכרטיס, ראשי בדף), או תווית מצב.
class PluginAction extends StatelessWidget {
  const PluginAction({
    super.key,
    required this.controller,
    required this.plugin,
    required this.state,
    required this.onInstall,
    required this.onSave,
    this.primary = false,
    this.blocked = false,
  });

  final PluginsModuleController controller;
  final StorePlugin plugin;
  final PluginCardState state;
  final VoidCallback onInstall;
  final VoidCallback onSave;

  /// בדף הפרטים — כפתור ראשי.
  final bool primary;

  /// סנכרון, ייצוא או "עדכון הכול" רצים — הכפתור מושבת.
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    Widget button(String text, VoidCallback? onPressed, {IconData? icon}) =>
        primary
            ? ActionButton.recommended(
                text: text,
                icon: icon,
                onPressed: blocked ? null : onPressed,
              )
            : ActionButton.neutral(
                text: text,
                icon: icon,
                onPressed: blocked ? null : onPressed,
              );

    return switch (state) {
      PluginCardState.sending => ActionButton.neutral(
          text: t.sendingLabel, isLoading: true, onPressed: null),
      PluginCardState.sent => StoreStateLabel(
          icon: FluentIcons.send_20_regular,
          text: t.sentLabel,
        ),
      PluginCardState.development => StoreStateLabel(
          icon: FluentIcons.wrench_20_regular,
          text: t.developmentLabel,
        ),
      PluginCardState.incompatible => StoreStateLabel(
          icon: FluentIcons.warning_20_regular,
          text: t.incompatibleLabel,
        ),
      PluginCardState.disabled => StoreStateLabel(
          icon: FluentIcons.eye_off_20_regular,
          text: t.disabledLabel,
        ),
      PluginCardState.installed => StoreStateLabel(
          icon: FluentIcons.checkmark_circle_20_filled,
          text: t.installedLabel,
        ),
      PluginCardState.update =>
        button(t.updateToButton(controller.versionOf(plugin)), onInstall),
      PluginCardState.install => button(t.installInOtzariaButton, onInstall),
      PluginCardState.needsOtzaria => button(t.installInOtzariaButton, null),
      PluginCardState.missingOffline => StoreStateLabel(
          icon: FluentIcons.arrow_download_20_regular,
          text: t.fileNotOnDriveLabel,
        ),
      PluginCardState.saveOnly => button(
          t.saveFileButton,
          controller.hasFileFor(plugin) ? onSave : null,
          icon: FluentIcons.save_20_regular,
        ),
    };
  }
}

/// שורת המטא של תוסף: דירוג, הורדות, גרסה, ושבבים לבטא/ניסיוני, לאינטרנט
/// ולתוסף חדש. "יציב" אינו מוצג — כמו בכרטיס שבאתר.
class PluginMeta extends StatelessWidget {
  const PluginMeta({
    super.key,
    required this.controller,
    required this.plugin,
    this.isNew = false,
  });

  final PluginsModuleController controller;
  final StorePlugin plugin;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    final status = controller.targetOf(plugin)?.status ?? plugin.status;
    final network =
        controller.targetOf(plugin)?.requiresNetwork ?? plugin.requiresNetwork;
    return StoreMetaLine(
      items: [
        if (isNew) StoreMetaChip(t.newChip, tonal: true),
        if (plugin.ratingCount > 0)
          Tooltip(
            message: t.ratingTooltip(plugin.ratingCount),
            child: StoreMetaItem(
              t.ratingBadge(formatRating(plugin.ratingAvg), plugin.ratingCount),
              icon: FluentIcons.star_16_filled,
              iconColor: AppPalette.of(context).rating,
            ),
          ),
        if (plugin.downloadCount > 0)
          StoreMetaItem(
            formatCount(plugin.downloadCount),
            icon: FluentIcons.arrow_download_16_regular,
          ),
        StoreMetaItem(t.pluginVersionBadge(controller.versionOf(plugin))),
        if (isExperimentalPluginStatus(status))
          StoreMetaChip(pluginStatusLabel(status)),
        if (network)
          StoreMetaChip(
            t.networkChip,
            icon: FluentIcons.globe_16_regular,
          ),
      ],
    );
  }
}
