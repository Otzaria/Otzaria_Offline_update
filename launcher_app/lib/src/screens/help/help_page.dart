import 'package:flutter/material.dart';

import '../../controllers/faq_controller.dart';
import '../../settings/safer_mode.dart';
import '../../widgets/screen_body.dart';
import '../faq/faq_body.dart';

/// דף העזרה — נפתח מ-"?" שבשורת הכותרת, ומארח את השאלות הנפוצות.
/// הדף נשאר בנוי בין כניסות, ולכן כל כניסה מחזירה אותו לראש.
class HelpPage extends StatefulWidget {
  const HelpPage({
    super.key,
    required this.faq,
    this.saferMode,
    this.editRequests,
    this.active = true,
    this.readOnly = false,
  });

  final FaqController faq;
  final SaferModeGate? saferMode;

  /// "עריכת השאלות הנפוצות" שבהגדרות — ראו [FaqBody.editRequests].
  final ValueNotifier<bool>? editRequests;

  /// ראו [FaqBody.active].
  final bool active;
  final bool readOnly;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(HelpPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenBody(
        controller: _scroll,
        children: [
          FaqBody(
            faq: widget.faq,
            saferMode: widget.saferMode,
            editRequests: widget.editRequests,
            active: widget.active,
            readOnly: widget.readOnly,
          ),
        ],
      );
}
