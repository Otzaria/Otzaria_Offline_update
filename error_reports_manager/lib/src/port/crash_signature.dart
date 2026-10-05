/// חתימת קריסה: סוג החריגה ועד 3 פריימים מנורמלים, לקיבוץ דיווחים זהים בשרת.
class CrashSignature {
  const CrashSignature({required this.exceptionType, required this.frames});

  static const int maxFrames = 3;
  static const int maxExceptionTypeLength = 200;
  static const int maxFrameLength = 300;

  final String exceptionType;
  final List<String> frames;

  static CrashSignature? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['exceptionType'];
    if (type is! String) return null;
    final frames = json['frames'];
    return CrashSignature(
      exceptionType: type,
      frames: frames is List
          ? frames.whereType<String>().toList()
          : const <String>[],
    );
  }
}
