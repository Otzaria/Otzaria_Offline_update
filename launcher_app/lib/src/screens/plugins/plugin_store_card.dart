import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../store_kit/store_kit.dart';
import 'plugin_visuals.dart';

/// כרטיס תוסף ברשת החנות — כמו `PluginCard` שבאתר: סמל, שם, מטא, שתי שורות
/// תיאור ופעולה אחת לפי המצב. תגיות ותאריך — רק בדף הפרטים.
class PluginStoreCard extends StatelessWidget {
  const PluginStoreCard({
    super.key,
    required this.plugin,
    required this.controller,
    required this.state,
    required this.onOpenDetail,
    required this.onSave,
    required this.onInstall,
    this.isNew = false,
    this.blocked = false,
    this.online,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final PluginCardState state;
  final VoidCallback onOpenDetail;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final bool isNew;

  /// "עדכון הכול" רץ — כפתורי הכרטיסים מושבתים בינתיים.
  final bool blocked;

  /// `true` — יש אינטרנט, וקובץ חסר יירד מיד בהתקנה.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    return StoreItemCard(
      icon: StoreIcon(imagePath: controller.assetPath(plugin.imagePath)),
      title: plugin.name,
      meta: PluginMeta(controller: controller, plugin: plugin, isNew: isNew),
      description: plugin.shortDescription,
      onTap: onOpenDetail,
      action: PluginAction(
        controller: controller,
        plugin: plugin,
        state: state,
        onInstall: onInstall,
        onSave: onSave,
        blocked: blocked,
      ),
      note: pluginNoteOf(context, controller, plugin, state, online: online),
    );
  }
}
