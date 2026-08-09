import 'package:equatable/equatable.dart';

/// הטקסטים האצורים של דף הבית של החנות (`/api/plugins/store-home`).
/// מנהלי האתר עורכים אותם שם, והמראה נושאת אותם אל המחשב הלא-מקוון.
class PluginStoreHome extends Equatable {
  const PluginStoreHome({this.title = '', this.subtitle = ''});

  static const PluginStoreHome empty = PluginStoreHome();

  final String title;
  final String subtitle;

  bool get isEmpty => title.isEmpty && subtitle.isEmpty;

  factory PluginStoreHome.fromApi(Map<String, dynamic> json) => PluginStoreHome(
        title: json['homeTitle'] is String ? json['homeTitle'] as String : '',
        subtitle: json['homeSubtitle'] is String
            ? json['homeSubtitle'] as String
            : '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'subtitle': subtitle};

  static PluginStoreHome fromJson(Object? json) {
    if (json is! Map) return empty;
    return PluginStoreHome(
      title: json['title'] is String ? json['title'] as String : '',
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
    );
  }

  @override
  List<Object?> get props => [title, subtitle];
}
