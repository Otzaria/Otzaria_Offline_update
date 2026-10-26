import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'sub_page_header.dart';

/// גוף דף (`.page`): כותרת והסבר, ורשימת כרטיסים עד 720 ממורכזת. דף
/// שכרטיס המצב שלו נושא את השם — בלי [title].
class ScreenBody extends StatelessWidget {
  final String? title;
  final String? description;
  final List<Widget> children;
  final ScrollController? controller;

  const ScreenBody({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const padding = LayoutConstraints.pagePadding;
    final header = SubPageHeaderScope.maybeOf(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: LayoutConstraints.panelContentMaxWidth + padding.horizontal,
        ),
        child: ListView(
          controller: controller,
          padding: padding,
          children: [
            if (header != null) header,
            if (title != null)
              Padding(
                padding: EdgeInsets.only(bottom: description != null ? 20 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      style:
                          AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        style: AppTextStyles.body.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}
