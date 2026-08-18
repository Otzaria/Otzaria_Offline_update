import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/faq_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'faq_dialog.dart';

/// קוטר הכפתור העגול.
const double _buttonSize = 44;

/// הרווח בין הכפתור לבועה שמעליו.
const double _bubbleGap = AppTokens.spaceSM;

/// אורך מחזור הבהוב אחד, וכמה מחזורים הוא רץ בפתיחת התוכנה.
const Duration _pulseCycle = Duration(milliseconds: 1100);
const int _defaultPulseCycles = 3;

/// כמה זמן הבועה נשארת פתוחה, ואחרי כמה זמן היא נפתחת. ההשהיה קיימת כדי
/// שהבועה לא תוצג לפני שהחלון עצמו נצבע.
const Duration _bubbleVisible = Duration(seconds: 2);
const Duration _bubbleDelay = Duration(milliseconds: 500);

/// כפתור "שאלות נפוצות" הצף בפינה התחתונה שממול לסרגל הניווט — בעברית משמאל,
/// באנגלית מימין.
///
/// בפתיחת התוכנה הוא מהבהב כמה מחזורים ופותח בועה עם שמו לשתי שניות — משתמש
/// שאינו מחפש עזרה לא ימצא כפתור עגול קטן בפינה מעצמו. שניהם חד-פעמיים
/// להרצה: הם רצים ב-`initState`, וה-state נשמר בין בניות של המסגרת.
class FaqFloatingButton extends StatefulWidget {
  const FaqFloatingButton({
    super.key,
    required this.faq,
    this.showIntro = true,
  });

  /// ההתאמות שהמשתמש עשה להדרכה — נמסרות לדיאלוג, שהוא גם מי שעורך אותן.
  final FaqController faq;

  /// כיבוי ההבהוב והבועה — לבדיקות, ולכל מקום שבו הכפתור אינו "חדש" למשתמש.
  final bool showIntro;

  @override
  State<FaqFloatingButton> createState() => _FaqFloatingButtonState();
}

class _FaqFloatingButtonState extends State<FaqFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _pulseCycle,
  );

  /// מספר סופי של מחזורים ולא `repeat()`: טבעת שמהבהבת לנצח בפינה היא נדנוד,
  /// וגם הייתה משאירה אנימציה תלויה לכל אורך ההרצה.
  int _cyclesLeft = 0;

  bool _bubbleOpen = false;
  Timer? _bubbleTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.showIntro) return;

    _cyclesLeft = _defaultPulseCycles;
    _pulse.addStatusListener(_onPulseDone);
    _pulse.forward();

    _bubbleTimer = Timer(_bubbleDelay, () {
      if (!mounted) return;
      setState(() => _bubbleOpen = true);
      _bubbleTimer = Timer(_bubbleVisible, () {
        if (mounted) setState(() => _bubbleOpen = false);
      });
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onPulseDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (--_cyclesLeft <= 0) return;
    _pulse
      ..reset()
      ..forward();
  }

  /// הבועה נסגרת מיד כשההדרכה נפתחת — היא כבר עשתה את שלה.
  Future<void> _open() async {
    _bubbleTimer?.cancel();
    if (_bubbleOpen) setState(() => _bubbleOpen = false);
    await showFaqDialog(context, faq: widget.faq);
  }

  @override
  Widget build(BuildContext context) {
    // הבועה יושבת ב-Positioned מעל הכפתור, ולכן אינה משתתפת במידות ה-Stack:
    // הגודל נקבע בידי הכפתור לבדו, וכך גם ב-RTL וגם ב-LTR הכול נשאר בפינה.
    // היא נצמדת לקצה ה-end כמו הכפתור, ולכן נפתחת פנימה ולא אל מחוץ לחלון.
    return Stack(
      alignment: AlignmentDirectional.bottomEnd,
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          end: 0,
          bottom: _buttonSize + _bubbleGap,
          child: _Bubble(isOpen: _bubbleOpen),
        ),
        _button(context),
      ],
    );
  }

  Widget _button(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // הטבעת נמדדת כמו הכפתור ומוגדלת ב-Transform, כדי שההבהוב לא יזיז
        // כלום בפריסה.
        Positioned.fill(child: IgnorePointer(child: _pulseRing(context))),
        Tooltip(
          message: context.strings.faq.title,
          child: Material(
            color: cs.primaryContainer,
            surfaceTintColor: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: AppTokens.elevation2,
            child: InkWell(
              onTap: () => unawaited(_open()),
              mouseCursor: SystemMouseCursors.click,
              child: SizedBox(
                width: _buttonSize,
                height: _buttonSize,
                child: Center(
                  child: Icon(
                    FluentIcons.question_circle_24_regular,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pulseRing(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: 1.8).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeOut),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppSurfaces.faqPulseRing(context),
            ),
          ),
        ),
      );
}

/// בועת השיחה שמעל הכפתור. `IgnorePointer` כדי שלא תחסום את הכפתור בזמן
/// שהיא נעלמת.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: isOpen ? 1 : 0,
        duration: AppTokens.animNormal,
        child: Container(
          decoration: ShapeDecoration(
            color: theme.colorScheme.inverseSurface,
            shape: const _BubbleBorder(),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceSM,
          ),
          child: Text(
            context.strings.faq.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// מסגרת הבועה: מלבן מעוגל וזנב קטן בתחתיתו, שמצביע על הכפתור.
///
/// הזנב יושב בקצה ה-start של הבועה — כמו הכפתור עצמו — ולכן הוא מתהפך עם
/// כיוון הכתיבה: בעברית משמאל, באנגלית מימין.
class _BubbleBorder extends ShapeBorder {
  const _BubbleBorder();

  static const double _tailHeight = 7;
  static const double _tailWidth = 14;
  static const double _tailInset = (_buttonSize - _tailWidth) / 2;

  @override
  EdgeInsetsGeometry get dimensions =>
      const EdgeInsets.only(bottom: _tailHeight);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(
      rect.left,
      rect.top,
      rect.right,
      rect.bottom - _tailHeight,
    );
    final tailStart = textDirection == TextDirection.rtl
        ? body.left + _tailInset
        : body.right - _tailInset - _tailWidth;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        body,
        const Radius.circular(AppTokens.radius),
      ))
      ..moveTo(tailStart, body.bottom)
      ..lineTo(tailStart + _tailWidth / 2, rect.bottom)
      ..lineTo(tailStart + _tailWidth, body.bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => const _BubbleBorder();
}
