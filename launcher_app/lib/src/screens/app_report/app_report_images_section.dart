import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/app_logger.dart';
import '../../services/image_clipboard.dart';
import '../../services/native_file_dialogs.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// מקור התמונות: בחירת קבצים. מוזרק בבדיקות — דיאלוג המערכת אינו רץ שם.
/// הדבקה מהלוח: `ImageClipboard`. גרירה (באוצריא) לא פורטה.
class AppReportImageSource {
  const AppReportImageSource();

  Future<PickedImages> pickFiles(
    String dialogTitle,
    List<AppReportImage> existing,
  ) async {
    final paths = await NativeFileDialogs.pickManyFiles(
      dialogTitle: dialogTitle,
      allowedExtensions: AppReportImage.supportedExtensions,
    );
    return loadPaths(paths, existing: existing);
  }

  /// קורא את הקבצים: הגודל נבדק **לפני** הקריאה (קובץ של מאות מגה-בתים אינו
  /// נטען לזיכרון), וה-`mimeType` נקבע מהבייטים ולא מהסיומת.
  ///
  /// הקריאה נעצרת כשהמכסה (מספר או נפח כולל, כולל [existing]) מלאה — קבצים
  /// שאחריה אינם נקראים כלל, ו-[PickedImages.limit] אומר למה.
  static Future<PickedImages> loadPaths(
    List<String> paths, {
    List<AppReportImage> existing = const [],
  }) async {
    final images = <AppReportImage>[];
    var tooLarge = false;
    var unreadable = 0;
    AppReportImageRejection? limit;
    var total = existing.fold<int>(0, (sum, i) => sum + i.bytes.length);
    for (final path in paths) {
      if (existing.length + images.length >= AppReportImage.maxCount) {
        limit = AppReportImageRejection.tooMany;
        break;
      }
      try {
        final file = File(path);
        final length = await file.length();
        if (length > AppReportImage.maxBytes) {
          tooLarge = true;
          continue;
        }
        if (total + length > AppReportImage.maxTotalBytes) {
          limit = AppReportImageRejection.totalTooLarge;
          continue; // קובץ קטן יותר שאחריו עדיין עשוי להיכנס
        }
        final bytes = await file.readAsBytes();
        final mimeType = AppReportImage.sniffMimeType(bytes);
        if (mimeType == null) {
          unreadable++;
          continue;
        }
        total += bytes.length;
        images.add(
          AppReportImage(
            bytes: bytes,
            fileName: p.basename(path),
            mimeType: mimeType,
          ),
        );
      } on FileSystemException {
        unreadable++;
      }
    }
    return PickedImages(
      images,
      tooLarge: tooLarge,
      unreadable: unreadable,
      limit: limit,
    );
  }
}

/// מה שנבחר: התמונות התקינות, ומה שנדחה ולמה.
class PickedImages {
  const PickedImages(
    this.images, {
    this.tooLarge = false,
    this.unreadable = 0,
    this.limit,
  });

  final List<AppReportImage> images;

  /// קובץ אחד לפחות גדול מ-[AppReportImage.maxBytes] ולא נקרא.
  final bool tooLarge;

  /// קבצים שאינם PNG/JPEG/GIF בפועל, או שלא ניתן היה לקרוא.
  final int unreadable;

  /// המכסה שהקריאה נעצרה בה (מספר תמונות או נפח כולל), או `null`.
  final AppReportImageRejection? limit;
}

/// אזור צירוף צילומי מסך: לחיצה לבחירת קובץ, ומתחתיו התמונות שצורפו.
class AppReportImagesSection extends StatefulWidget {
  const AppReportImagesSection({
    super.key,
    required this.images,
    required this.onChanged,
    this.enabled = true,
    this.otherAttachmentBytes = 0,
    this.source = const AppReportImageSource(),
    this.clipboard = const SystemImageClipboard(),
  });

  final List<AppReportImage> images;
  final ValueChanged<List<AppReportImage>> onChanged;
  final bool enabled;
  final int otherAttachmentBytes;
  final AppReportImageSource source;
  final ImageClipboard clipboard;

  @override
  State<AppReportImagesSection> createState() => _AppReportImagesSectionState();
}

class _AppReportImagesSectionState extends State<AppReportImagesSection> {
  bool _pasting = false;

  List<AppReportImage> get images => widget.images;
  bool get enabled => widget.enabled;
  AppReportImageSource get source => widget.source;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl+V (Cmd+V ב-macOS) מצרף תמונה רק כשבלוח יש תמונה ואין טקסט; אחרת
  /// האירוע עובר כמות שהוא, והדבקת טקסט בשדות לא משתנה.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!modifier || !enabled || _pasting) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (!widget.clipboard.isSupported ||
        !widget.clipboard.holdsImageWithoutText) {
      return false;
    }
    unawaited(_paste());
    return false;
  }

  Future<void> _paste() async {
    if (_pasting) return;
    _pasting = true;
    final t = context.strings.appReports;
    try {
      final ClipboardImages? content;
      try {
        content = await widget.clipboard.read();
      } catch (error, stack) {
        AppLogger.maybeInstance
            ?.error('הדבקת תמונה לדיווח נכשלה', error, stack);
        if (mounted) UiSnack.showError(t.imageReadFailed);
        return;
      }
      if (!mounted) return;
      if (content == null) {
        UiSnack.showError(t.clipboardHasNoImage);
        return;
      }
      final PickedImages picked;
      if (content.tooLarge) {
        picked = const PickedImages([], tooLarge: true);
      } else if (content.paths.isNotEmpty) {
        picked = await AppReportImageSource.loadPaths(
          content.paths,
          existing: images,
        );
      } else {
        final bytes = content.bytes;
        final mime = bytes == null ? null : AppReportImage.sniffMimeType(bytes);
        if (bytes == null || mime == null) {
          picked = const PickedImages([], unreadable: 1);
        } else if (bytes.length > AppReportImage.maxBytes) {
          picked = const PickedImages([], tooLarge: true);
        } else {
          picked = PickedImages([
            AppReportImage(
              bytes: bytes,
              fileName: _clipboardFileName(mime),
              mimeType: mime,
            ),
          ]);
        }
      }
      if (!mounted) return;
      _apply(picked);
    } finally {
      _pasting = false;
    }
  }

  static String _clipboardFileName(String mime) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ext = switch (mime) {
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
      _ => 'png',
    };
    return 'clipboard-${n.year}${two(n.month)}${two(n.day)}-'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}.$ext';
  }

  Future<void> _pick(BuildContext context) async {
    final t = context.strings.appReports;
    final PickedImages picked;
    try {
      picked = await source.pickFiles(t.imagesPickDialogTitle, images);
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('קריאת תמונה לדיווח נכשלה', error, stack);
      UiSnack.showError(t.imageReadFailed);
      return;
    }
    if (!mounted) return;
    _apply(picked);
  }

  void _apply(PickedImages picked) {
    final t = context.strings.appReports;
    final onChanged = widget.onChanged;
    final otherAttachmentBytes = widget.otherAttachmentBytes;
    if (!enabled) return;
    final merged = mergeAppReportImages(images, picked.images,
        otherAttachmentBytes: otherAttachmentBytes);
    // הודעה אחת בכל פעם (`UiSnack` ללא תור): קובץ שלא נקרא קודם לשאר.
    if (picked.unreadable > 0) {
      UiSnack.showError(t.imageReadFailed);
    } else {
      switch (picked.limit ?? merged.rejection) {
        case AppReportImageRejection.totalTooLarge:
          UiSnack.showError(
            t.imagesTotalTooLarge(
                AppReportImage.maxTotalBytes ~/ AppReportImage.megabyte),
          );
        case AppReportImageRejection.tooMany:
          UiSnack.showError(t.tooManyImages(AppReportImage.maxCount));
        case AppReportImageRejection.tooLarge:
        case null:
          if (picked.tooLarge || merged.rejection != null) {
            UiSnack.showError(
              t.imageTooLarge(
                  AppReportImage.maxBytes ~/ AppReportImage.megabyte),
            );
          }
      }
    }
    if (merged.images.length != images.length) onChanged(merged.images);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = context.strings.appReports;
    final canPaste = widget.clipboard.isSupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('app-report-image-area'),
            onTap: enabled ? () => _pick(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD,
                vertical: 20,
              ),
              child: Column(
                children: [
                  Icon(
                    FluentIcons.image_add_24_regular,
                    color: enabled ? cs.primary : theme.disabledColor,
                  ),
                  const SizedBox(height: AppTokens.spaceSM),
                  Text(
                    canPaste ? t.imagesPromptWithPaste : t.imagesPrompt,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (canPaste) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ActionButton.neutral(
              key: const ValueKey('app-report-image-paste'),
              text: t.imagePasteButton,
              icon: FluentIcons.clipboard_paste_24_regular,
              size: ActionButtonSize.sm,
              onPressed: enabled ? _paste : null,
            ),
          ),
        ],
        const SizedBox(height: AppTokens.spaceSM),
        Text(t.attachmentLimitsHint, style: theme.textTheme.bodySmall),
        if (images.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (var i = 0; i < images.length; i++)
                _ImageThumbnail(
                  key: ValueKey('app-report-image-$i'),
                  image: images[i],
                  onRemove: enabled
                      ? () => widget.onChanged([...images]..removeAt(i))
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({super.key, required this.image, this.onRemove});

  static const double _size = 72;

  final AppReportImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Tooltip(
      message: image.fileName,
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: AppTokens.borderRadiusAll,
              // `cacheHeight`: בלעדיו התמונה מפוענחת ברזולוציית המקור (§5.9).
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                cacheHeight: (_size * ratio).round(),
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    FluentIcons.image_off_24_regular,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: SecondaryIconButton(
                  key: const ValueKey('app-report-image-remove'),
                  tooltip: context.strings.appReports.removeImageTooltip,
                  icon: FluentIcons.dismiss_16_regular,
                  onPressed: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
