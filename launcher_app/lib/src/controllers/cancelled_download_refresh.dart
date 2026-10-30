import 'download_plan.dart';
import 'library_module_controller.dart';
import 'otzaria_module_controller.dart';
import 'plugins_module_controller.dart';

class OnlineAnswersBeforeDownload {
  OnlineAnswersBeforeDownload.capture({
    required LibraryModuleController library,
    required PluginsModuleController plugins,
  })  : startedAt = DateTime.now(),
        libraryAnswers = library.onlineAnswers,
        catalogAnswers = plugins.catalogOnlineAnswers,
        storeAppAnswers = plugins.storeAppOnlineAnswers;

  final DateTime startedAt;
  final LibraryOnlineAnswers libraryAnswers;
  final PluginsCatalogOnlineAnswers catalogAnswers;
  final StoreAppOnlineAnswers storeAppAnswers;

  bool answeredDuringDownload(DateTime? checkedAt) =>
      checkedAt != null && !checkedAt.isBefore(startedAt);
}

Future<void> refreshAfterCancelledDownload({
  required OtzariaModuleController otzaria,
  required LibraryModuleController library,
  required PluginsModuleController plugins,
  required OnlineAnswersBeforeDownload before,
  required Set<MirrorComponent> reverted,
}) async {
  // רכיב שנשאר בכונן שומר את תשובות הרשת שנמדדו מולו בזמן ההורדה.
  await otzaria.checkForUpdate();
  if (reverted.contains(MirrorComponent.library) &&
      before.answeredDuringDownload(library.onlineCheckedAt)) {
    library.restoreOnlineAnswers(before.libraryAnswers);
  }
  await library.checkForUpdate();
  if (reverted.contains(MirrorComponent.plugins)) {
    if (before.answeredDuringDownload(plugins.onlineCheckedAt)) {
      plugins.restoreCatalogOnlineAnswers(before.catalogAnswers);
    }
    if (before.answeredDuringDownload(plugins.storeAppCheckedAt)) {
      plugins.restoreStoreAppOnlineAnswers(before.storeAppAnswers);
    }
  }
  // סנכרון או מסירה שרצים במקביל: טעינה באמצעם דורסת את מצבם; הסנכרון טוען בסופו.
  if (!plugins.isSyncing &&
      !plugins.isUpdatingAll &&
      !plugins.isDeliveringAny) {
    await plugins.load();
  }
}
