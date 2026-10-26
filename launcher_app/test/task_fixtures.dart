import 'package:flutter/material.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/screens/tasks/download_task_view.dart';
import 'package:launcher_app/src/screens/tasks/update_here_task_view.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';

/// מצבי מסכי המשימה כמו במוקאפ — לבדיקות ולצילומי הסקירה.
const _all = [
  MirrorComponent.app,
  MirrorComponent.library,
  MirrorComponent.plugins,
];

final Map<String, DownloadTask> downloadScenarios = {
  'semantic': const DownloadTask(phase: DownloadTaskPhase.question),
  'preparing': const DownloadTask(phase: DownloadTaskPhase.preparing),
  'download': const DownloadTask(
    phase: DownloadTaskPhase.running,
    components: _all,
  ),
  'cancelled': const DownloadTask(
    phase: DownloadTaskPhase.cancelled,
    components: _all,
  ),
  'dlDone': const DownloadTask(
    phase: DownloadTaskPhase.done,
    components: _all,
  ),
  'dlError': const DownloadTask(
    phase: DownloadTaskPhase.failed,
    components: _all,
    failure: DownloadFailure(
      DownloadFailureKind.network,
      components: [MirrorComponent.library],
      details: 'library: SocketException: Connection reset by peer '
          '(OS Error 10054)',
    ),
  ),
  'dlBlocked': const DownloadTask(
    phase: DownloadTaskPhase.failed,
    components: _all,
    failure: DownloadFailure(
      DownloadFailureKind.blocked,
      components: [MirrorComponent.library],
      details: 'library: HandshakeException: Handshake error in client '
          '(OS Error: CERTIFICATE_VERIFY_FAILED: unable to get local issuer '
          'certificate)',
    ),
  ),
  'dlNothing': const DownloadTask(
    phase: DownloadTaskPhase.done,
    skipped: _all,
  ),
  'dlShabbat': const DownloadTask(
    phase: DownloadTaskPhase.failed,
    components: _all,
    failure: DownloadFailure(
      DownloadFailureKind.shabbat,
      components: [MirrorComponent.plugins],
    ),
  ),
  'dlFail': const DownloadTask(
    phase: DownloadTaskPhase.failed,
    components: _all,
    failure: DownloadFailure(
      DownloadFailureKind.other,
      components: [MirrorComponent.library],
      details: 'library: SHA-256 mismatch',
    ),
  ),
  'dlSpace': const DownloadTask(
    phase: DownloadTaskPhase.failed,
    components: _all,
    failure: DownloadFailure(
      DownloadFailureKind.diskSpace,
      components: [MirrorComponent.library],
      needed: '1.2 GB',
      free: '0.4 GB',
    ),
  ),
};

/// ההתקדמות של צילום "download": הספרייה באמצע.
const downloadProgressSnapshot = DownloadSnapshot(
  current: MirrorComponent.library,
  fraction: 0.42,
  received: 403 * 1024 * 1024,
  total: 960 * 1024 * 1024,
);

const downloadDoneInfo = DownloadDoneInfo(
  appVersion: '0.9.96',
  libraryVersion: 27,
  pluginCount: 12,
  offer: DownloadHereOffer.update,
);

const _update = [GuidanceItem.library, GuidanceItem.app, GuidanceItem.plugins];
const _plugins = [
  PluginDelivery('לוח שנה עברי', PluginDeliveryState.sent),
  PluginDelivery('מזומנים', PluginDeliveryState.waiting),
];

final Map<String, UpdateHereTask> updateScenarios = {
  'otherUser': const UpdateHereTask(
    phase: UpdateHereTaskPhase.confirmElevatedOtherUser,
    stages: _update,
    account: 'Admin',
  ),
  'close': const UpdateHereTask(
    phase: UpdateHereTaskPhase.closeOtzaria,
    stages: _update,
    plugins: _plugins,
  ),
  'instLib': const UpdateHereTask(
    phase: UpdateHereTaskPhase.running,
    stages: _update,
    libraryVersion: 27,
    appVersion: '0.9.96',
    plugins: _plugins,
  ),
  'instApp': const UpdateHereTask(
    phase: UpdateHereTaskPhase.running,
    stages: _update,
    stageIndex: 1,
    libraryVersion: 27,
    appVersion: '0.9.96',
    outcomes: {GuidanceItem.library: StageOutcome.done},
    plugins: _plugins,
  ),
  'instPlug': const UpdateHereTask(
    phase: UpdateHereTaskPhase.running,
    stages: _update,
    stageIndex: 2,
    libraryVersion: 27,
    appVersion: '0.9.96',
    outcomes: {
      GuidanceItem.library: StageOutcome.done,
      GuidanceItem.app: StageOutcome.done,
    },
    plugins: _plugins,
  ),
  'installDone': const UpdateHereTask(
    phase: UpdateHereTaskPhase.done,
    stages: _update,
    stageIndex: 3,
    libraryVersion: 27,
    appVersion: '0.9.96',
    outcomes: {
      GuidanceItem.library: StageOutcome.done,
      GuidanceItem.app: StageOutcome.done,
      GuidanceItem.plugins: StageOutcome.done,
    },
    plugins: [
      PluginDelivery('לוח שנה עברי', PluginDeliveryState.sent),
      PluginDelivery('מזומנים', PluginDeliveryState.sent),
    ],
  ),
  'stoppedDone': const UpdateHereTask(
    phase: UpdateHereTaskPhase.done,
    stages: _update,
    stageIndex: 3,
    libraryVersion: 27,
    appVersion: '0.9.96',
    outcomes: {
      GuidanceItem.library: StageOutcome.done,
      GuidanceItem.app: StageOutcome.stoppedWaiting,
      GuidanceItem.plugins: StageOutcome.skipped,
    },
    plugins: _plugins,
  ),
  'pluginsMixed': const UpdateHereTask(
    phase: UpdateHereTaskPhase.done,
    stages: [GuidanceItem.plugins],
    stageIndex: 1,
    outcomes: {GuidanceItem.plugins: StageOutcome.done},
    plugins: [
      PluginDelivery('לוח שנה עברי', PluginDeliveryState.sent),
      PluginDelivery('מזומנים', PluginDeliveryState.failed),
    ],
  ),
  'libraryNote': const UpdateHereTask(
    phase: UpdateHereTaskPhase.done,
    stages: [GuidanceItem.app, GuidanceItem.library],
    stageIndex: 2,
    firstInstall: true,
    appVersion: '0.10.4',
    outcomes: {
      GuidanceItem.app: StageOutcome.done,
      GuidanceItem.library: StageOutcome.done,
    },
    libraryNote: 'אוצריא עוד לא מכוונת לספרייה החדשה — בחר אותה בהגדרות '
        'אוצריא.',
  ),
  'firstStopped': const UpdateHereTask(
    phase: UpdateHereTaskPhase.cancelledByUser,
    stages: [GuidanceItem.app, GuidanceItem.library],
    firstInstall: true,
    appVersion: '0.10.4',
    outcomes: {GuidanceItem.app: StageOutcome.stoppedWaiting},
  ),
  'wizardStillOpen': const UpdateHereTask(
    phase: UpdateHereTaskPhase.cancelledByUser,
    stages: [GuidanceItem.library, GuidanceItem.app],
    stageIndex: 1,
    outcomes: {
      GuidanceItem.library: StageOutcome.done,
      GuidanceItem.app: StageOutcome.stillOpen,
    },
  ),
  'wizardClosed': const UpdateHereTask(
    phase: UpdateHereTaskPhase.cancelledByUser,
    stages: [GuidanceItem.library, GuidanceItem.app],
    stageIndex: 1,
    outcomes: {GuidanceItem.library: StageOutcome.done},
  ),
  'instFail': const UpdateHereTask(
    phase: UpdateHereTaskPhase.failed,
    stages: [GuidanceItem.library, GuidanceItem.app],
    failure: UpdateFailure(
      GuidanceItem.library,
      message: 'אין מספיק מקום פנוי בכונן C: כדי לעדכן את הספרייה: נדרשים '
          '2.4 GB ופנויים 0.9 GB.',
    ),
  ),
  'appFail': const UpdateHereTask(
    phase: UpdateHereTaskPhase.failed,
    stages: [GuidanceItem.app],
    failure: UpdateFailure(
      GuidanceItem.app,
      message: 'לא הצלחנו להעתיק את קובץ ההתקנה מהכונן.',
    ),
  ),
  'instFailAdmin': const UpdateHereTask(
    phase: UpdateHereTaskPhase.failed,
    stages: [GuidanceItem.app],
    failure: UpdateFailure(
      GuidanceItem.app,
      message: 'Access is denied (OS Error 5)\n'
          r'path: C:\Program Files\Otzaria\otzaria.exe',
      needsElevation: true,
    ),
  ),
  'firstFailAdmin': const UpdateHereTask(
    phase: UpdateHereTaskPhase.failed,
    stages: [GuidanceItem.app, GuidanceItem.library],
    firstInstall: true,
    failure: UpdateFailure(
      GuidanceItem.app,
      message: 'Access is denied (OS Error 5)',
      needsElevation: true,
    ),
  ),
  'pluginsFail': const UpdateHereTask(
    phase: UpdateHereTaskPhase.failed,
    stages: _update,
    stageIndex: 2,
    appVersion: '0.10.4',
    outcomes: {
      GuidanceItem.library: StageOutcome.done,
      GuidanceItem.app: StageOutcome.done,
    },
    failure: UpdateFailure(
      GuidanceItem.plugins,
      message: 'FileSystemException: Cannot copy file',
    ),
  ),
  'firstClose': const UpdateHereTask(
    phase: UpdateHereTaskPhase.closeOtzaria,
    stages: [GuidanceItem.app, GuidanceItem.library],
    stageIndex: 1,
    firstInstall: true,
    closeAfterWizard: true,
    appVersion: '0.10.4',
    outcomes: {GuidanceItem.app: StageOutcome.done},
  ),
  'firstDone': const UpdateHereTask(
    phase: UpdateHereTaskPhase.done,
    stages: [GuidanceItem.app, GuidanceItem.library],
    stageIndex: 2,
    firstInstall: true,
    appVersion: '0.10.4',
    outcomes: {
      GuidanceItem.app: StageOutcome.done,
      GuidanceItem.library: StageOutcome.done,
    },
  ),
};

/// מסך משימה בודד מהמצבים שלמעלה, עם פעולות שנרשמות ב-[calls].
Widget taskScenario(
  String name, {
  List<String>? calls,
  bool canRemember = true,
}) {
  void call(String what) => calls?.add(what);
  final download = downloadScenarios[name];
  if (download != null) {
    return DownloadTaskView(
      task: download,
      canRemember: canRemember,
      progress: ValueNotifier(0),
      snapshot: () => downloadProgressSnapshot,
      done: downloadDoneInfo,
      actions: DownloadTaskActions(
        onAnswer: (v) => call(
          v == null
              ? 'answer null'
              : 'answer ${v.download} remember=${v.remember}',
        ),
        onCancel: () => call('cancel'),
        onRetry: () => call('retry'),
        onHome: () => call('home'),
        onHere: () => call('here'),
        onCancelPreparing: () => call('cancel preparing'),
      ),
    );
  }
  final update = updateScenarios[name]!;
  return UpdateHereTaskView(
    task: update,
    libraryProgress: ValueNotifier(0),
    librarySnapshot: () => const LibraryApplySnapshot(fraction: 0.46),
    actions: UpdateHereActions(
      onRespond: (v) => call('respond $v'),
      onStopWaiting: () => call('stop waiting'),
      onFinishWithoutWaiting: () => call('finish now'),
      onLaunch: () => call('launch'),
      onHome: () => call('home'),
      onRetry: () => call('retry'),
      onOpenPage: (stage) => call('page ${stage.name}'),
      onReindex: name == 'installDone' ? () => call('reindex') : null,
      onRestartElevated:
          name.endsWith('FailAdmin') ? () => call('elevate') : null,
    ),
  );
}

/// [taskScenario] מתחת לפס בגובה שורת הכותרת — כמו בחלון האמיתי.
Widget taskScenarioInWindow(String name, {List<String>? calls}) => Column(
      children: [
        const SizedBox(height: 36),
        Expanded(child: taskScenario(name, calls: calls)),
      ],
    );

List<String> get taskScenarioNames =>
    [...downloadScenarios.keys, ...updateScenarios.keys];
