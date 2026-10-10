/// נשיאת דיווחי טעויות של אוצריא מהמחשב הלא-מקוון אל השרת, והדיווחים של
/// הלאנצ'ר על עצמו — ראו README.
library;

export 'src/launcher_report/app_report_service.dart';
export 'src/launcher_report/crash_report_flow.dart';
export 'src/launcher_report/launcher_log.dart';
export 'src/launcher_report/unclean_exit_detector.dart';
export 'src/models/outbox_report.dart';
export 'src/models/upload_result.dart' hide raceCancellation;
export 'src/port/app_report.dart';
export 'src/port/app_report_image.dart';
export 'src/port/app_report_redactor.dart';
export 'src/port/canonical_json.dart';
export 'src/port/crash_signature.dart';
export 'src/port/direct_error_report.dart';
export 'src/services/report_outbox.dart';
export 'src/services/report_uploader.dart';
export 'src/services/search_feedback_transport.dart';
export 'src/services/user_state_report_queue.dart';
