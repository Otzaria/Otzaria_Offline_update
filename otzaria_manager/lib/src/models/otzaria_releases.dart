class OtzariaReleases<T extends Object> {
  const OtzariaReleases({this.latest});
  final T? latest;
  bool get isEmpty => latest == null;
  List<T> get all => [if (latest != null) latest!];
}
