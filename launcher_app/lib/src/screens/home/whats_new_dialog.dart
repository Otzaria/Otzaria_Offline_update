import 'package:flutter/material.dart';

import '../../controllers/library_module_controller.dart';
import '../../controllers/otzaria_module_controller.dart';
import '../../flows/library_flows.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'home_view_model.dart';

/// "מה חדש?" מהבית: הערות הגרסה של התוכנה (הממתינה, או המותקנת כשאין
/// עדכון), ו"מה חדש בספרייה" כשיש.
Future<void> showHomeWhatsNewDialog(
  BuildContext context, {
  required OtzariaModuleController otzaria,
  required LibraryModuleController library,
}) {
  final app = whatsNewAppNotes(otzaria);
  final changes = library.changesNotes.isNotEmpty;
  final cs = Theme.of(context).colorScheme;
  final libraryTitle = context.strings.libraryScreen.changesTitle;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog.custom(
      title: app == null
          ? libraryTitle
          : context.strings.pages.appWhatsNew(displayVersion(app.version)),
      width: AppTokens.dialogWideWidth,
      customContent: Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (app != null) ...[
                if (app.installed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      context.strings.pages.appInstalledNotesCaption,
                      style: AppTextStyles.small.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ReleaseNotesCard(markdown: app.notes),
                if (changes) SectionLabel(libraryTitle),
              ],
              if (changes) LibraryChangesCard(library: library),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.recommended(
          text: context.strings.common.close,
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}
