/// נשיאת דיווחי טעויות של אוצריא מהמחשב הלא-מקוון אל השרת — ראו README.
library;

export 'src/models/outbox_report.dart';
export 'src/models/upload_result.dart' hide raceCancellation;
export 'src/port/canonical_json.dart';
export 'src/port/direct_error_report.dart';
export 'src/services/report_outbox.dart';
export 'src/services/report_uploader.dart';
export 'src/services/user_state_report_queue.dart';
