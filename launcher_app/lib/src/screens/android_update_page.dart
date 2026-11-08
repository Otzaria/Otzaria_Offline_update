import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../controllers/android_module_controller.dart';
import '../services/byte_size.dart';
import '../services/file_reveal.dart';
import '../services/native_file_dialogs.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

class AndroidUpdatePage extends StatefulWidget {
  const AndroidUpdatePage({super.key, required this.controller});
  final AndroidModuleController controller;

  @override
  State<AndroidUpdatePage> createState() => _AndroidUpdatePageState();
}

class _AndroidUpdatePageState extends State<AndroidUpdatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.controller.checked) {
        unawaited(widget.controller.refresh());
      }
    });
  }

  Future<void> _chooseTools(bool copy) async {
    final controller = widget.controller;
    final t = context.strings.android;
    final path = await NativeFileDialogs.pickDirectory(
        dialogTitle: copy ? t.copyTools : t.selectTools);
    if (!mounted || path == null || controller.actionsBlocked) return;
    await controller.selectTools(path, copyToDrive: copy);
  }

  Future<void> _export() async {
    final controller = widget.controller;
    final path = await NativeFileDialogs.saveFile(
        dialogTitle: context.strings.android.export,
        fileName: 'otzaria-android.apk',
        allowedExtensions: ['apk']);
    if (!mounted || path == null || controller.actionsBlocked) return;
    await controller.exportApk(path);
  }

  Future<void> _openTools() async {
    if (await FileReveal.openAndroidToolsUrl() || !mounted) return;
    await Clipboard.setData(
        const ClipboardData(text: AndroidTools.downloadUrl));
    if (mounted) UiSnack.show(context.strings.common.pathCopiedSnack);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final t = context.strings.android;
          final common = context.strings.common;
          final info = c.deviceInfo;
          final release = c.release;
          return ScreenBody(
              title: t.title,
              description: t.description,
              children: [
                if (c.readOnly)
                  NoticeBanner(
                    leading: const IconTile(
                        icon: FluentIcons.lock_closed_24_regular),
                    title: t.readOnly,
                  ),
                if (c.error != null)
                  NoticeBanner(
                    leading: const IconTile(
                        icon: FluentIcons.error_circle_24_regular,
                        tone: IconTileTone.error),
                    title: common.error,
                    body: '${c.error}',
                    kind: NoticeKind.warning,
                    actions: [
                      ActionButton.neutral(
                          text: common.retry,
                          onPressed: c.canRetry ? c.retry : null)
                    ],
                  ),
                if (c.notice != null)
                  NoticeBanner(
                    leading: const IconTile(icon: FluentIcons.info_24_regular),
                    title: c.notice!,
                  ),
                if (c.isBusy) _progress(context),
                _card(t.apkTitle, [
                  Text(release == null
                      ? t.noMirror
                      : t.version(
                          release.info.versionName, release.info.versionCode)),
                  const SizedBox(height: 8),
                  Text(t.downloadHint),
                  const SizedBox(height: 12),
                  ActionButton.neutral(
                      key: const ValueKey('android-download'),
                      text: t.download,
                      onPressed:
                          c.actionsBlocked || c.readOnly ? null : c.download),
                ]),
                _card(t.devicesTitle, [
                  Text(t.connectionHint),
                  const SizedBox(height: 12),
                  ActionButton.neutral(
                      key: const ValueKey('android-refresh'),
                      text: t.refresh,
                      onPressed: c.actionsBlocked ? null : c.refresh),
                  const SizedBox(height: 12),
                  if (c.checked && c.devices.isEmpty) Text(t.noDevices),
                  for (final device in c.devices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        selected: c.selectedSerial == device.serial,
                        padding: const EdgeInsets.all(12),
                        onTap: c.actionsBlocked || !device.authorized
                            ? null
                            : () => c.selectDevice(device.serial),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.model,
                                  style: AppTextStyles.rowTitle,
                                  textDirection: TextDirection.ltr),
                              Text(device.serial,
                                  textDirection: TextDirection.ltr),
                              Text(device.authorized
                                  ? t.authorizedLabel
                                  : device.state == 'unauthorized'
                                      ? t.unauthorizedLabel
                                      : t.offlineLabel),
                            ]),
                      ),
                    ),
                  if (c.selectedSerial == null &&
                      c.devices.any((d) => d.authorized))
                    Text(t.selectDevice),
                  if (info != null) ...[
                    Text(info.versionCode == null
                        ? t.notInstalled
                        : t.version(info.versionName ?? common.unknownValue,
                            info.versionCode!)),
                    if (release != null &&
                        info.versionCode == release.info.versionCode)
                      Text(common.upToDate),
                    if (release != null &&
                        info.versionCode != null &&
                        info.versionCode! > release.info.versionCode)
                      Text(common.installedIsNewer),
                    if (c.incompatibility ==
                        AndroidUpdateFailure.incompatibleSdk)
                      Text(t.incompatibleSdk),
                    if (c.incompatibility ==
                        AndroidUpdateFailure.incompatibleAbi)
                      Text(t.incompatibleAbi),
                  ],
                  const SizedBox(height: 12),
                  ActionButton.recommended(
                      key: const ValueKey('android-install'),
                      text: t.install,
                      onPressed: c.canInstall ? c.install : null),
                ]),
                _card(t.toolsTitle, [
                  Text(t.toolsHint),
                  const SizedBox(height: 8),
                  TextLink(text: t.toolsDownload, onTap: _openTools),
                  const SizedBox(height: 12),
                  Text(c.toolsPath == null
                      ? t.adbMissing
                      : t.toolsPath(c.toolsPath!)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    ActionButton.neutral(
                        text: t.selectTools,
                        onPressed: c.actionsBlocked
                            ? null
                            : () => _chooseTools(false)),
                    ActionButton.neutral(
                        text: t.copyTools,
                        onPressed: c.actionsBlocked || c.readOnly
                            ? null
                            : () => _chooseTools(true)),
                  ]),
                ]),
                _card(t.exportTitle, [
                  Text(t.exportHint),
                  const SizedBox(height: 12),
                  ActionButton.neutral(
                      key: const ValueKey('android-export'),
                      text: t.export,
                      onPressed:
                          c.actionsBlocked || release == null ? null : _export),
                ]),
              ]);
        },
      );

  Widget _card(String title, List<Widget> children) => AppCard(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.rowTitle),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _progress(BuildContext context) => ListenableBuilder(
        listenable: widget.controller.progress,
        builder: (context, _) {
          final c = widget.controller;
          final t = context.strings.android;
          final message = c.stage ??
              switch (c.operation) {
                AndroidOperation.downloading => t.downloading,
                AndroidOperation.installing => t.installing,
                AndroidOperation.exporting => t.exporting,
                AndroidOperation.tools => t.preparingTools,
                _ => t.checking,
              };
          return _card(message, [
            AppProgressBar(
                value: c.total == null || c.total! <= 0
                    ? null
                    : (c.received ?? 0) / c.total!),
            if (c.total != null) ...[
              const SizedBox(height: 8),
              Text(
                  '${formatBytes(c.received ?? 0)} / ${formatBytes(c.total!)}'),
            ],
            const SizedBox(height: 12),
            ActionButton.ghost(
                text: context.strings.common.cancel,
                onPressed: c.cancelAndWait),
          ]);
        },
      );
}
