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
}) async {
  await otzaria.checkForUpdate();
  if (before.answeredDuringDownload(library.onlineCheckedAt)) {
    library.restoreOnlineAnswers(before.libraryAnswers);
  }
  await library.checkForUpdate();
  if (before.answeredDuringDownload(plugins.onlineCheckedAt)) {
    plugins.restoreCatalogOnlineAnswers(before.catalogAnswers);
  }
  if (before.answeredDuringDownload(plugins.storeAppCheckedAt)) {
    plugins.restoreStoreAppOnlineAnswers(before.storeAppAnswers);
  }
  await plugins.load();
}
