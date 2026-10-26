/// צורת הריבוי לפי [count]. [one] — יחיד מנוסח ("תוסף אחד"); [two] — זוגי
/// בעברית ("שתי דקות"), ובלעדיו נופלים ל-[many].
String plural(
  int count, {
  required String one,
  String? two,
  required String many,
}) =>
    switch (count) {
      1 => one,
      2 => two ?? many,
      _ => many,
    };
