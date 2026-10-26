import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../services/byte_size.dart';
import '../services/native_file_dialogs.dart';
import '../widgets/widgets_exports.dart';

Widget libraryApplyProgressRow(
  BuildContext context,
  LibraryModuleController c,
) =>
    ListenableBuilder(
      listenable: c.progress,
      builder: (context, _) => InfoProgressRow(
        stage: c.stageText ?? context.strings.libraryScreen.updatingProgress,
        progress: c.applyProgress,
        detail: formatBytesProgress(c.applyReceivedBytes, c.applyTotalBytes),
        warning: context.strings.home.doNotRemoveDriveWarning,
      ),
    );

/// "מה חדש בספרייה" — ההערות של כל הגרסאות שבטווח, החדשה קודם.
Future<void> showLibraryChangesDialog(
  BuildContext context,
  LibraryModuleController library,
) async {
  final notes = library.changesNotes;
  final parts = <String>[];
  for (final note in notes) {
    try {
      final markdown = (await note.readMarkdown()).trim();
      if (markdown.isNotEmpty) parts.add(markdown);
    } on FileSystemException {
      // כונן שנשלף — מה שנקרא מוצג, והשאר נאמר כ"לא נמצא".
    }
  }
  if (!context.mounted) return;
  final t = context.strings.libraryScreen;
  await showSingleActionDialog(
    context: context,
    title: t.changesTitle,
    confirmText: context.strings.common.close,
    customContent: LibraryChangesView(
      markdowns: parts,
      emptyText: t.changesNotFound,
      note: library.changesNotesPartial
          ? t.changesPartial(notes.length, library.changesNotesRange)
          : null,
    ),
  );
}

/// "מה חדש בספרייה" כרשימה קצרה; הרשימה המלאה נפתחת בחלון משלה, כי היא
/// יכולה למנות אלפי ספרים.
class LibraryChangesCard extends StatelessWidget {
  const LibraryChangesCard({super.key, required this.library});

  final LibraryModuleController library;

  @override
  Widget build(BuildContext context) {
    final c = library;
    final s = context.strings.libraryScreen;
    return NewsCard(
      items: [
        c.changesNotesApplied
            ? s.changesAppliedSubtitle('${c.changesNotesVersion}')
            : s.changesPendingSubtitle('${c.changesNotesVersion}'),
        if (c.changesNotesPartial)
          s.changesPartial(c.changesNotes.length, c.changesNotesRange),
      ],
      footer: ActionButton.ghost(
        text: s.changesButton,
        icon: FluentIcons.document_text_24_regular,
        size: ActionButtonSize.sm,
        onPressed: () => showLibraryChangesDialog(context, c),
      ),
    );
  }
}

/// בחירת קובץ הספרייה (`seforim.db`) במחשב הזה.
Future<void> pickLibraryDbFile(
  BuildContext context,
  LibraryModuleController library,
) async {
  final t = context.strings.libraryScreen;
  final path = await NativeFileDialogs.pickFile(
    dialogTitle: t.pickDbDialogTitle,
    allowedExtensions: const ['db'],
  );
  if (path == null || !context.mounted) return;
  if (!await _confirmLocationOutsideOtzaria(context, library, path)) return;
  await library.setCustomDbPath(path);
  UiSnack.showSuccess(t.dbPathUpdatedSnack);
}

/// התיקייה שאליה תותקן ספרייה חדשה, או שבה היא יושבת עכשיו.
Future<void> pickLibraryInstallDir(
  BuildContext context,
  LibraryModuleController library,
) async {
  final t = context.strings.libraryScreen;
  final dir = await NativeFileDialogs.pickDirectory(
    dialogTitle: t.pickInstallDirDialogTitle,
  );
  if (dir == null || !context.mounted) return;
  if (!await _confirmLocationOutsideOtzaria(
    context,
    library,
    library.dbPathIn(dir),
  )) {
    return;
  }
  await library.setInstallDir(dir);
  UiSnack.showSuccess(t.installDirUpdatedSnack);
}

/// מיקום שאוצריא אינה מחפשת בו מותר — אבל רק אחרי אזהרה מפורשת: היא לא
/// תראה שם ספרים עד שהמשתמש יצביע על התיקייה מתוך ההגדרות שלה.
Future<bool> _confirmLocationOutsideOtzaria(
  BuildContext context,
  LibraryModuleController library,
  String dbPath,
) async {
  if (await library.isDbPathKnownToOtzaria(dbPath)) return true;
  if (!context.mounted) return false;
  final t = context.strings.libraryScreen;
  return showTwoActionsDialog(
    context: context,
    title: t.customLocationDialogTitle,
    content: t.customLocationPrompt(dbPath),
    confirmText: t.customLocationConfirm,
  );
}

/// קוראת את גרסת המסד של המחשב הזה ורושמת אותה. snack ולא שדה מצב:
/// לחיצה שלא מצאה מסד היא מידע חד-פעמי, לא תקלה שנשארת בדף.
Future<void> capturePersonalVersion(
  BuildContext context,
  LibraryModuleController library,
) async {
  final t = context.strings.libraryScreen;
  final captured = await library.capturePersonalVersion();
  if (!context.mounted) return;
  if (captured) {
    UiSnack.showSuccess(
      t.personalVersionCapturedSnack('${library.personalFromVersion}'),
    );
  } else {
    UiSnack.showError(
      library.personalCaptureError ?? t.personalVersionNotFoundSnack,
    );
  }
}
