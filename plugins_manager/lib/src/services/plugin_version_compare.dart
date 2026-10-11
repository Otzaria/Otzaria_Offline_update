int comparePluginVersions(String? a, String? b) =>
    _compare(_parts(a), _parts(b));

int compareAppVersions(String? a, String? b) =>
    _compare(_parts(a).take(3).toList(), _parts(b).take(3).toList());

int _compare(List<int> pa, List<int> pb) {
  final length = pa.length > pb.length ? pa.length : pb.length;

  for (var i = 0; i < length; i++) {
    final diff = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (diff != 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

final _leadingDigits = RegExp(r'^\d+');

List<int> _parts(String? version) {
  var text = (version ?? '0').trim();
  if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
  text = text.split('+').first.split('-').first;

  return text.split('.').map((segment) {
    final digits = _leadingDigits.firstMatch(segment.trim());
    return digits == null ? 0 : int.parse(digits.group(0)!);
  }).toList();
}
