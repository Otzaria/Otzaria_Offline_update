import 'package:flutter/material.dart';

/// הלוגו של אוצריא — באריח של "אוצריא פתוחה כרגע" ובכל מקום שמדבר עליה.
class OtzariaLogo extends StatelessWidget {
  const OtzariaLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/otzaria_logo.png',
        width: size,
        height: size,
        excludeFromSemantics: true,
      );
}
