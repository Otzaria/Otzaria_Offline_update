/// Wraps every start of a program the user keeps using: Windows hands a
/// below-normal priority class to the child, so the launcher lifts it here.
Future<T> Function<T>(Future<T> Function() start) aroundChildStart = _startAsIs;

Future<T> _startAsIs<T>(Future<T> Function() start) => start();
