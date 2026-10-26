/// כשל שהנוסח שלו מתורגם ומיועד למשתמש — בלי הקידומת "Bad state: " של
/// [StateError], שנשארת לכשלים פנימיים (ושם הם עוברים ל"פרטים טכניים").
class OtzariaUserError extends StateError {
  OtzariaUserError(super.message);

  @override
  String toString() => message;
}
