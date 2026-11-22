import 'dart:async';

import 'package:http/http.dart' as http;

Future<http.StreamedResponse> sendAbortableRequest(
  http.Client client,
  http.AbortableRequest request,
  Completer<void> abort, {
  RequestCancellation? cancellation,
}) {
  cancellation?.abort = abort;
  final pending = client.send(request);
  unawaited(
    pending.then((response) async {
      if (abort.isCompleted) {
        try {
          await response.stream.listen((_) {}).cancel();
        } catch (_) {}
      }
    }, onError: (Object _) {}),
  );
  return cancellation?.wait(pending) ?? pending;
}

class RequestCancellation {
  RequestCancellation(this._check) {
    _cancelled.future.ignore();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      try {
        check();
      } catch (_) {}
    });
  }

  final void Function() _check;
  final _cancelled = Completer<Never>();
  late final Timer _timer;
  Completer<void>? abort;
  Object? _error;
  StackTrace? _stack;

  void check() {
    if (_error case final error?) Error.throwWithStackTrace(error, _stack!);
    try {
      _check();
    } catch (error, stack) {
      _error = error;
      _stack = stack;
      _timer.cancel();
      if (abort case final requestAbort? when !requestAbort.isCompleted) {
        requestAbort.complete();
      }
      _cancelled.completeError(error, stack);
      rethrow;
    }
  }

  Future<T> wait<T>(Future<T> pending) =>
      Future.any([pending, _cancelled.future]);

  Stream<T> bind<T>(Stream<T> source) => Stream<T>.multi((controller) {
        var active = true;
        final subscription = source.listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: () {
            active = false;
            controller.closeSync();
          },
        );
        controller.onPause = subscription.pause;
        controller.onResume = subscription.resume;
        controller.onCancel = () {
          active = false;
          return subscription.cancel();
        };
        unawaited(
          _cancelled.future.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              if (active) controller.addError(error, stack);
            },
          ),
        );
      });

  void dispose() => _timer.cancel();
}
