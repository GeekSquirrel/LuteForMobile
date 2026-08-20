import 'package:flutter/foundation.dart';

@immutable
class AndroidAppInfo {
  final String packageName;
  final String activityName;
  final String label;
  final String? iconBase64;
  final String actionType; // 'PROCESS_TEXT' or 'SEND'

  const AndroidAppInfo({
    required this.packageName,
    required this.activityName,
    required this.label,
    this.iconBase64,
    this.actionType = 'PROCESS_TEXT',
  });

  String get id => '$packageName/$activityName';

  factory AndroidAppInfo.fromJson(Map<String, dynamic> json) {
    return AndroidAppInfo(
      packageName: json['packageName'] as String? ?? '',
      activityName: json['activityName'] as String? ?? '',
      label: json['label'] as String? ?? '',
      iconBase64: json['iconBase64'] as String?,
      actionType: json['actionType'] as String? ?? 'PROCESS_TEXT',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'activityName': activityName,
      'label': label,
      if (iconBase64 != null) 'iconBase64': iconBase64,
      'actionType': actionType,
    };
  }

  AndroidAppInfo copyWith({
    String? packageName,
    String? activityName,
    String? label,
    String? iconBase64,
    String? actionType,
  }) {
    return AndroidAppInfo(
      packageName: packageName ?? this.packageName,
      activityName: activityName ?? this.activityName,
      label: label ?? this.label,
      iconBase64: iconBase64 ?? this.iconBase64,
      actionType: actionType ?? this.actionType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndroidAppInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          activityName == other.activityName &&
          label == other.label &&
          actionType == other.actionType;

  @override
  int get hashCode =>
      packageName.hashCode ^
      activityName.hashCode ^
      label.hashCode ^
      actionType.hashCode;
}

@immutable
class LocalAppTabConfig {
  final bool enabled;
  final String? defaultAppId;
  final bool autoInvokeDefault;
  final List<String> hiddenAppIds;
  final List<String> appOrder;
  final String tabTitle;

  const LocalAppTabConfig({
    this.enabled = true,
    this.defaultAppId,
    this.autoInvokeDefault = true,
    this.hiddenAppIds = const [],
    this.appOrder = const [],
    this.tabTitle = 'Apps',
  });

  factory LocalAppTabConfig.fromJson(Map<String, dynamic> json) {
    return LocalAppTabConfig(
      enabled: json['enabled'] as bool? ?? true,
      defaultAppId: json['defaultAppId'] as String?,
      autoInvokeDefault: json['autoInvokeDefault'] as bool? ?? true,
      hiddenAppIds:
          (json['hiddenAppIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      appOrder:
          (json['appOrder'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      tabTitle: json['tabTitle'] as String? ?? 'Apps',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'defaultAppId': defaultAppId,
      'autoInvokeDefault': autoInvokeDefault,
      'hiddenAppIds': hiddenAppIds,
      'appOrder': appOrder,
      'tabTitle': tabTitle,
    };
  }

  LocalAppTabConfig copyWith({
    bool? enabled,
    String? defaultAppId,
    bool clearDefaultAppId = false,
    bool? autoInvokeDefault,
    List<String>? hiddenAppIds,
    List<String>? appOrder,
    String? tabTitle,
  }) {
    return LocalAppTabConfig(
      enabled: enabled ?? this.enabled,
      defaultAppId: clearDefaultAppId
          ? null
          : (defaultAppId ?? this.defaultAppId),
      autoInvokeDefault: autoInvokeDefault ?? this.autoInvokeDefault,
      hiddenAppIds: hiddenAppIds ?? this.hiddenAppIds,
      appOrder: appOrder ?? this.appOrder,
      tabTitle: tabTitle ?? this.tabTitle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalAppTabConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          defaultAppId == other.defaultAppId &&
          autoInvokeDefault == other.autoInvokeDefault &&
          listEquals(hiddenAppIds, other.hiddenAppIds) &&
          listEquals(appOrder, other.appOrder) &&
          tabTitle == other.tabTitle;

  @override
  int get hashCode =>
      enabled.hashCode ^
      defaultAppId.hashCode ^
      autoInvokeDefault.hashCode ^
      hiddenAppIds.hashCode ^
      appOrder.hashCode ^
      tabTitle.hashCode;
}
