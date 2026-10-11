import 'package:flutter/foundation.dart';

mixin DisposeGuard on ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

mixin SilentAfterDispose on DisposeGuard {
  @override
  void notifyListeners() {
    if (!isDisposed) super.notifyListeners();
  }
}
