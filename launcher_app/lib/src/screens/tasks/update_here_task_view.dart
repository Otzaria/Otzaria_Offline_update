import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../screens/home/home_view_model.dart' show displayVersion;
import '../../shell/home_guidance.dart' show GuidanceItem;
import '../../shell/shell_keys.dart';
import '../../shell/shell_tasks.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'task_parts.dart';

/// התקדמות החלת הספרייה — נקראת בתוך `ListenableBuilder` על ה-progress.
class LibraryApplySnapshot {
  const LibraryApplySnapshot({this.fraction, this.stage});

  final double? fraction;
  final String? stage;
}

class UpdateHereActions {
  const UpdateHereActions({
    required this.onRespond,
    required this.onStopWaiting,
    required this.onFinishWithoutWaiting,
    required this.onLaunch,
    required this.onHome,
    required this.onRetry,
    required this.onOpenPage,
    this.onReindex,
    this.onRestartElevated,
    this.onLibraryChanges,
  });

  final ValueChanged<bool> onRespond;
  final VoidCallback onStopWaiting;
  final VoidCallback onFinishWithoutWaiting;
  final VoidCallback onLaunch;
  final VoidCallback onHome;
  final VoidCallback onRetry;

  /// "לדף הספרייה" / "לדף התוספים" במסך הכשל. לתוכנה אין דף — הבית.
  final ValueChanged<GuidanceItem> onOpenPage;

  /// `null` — אין בקשת אינדוקס שממתינה.
  final VoidCallback? onReindex;

  /// `null` — הכשל אינו על הרשאות, או שהסשן לא יכבד הפעלה מחדש עכשיו.
  final VoidCallback? onRestartElevated;

  /// `null` — אין "מה חדש" לספרייה שהותקנה.
  final VoidCallback? onLibraryChanges;
}

/// מסך המשימה "עדכון אוצריא במחשב הזה" (וגם "התקנת אוצריא").
class UpdateHereTaskView extends StatelessWidget {
  const UpdateHereTaskView({
    super.key,
    required this.task,
    required this.libraryProgress,
    required this.librarySnapshot,
    required this.actions,
  });

  final UpdateHereTask task;
  final Listenable libraryProgress;
  final LibraryApplySnapshot Function() librarySnapshot;
  final UpdateHereActions actions;

  @override
  Widget build(BuildContext context) => switch (task.phase) {
        UpdateHereTaskPhase.confirmElevatedOtherUser => _otherUser(context),
        UpdateHereTaskPhase.closeOtzaria when !task.closeAfterWizard =>
          _close(context),
        UpdateHereTaskPhase.closeOtzaria ||
        UpdateHereTaskPhase.running =>
          _running(context),
        UpdateHereTaskPhase.done => _done(context),
        UpdateHereTaskPhase.cancelledByUser => _cancelled(context),
        UpdateHereTaskPhase.failed => _failed(context),
      };

  Widget _otherUser(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      center: true,
      start: ActionButton.ghost(
        text: context.strings.common.cancel,
        onPressed: () => actions.onRespond(false),
      ),
      end: ActionButton.recommended(
        key: ShellKeys.taskPrimary,
        text: t.continueAnyway,
        autofocus: true,
        onPressed: () => actions.onRespond(true),
      ),
      child: Column(
        children: [
          const _BigTile(child: Icon(FluentIcons.person_24_regular, size: 32)),
          TaskHeading(
            title: t.otherUserTitle,
            body: t.otherUserBody(
              firstInstall: task.firstInstall,
              account: task.account,
            ),
            hint: t.otherUserHint,
          ),
        ],
      ),
    );
  }

  Widget _close(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      center: true,
      start: ActionButton.ghost(
        text: context.strings.common.cancel,
        onPressed: () => actions.onRespond(false),
      ),
      end: ActionButton.recommended(
        key: ShellKeys.taskPrimary,
        text: t.closeOtzariaAndContinue,
        autofocus: true,
        onPressed: () => actions.onRespond(true),
      ),
      child: Column(
        children: [
          _BigTile(child: _logo(40)),
          TaskHeading(
            title: t.closeTitle,
            body: t.closeBody,
            hint: t.closeHint(
              plugins: task.stages.contains(GuidanceItem.plugins),
            ),
          ),
        ],
      ),
    );
  }

  Widget _running(BuildContext context) {
    final t = context.strings.task;
    final narrow = TaskFrame.isCompact(context);
    final stage = task.currentStage;
    final closing = task.phase == UpdateHereTaskPhase.closeOtzaria;
    final first = task.firstInstall;
    final minutes = task.libraryMinutes;
    final (title, body) = closing
        ? (t.closeTitle, t.closeAfterWizardBody)
        : switch (stage) {
            GuidanceItem.app => (
                first ? t.installingApp : t.updatingApp,
                first ? t.appWizardFirstBody : t.appWizardBody,
              ),
            GuidanceItem.library => (
                first ? t.installingLibrary : t.updatingLibrary,
                t.libraryBody(minutes?.low, minutes?.high),
              ),
            GuidanceItem.plugins || null => (t.sendingPlugins, t.pluginsBody),
          };
    final index = task.stageIndex.clamp(0, task.stages.length - 1);
    return TaskFrame(
      start: closing
          ? ActionButton.ghost(
              text: context.strings.common.cancel,
              onPressed: () => actions.onRespond(false),
            )
          : null,
      end: closing
          ? ActionButton.recommended(
              key: ShellKeys.taskPrimary,
              text: t.closeOtzariaAndContinue,
              autofocus: true,
              onPressed: () => actions.onRespond(true),
            )
          : stage == GuidanceItem.plugins
              ? ActionButton.ghost(
                  key: ShellKeys.taskSecondary,
                  text: t.finishWithoutWaiting,
                  onPressed: actions.onFinishWithoutWaiting,
                )
              : null,
      child: Column(
        children: [
          StepDots(count: task.stages.length, current: index),
          const SizedBox(height: 8),
          Text(
            t.stepOf(index + 1, task.stages.length),
            style: AppTextStyles.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TaskHeading(title: title, body: body),
          if (stage == GuidanceItem.library && !closing)
            const KeepDriveNotice(),
          SizedBox(height: narrow ? 16 : 24),
          RowsCard(
            children: [
              for (final (i, s) in task.stages.indexed)
                _stageRow(context, s, i, closing: closing, compact: narrow),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageRow(
    BuildContext context,
    GuidanceItem stage,
    int i, {
    required bool closing,
    required bool compact,
  }) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    final state = i < task.stageIndex
        ? StageState.done
        : i == task.stageIndex
            ? StageState.current
            : StageState.waiting;
    final outcome = task.outcomes[stage];
    final version =
        task.appVersion == null ? null : displayVersion(task.appVersion!);
    switch (stage) {
      case GuidanceItem.app:
        return StageRow(
          tileChild: _logo(18),
          title: t.componentApp,
          state: state,
          compact: compact,
          detail: switch (state) {
            StageState.done => switch (outcome) {
                StageOutcome.stoppedWaiting => t.appStoppedWaiting,
                StageOutcome.skipped => t.appSkipped,
                _ =>
                  version == null ? t.stageDone(null) : t.appInstalled(version),
              },
            StageState.current => t.appWizardOpen,
            StageState.waiting =>
              version == null ? null : t.appVersion(version),
          },
          extra: state == StageState.current
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const AppProgressBar(thin: true),
                    const SizedBox(height: 6),
                    TextLink(
                      key: ShellKeys.taskStopWaiting,
                      text: t.stopWaiting,
                      style: AppTextStyles.meta,
                      onTap: task.stopWaitingRequested
                          ? null
                          : actions.onStopWaiting,
                    ),
                  ],
                )
              : null,
        );
      case GuidanceItem.library:
        final detail = _libraryDetail(context);
        if (state == StageState.current && !closing) {
          return ListenableBuilder(
            listenable: libraryProgress,
            builder: (context, _) {
              final s = librarySnapshot();
              final pct = s.fraction == null
                  ? null
                  : '${(s.fraction!.clamp(0.0, 1.0) * 100).floor()}%';
              return StageRow(
                icon: FluentIcons.library_24_regular,
                title: t.componentLibrary,
                state: state,
                compact: compact,
                detail: [if (pct != null) pct, if (detail != null) detail]
                    .join(' · '),
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    AppProgressBar(thin: true, value: s.fraction),
                    if (s.stage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.stage!,
                        style: AppTextStyles.meta.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        }
        return StageRow(
          icon: FluentIcons.library_24_regular,
          title: t.componentLibrary,
          state: state,
          compact: compact,
          // ממתינים למשתמש, לא עובדים — מנעול ולא טבעת מסתובבת.
          mark: state == StageState.current && closing
              ? Icon(
                  FluentIcons.lock_closed_20_regular,
                  size: 20,
                  color: cs.onSurfaceVariant,
                )
              : null,
          detail: switch (state) {
            StageState.done => outcome == StageOutcome.skipped
                ? t.librarySkipped
                : t.libraryDone(detail ?? t.componentLibrary),
            StageState.current => t.libraryWaitingClose,
            StageState.waiting => detail,
          },
        );
      case GuidanceItem.plugins:
        return StageRow(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: t.componentPlugins,
          state: state,
          compact: compact,
          detail: switch (state) {
            StageState.done => outcome == StageOutcome.skipped
                ? t.pluginsAfterInstall
                : t.pluginsSent,
            StageState.current => t.pluginsCurrent,
            StageState.waiting => t.pluginsWaiting(task.plugins.length),
          },
          extra: state == StageState.current
              ? _Deliveries(rows: task.plugins)
              : null,
        );
    }
  }

  String? _libraryDetail(BuildContext context) {
    final t = context.strings.task;
    if (task.librarySemanticOnly) {
      return context.strings.libraryDomain.companionSemanticName;
    }
    return task.firstInstall
        ? t.libraryFull
        : task.libraryVersion == null
            ? null
            : t.libraryVersion(task.libraryVersion!);
  }

  Widget _done(BuildContext context) {
    final t = context.strings.task;
    final g = context.strings.guide;
    final cs = Theme.of(context).colorScheme;
    final narrow = TaskFrame.isCompact(context);
    final outcomes = task.outcomes;
    final appDone = outcomes[GuidanceItem.app] == StageOutcome.done;
    final libraryDone = outcomes[GuidanceItem.library] == StageOutcome.done;
    final stoppedWaiting =
        outcomes[GuidanceItem.app] == StageOutcome.stoppedWaiting;
    final rows = task.plugins;
    final sent = rows.any((p) => p.state != PluginDeliveryState.failed);
    final pluginsSent = task.stages.contains(GuidanceItem.plugins) &&
        outcomes[GuidanceItem.plugins] == StageOutcome.done &&
        sent;

    Widget doneMark() => Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: 22,
          color: cs.primary,
        );
    Widget quietMark(IconData icon) =>
        Icon(icon, size: 22, color: cs.onSurfaceVariant);

    AppRow row(GuidanceItem s) {
      final outcome = outcomes[s];
      final (title, subtitle, mark) = switch (s) {
        GuidanceItem.app => switch (outcome) {
            StageOutcome.stoppedWaiting => (
                t.appStoppedWaiting,
                null,
                quietMark(FluentIcons.clock_24_regular),
              ),
            StageOutcome.skipped => (
                t.appSkipped,
                null,
                quietMark(FluentIcons.subtract_circle_24_regular),
              ),
            _ => (
                task.appVersion == null
                    ? t.stageDone(null)
                    : t.doneAppValue(displayVersion(task.appVersion!)),
                null,
                doneMark(),
              ),
          },
        // הערה על שלב שדולג היא הסיבה (למשל חסימת החיפוש החכם), ולא "אחר כך".
        GuidanceItem.library => outcome == StageOutcome.skipped
            ? (
                task.libraryNote ?? t.librarySkipped,
                null,
                quietMark(FluentIcons.subtract_circle_24_regular),
              )
            : (
                _libraryDetail(context) ?? t.componentLibrary,
                task.libraryNote,
                task.libraryNote == null
                    ? doneMark()
                    : quietMark(FluentIcons.warning_24_regular),
              ),
        GuidanceItem.plugins => _pluginsRow(context, outcome, quietMark),
      };
      return AppRow(
        dense: narrow,
        leading: s == GuidanceItem.app
            ? IconTile(child: _logo(24))
            : IconTile(
                icon: s == GuidanceItem.library
                    ? FluentIcons.library_24_regular
                    : FluentIcons.puzzle_piece_24_regular,
              ),
        label: switch (s) {
          GuidanceItem.app => t.componentApp,
          GuidanceItem.library => t.componentLibrary,
          GuidanceItem.plugins => t.componentPlugins,
        },
        title: title,
        subtitle: subtitle,
        trailing: mark,
      );
    }

    final (title, body) = stoppedWaiting
        ? (
            t.stoppedWaitingTitle,
            t.stoppedWaitingBody(firstInstall: false, libraryDone: libraryDone),
          )
        : (
            task.firstInstall ? t.installedTitle : t.updatedTitle,
            t.doneHereBody(
              firstInstall: task.firstInstall,
              app: appDone,
              library: libraryDone,
              plugins: pluginsSent,
              libraryNote: task.libraryNote != null,
            ),
          );
    return TaskResult(
      badge: ResultBadge(
        kind: stoppedWaiting ? ResultBadgeKind.calm : ResultBadgeKind.ok,
        icon: stoppedWaiting
            ? FluentIcons.clock_24_regular
            : FluentIcons.checkmark_24_regular,
      ),
      title: title,
      body: body,
      extra: [
        SizedBox(height: narrow ? 12 : 20),
        RowsCard(children: [for (final s in task.stages) row(s)]),
        if (actions.onReindex != null && !task.firstInstall && libraryDone)
          TaskGuide(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.reindexTitle,
                          style: AppTextStyles.small.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: AppTextStyles.semibold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.reindexBody,
                          style: AppTextStyles.small.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ActionButton.neutral(
                    key: ShellKeys.taskReindex,
                    text: t.reindexButton,
                    size: ActionButtonSize.sm,
                    onPressed: actions.onReindex,
                  ),
                ],
              ),
            ],
          ),
        if (actions.onLibraryChanges != null) ...[
          const SizedBox(height: 12),
          TextLink(
            text: context.strings.libraryScreen.changesTitle,
            onTap: actions.onLibraryChanges,
          ),
        ],
      ],
      actions: stoppedWaiting
          ? [
              ActionButton.recommended(
                key: ShellKeys.taskPrimary,
                text: t.backHome,
                size: ActionButtonSize.lg,
                autofocus: true,
                expand: true,
                onPressed: () => actions.onOpenPage(GuidanceItem.app),
              ),
            ]
          : [
              ActionButton.recommended(
                key: ShellKeys.taskPrimary,
                text: pluginsSent ? t.toOtzaria : g.launchButton,
                size: ActionButtonSize.lg,
                autofocus: true,
                expand: true,
                onPressed: actions.onLaunch,
              ),
              ActionButton.ghost(
                text: t.backHome,
                expand: true,
                onPressed: actions.onHome,
              ),
            ],
    );
  }

  /// שורת התוספים בסיום: רק מה שבאמת נשלח נקרא "נשלח".
  (String, String?, Widget) _pluginsRow(
    BuildContext context,
    StageOutcome? outcome,
    Widget Function(IconData) quietMark,
  ) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    final rows = task.plugins;
    if (rows.isEmpty) {
      return (
        t.appSkipped,
        null,
        quietMark(FluentIcons.subtract_circle_24_regular),
      );
    }
    final names = rows.map((p) => p.name).join(', ');
    if (outcome == StageOutcome.skipped) {
      return (
        names,
        t.pluginsAfterInstall,
        quietMark(FluentIcons.clock_24_regular),
      );
    }
    String namesIn(PluginDeliveryState state) =>
        rows.where((p) => p.state == state).map((p) => p.name).join(', ');
    final sent = namesIn(PluginDeliveryState.sent);
    final failed = namesIn(PluginDeliveryState.failed);
    final waiting = namesIn(PluginDeliveryState.waiting);
    if (failed.isEmpty && waiting.isEmpty) {
      return (
        names,
        t.pluginsSent,
        Icon(FluentIcons.send_24_regular, size: 22, color: cs.primary),
      );
    }
    final subtitle = [
      if (sent.isNotEmpty) t.pluginsSentNames(sent),
      if (waiting.isNotEmpty) t.pluginsStillSending(waiting),
      if (failed.isNotEmpty) t.pluginsNotSent(failed),
    ].join(' · ');
    return (
      names,
      subtitle,
      failed.isNotEmpty
          ? Icon(FluentIcons.dismiss_circle_24_regular,
              size: 22, color: cs.error)
          : quietMark(FluentIcons.clock_24_regular),
    );
  }

  Widget _cancelled(BuildContext context) {
    final t = context.strings.task;
    final atStage = task.stageIndex < task.stages.length
        ? task.stages[task.stageIndex]
        : null;
    final wizard = atStage == GuidanceItem.app;
    final appOutcome = task.outcomes[GuidanceItem.app];
    final libraryDone =
        task.outcomes[GuidanceItem.library] == StageOutcome.done;
    // לא ידוע אם ההתקנה הסתיימה — הבדיקה בבית, לא "נסה שוב" שיפתח אשף נוסף
    // מעל הפתוח.
    final unknown = wizard &&
        (appOutcome == StageOutcome.stoppedWaiting ||
            appOutcome == StageOutcome.stillOpen);
    final (title, body) = !wizard
        ? (t.stoppedTitle, t.stoppedBody)
        : switch (appOutcome) {
            StageOutcome.stoppedWaiting => (
                t.stoppedWaitingTitle,
                t.stoppedWaitingBody(
                  firstInstall: task.firstInstall,
                  libraryDone: libraryDone,
                ),
              ),
            StageOutcome.stillOpen => (
                t.wizardStillOpenTitle,
                t.wizardStillOpenBody,
              ),
            _ => (
                t.wizardClosedTitle,
                t.wizardClosedBody(
                  firstInstall: task.firstInstall,
                  libraryDone: libraryDone,
                ),
              ),
          };
    return TaskResult(
      badge: ResultBadge(
        kind: ResultBadgeKind.calm,
        icon: unknown
            ? FluentIcons.clock_24_regular
            : FluentIcons.arrow_reset_24_regular,
      ),
      title: title,
      body: body,
      actions: [
        if (unknown)
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: t.backHome,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: () => actions.onOpenPage(GuidanceItem.app),
          )
        else ...[
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: context.strings.common.retry,
            icon: FluentIcons.arrow_clockwise_24_regular,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: actions.onRetry,
          ),
          ActionButton.ghost(
            text: t.backHome,
            expand: true,
            onPressed: actions.onHome,
          ),
        ],
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final t = context.strings.task;
    final failure = task.failure ?? const UpdateFailure(GuidanceItem.library);
    final library = failure.stage == GuidanceItem.library;
    final elevate = actions.onRestartElevated;
    final message = splitFailureMessage(failure.message);
    final app = failure.stage == GuidanceItem.app;
    final home = ActionButton.ghost(
      text: t.backHome,
      expand: true,
      onPressed:
          app ? () => actions.onOpenPage(GuidanceItem.app) : actions.onHome,
    );
    if (elevate != null) {
      final raw = failure.message?.trim();
      return TaskResult(
        badge: const ResultBadge(
          kind: ResultBadgeKind.error,
          icon: FluentIcons.important_24_filled,
        ),
        title: task.firstInstall
            ? t.permissionInstallFailedTitle
            : t.permissionFailedTitle,
        body: library
            ? t.permissionLibraryBody
            : task.firstInstall
                ? t.permissionAppInstallBody
                : t.permissionAppBody,
        extra: [
          const SizedBox(height: 16),
          NoticeBanner(
            key: ShellKeys.taskElevation,
            kind: NoticeKind.banner,
            leading:
                const IconTile(icon: FluentIcons.shield_checkmark_24_regular),
            title: t.elevateTitle,
            body: t.elevateBody,
          ),
          if (raw != null && raw.isNotEmpty) TechDetails(text: raw),
        ],
        actions: [
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: t.elevateButton,
            icon: FluentIcons.shield_checkmark_24_regular,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: elevate,
          ),
          home,
        ],
      );
    }
    final plugins = failure.stage == GuidanceItem.plugins;
    final keep = library
        ? t.libraryFailedKeep
        : plugins
            ? t.pluginsFailedKeep(
                firstInstall: task.firstInstall,
                appDone: task.outcomes[GuidanceItem.app] == StageOutcome.done,
              )
            : t.appFailedKeep;
    final lead = message.body;
    return TaskResult(
      badge: const ResultBadge(
        kind: ResultBadgeKind.error,
        icon: FluentIcons.important_24_filled,
      ),
      title: library
          ? (task.firstInstall
              ? t.libraryInstallFailedTitle
              : t.libraryFailedTitle)
          : plugins
              ? t.pluginsFailedTitle
              : t.appFailedTitle,
      body: lead == null ? keep : '$lead $keep',
      extra: [
        if (message.details case final details?) TechDetails(text: details),
      ],
      actions: [
        ActionButton.recommended(
          key: ShellKeys.taskPrimary,
          text: context.strings.common.retry,
          icon: FluentIcons.arrow_clockwise_24_regular,
          size: ActionButtonSize.lg,
          autofocus: true,
          expand: true,
          onPressed: actions.onRetry,
        ),
        if (!app)
          ActionButton.neutral(
            key: ShellKeys.taskSecondary,
            text: library ? t.toLibraryPage : t.toPluginsPage,
            expand: true,
            onPressed: () => actions.onOpenPage(failure.stage),
          ),
        home,
      ],
    );
  }
}

final RegExp _rawError = RegExp(
  r'(Exception|Error)\b|errno|OS Error|Bad state|^\s*#\d',
);

/// מחלק הודעת כשל: שורה ראשונה מקומית לגוף, והשאר (או הכול, כשהשורה היא
/// טקסט חריג שלא עבר לוקליזציה) ל"פרטים טכניים".
({String? body, String? details}) splitFailureMessage(String? message) {
  final text = message?.trim();
  if (text == null || text.isEmpty) return (body: null, details: null);
  final lines = text.split('\n');
  final first = lines.first.trim();
  if (_rawError.hasMatch(first)) return (body: null, details: text);
  final rest = lines.skip(1).join('\n').trim();
  return (body: first, details: rest.isEmpty ? null : rest);
}

Widget _logo(double size) => Image.asset(
      'assets/images/otzaria_logo.png',
      width: size,
      height: size,
    );

/// אריח 64 מעל כותרת השאלה.
class _BigTile extends StatelessWidget {
  const _BigTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.only(bottom: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: IconTheme(
        data: IconThemeData(color: cs.onSecondaryContainer),
        child: child,
      ),
    );
  }
}

class _Deliveries extends StatelessWidget {
  const _Deliveries({required this.rows});

  final List<PluginDelivery> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  switch (row.state) {
                    PluginDeliveryState.sent => Icon(
                        FluentIcons.send_16_regular,
                        size: 16,
                        color: cs.primary,
                      ),
                    PluginDeliveryState.failed => Icon(
                        FluentIcons.dismiss_circle_16_regular,
                        size: 16,
                        color: cs.error,
                      ),
                    PluginDeliveryState.waiting => SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                          backgroundColor: cs.secondaryContainer,
                        ),
                      ),
                  },
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${row.name} · ${switch (row.state) {
                        PluginDeliveryState.sent => t.pluginRowSent,
                        PluginDeliveryState.failed => t.pluginRowFailed,
                        PluginDeliveryState.waiting => t.pluginRowWaiting,
                      }}',
                      style: AppTextStyles.small.copyWith(color: cs.onSurface),
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
