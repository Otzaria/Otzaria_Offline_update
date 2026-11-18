/// Receives one entry per finished install sub-stage (an English key such as
/// `talmud.swap`); the launcher formats it into its log. Null in tests and
/// tools, where timing is dropped.
void Function(String stage, double seconds)? installTimingSink;

/// Runs [body] and reports its [stage] key and duration, also on failure.
Future<T> timedInstallStage<T>(String stage, Future<T> Function() body) async {
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    final sink = installTimingSink;
    if (sink != null) {
      try {
        sink(stage, watch.elapsedMilliseconds / 1000);
      } catch (_) {}
    }
  }
}
