import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';

void main() {
  late ShellTasks tasks;
  setUp(() => tasks = ShellTasks());
  tearDown(() => tasks.dispose());

  int startHiddenUpdateOverDownload() {
    tasks.downloadRunning(const [MirrorComponent.plugins]);
    tasks.hideDownload();
    final id = tasks.startUpdateHere(const [GuidanceItem.library]);
    tasks.hideUpdate();
    expect(tasks.current, isNull);
    return id;
  }

  test('hidden update question takes priority over a completed download',
      () async {
    final id = startHiddenUpdateOverDownload();
    tasks.downloadDone();
    expect(tasks.current, isA<DownloadTask>());
    final decision = tasks.askToCloseOtzaria();
    expect(tasks.current, same(tasks.updateTask));
    expect(tasks.updateHidden, isFalse);
    expect(tasks.isCurrentUpdate(id), isTrue);
    tasks.respond(true);
    expect(await decision, isTrue);
    expect(tasks.current, same(tasks.updateTask));
    tasks.updateDone();
    tasks.dismiss();
    expect((tasks.current! as DownloadTask).phase, DownloadTaskPhase.done);
  });

  test('hidden update failure is foregrounded without losing the download', () {
    final id = startHiddenUpdateOverDownload();
    tasks.updateFailed(const UpdateFailure(GuidanceItem.library));
    expect(tasks.current, same(tasks.updateTask));
    expect(tasks.updateTask!.phase, UpdateHereTaskPhase.failed);
    expect(tasks.isCurrentUpdate(id), isTrue);
    tasks.dismiss();
    expect(tasks.downloadInProgress, isTrue);
    expect(tasks.anyRunning, isTrue);
    tasks.showDownload();
    expect((tasks.current! as DownloadTask).phase, DownloadTaskPhase.running);
  });

  test('switching visible tasks keeps both running task identities', () {
    final id = startHiddenUpdateOverDownload();
    tasks.showDownload();
    final download = tasks.current;
    expect(download, isA<DownloadTask>());
    tasks.hideDownload();
    tasks.showUpdate();
    expect(tasks.isCurrentUpdate(id), isTrue);
    expect(tasks.updateInProgress, isTrue);
    expect(tasks.downloadInProgress, isTrue);
    tasks.hideUpdate();
    tasks.downloadFailed(const DownloadFailure(DownloadFailureKind.network));
    expect((tasks.current! as DownloadTask).phase, DownloadTaskPhase.failed);
    tasks.dismiss();
    expect(tasks.current, isNull);
    expect(tasks.updateHidden, isTrue);
    tasks.updateDone();
    expect(tasks.current, same(tasks.updateTask));
  });
}
