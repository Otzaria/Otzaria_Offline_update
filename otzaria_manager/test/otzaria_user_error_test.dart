import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

void main() {
  test('כשל למשתמש — הנוסח בלבד, בלי "Bad state: "', () {
    final error = OtzariaUserError('אוצריא לא נמצאה');
    expect(error, isA<StateError>());
    expect(error.toString(), 'אוצריא לא נמצאה');
    expect(OtzariaInstallNotDetected('x').toString(), 'x');
    // כשל פנימי נשאר כמו שהוא — ומסך המשימה שולח אותו ל"פרטים טכניים".
    expect(StateError('No element').toString(), 'Bad state: No element');
  });
}
