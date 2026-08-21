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
  final String? defaultTermAppId;
  final String? defaultSentenceAppId;
  final bool autoInvokeDefault;
  final List<String> hiddenAppIds;
  final List<String> appOrder;
  final String tabTitle;

  const LocalAppTabConfig({
    this.enabled = true,
    this.defaultTermAppId,
    this.defaultSentenceAppId,
    String? defaultAppId,
    this.autoInvokeDefault = true,
    this.hiddenAppIds = const [],
    this.appOrder = const [],
    this.tabTitle = 'Apps',
  }) : _legacyDefaultAppId = defaultAppId;

  final String? _legacyDefaultAppId;

  /// Default app ID for terms (or fallback to legacy defaultAppId)
  String? get defaultAppId => defaultTermAppId ?? _legacyDefaultAppId;

  /// Returns the default app ID for the given context (sentence or term).
  String? getDefaultAppId({bool isSentence = false}) {
    if (isSentence) {
      return defaultSentenceAppId;
    }
    return defaultTermAppId ?? _legacyDefaultAppId;
  }

  factory LocalAppTabConfig.fromJson(Map<String, dynamic> json) {
    final legacyDefault = json['defaultAppId'] as String?;
    return LocalAppTabConfig(
      enabled: json['enabled'] as bool? ?? true,
      defaultTermAppId: json['defaultTermAppId'] as String? ?? legacyDefault,
      defaultSentenceAppId: json['defaultSentenceAppId'] as String?,
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
      'defaultTermAppId': defaultTermAppId,
      'defaultSentenceAppId': defaultSentenceAppId,
      'defaultAppId': defaultAppId,
      'autoInvokeDefault': autoInvokeDefault,
      'hiddenAppIds': hiddenAppIds,
      'appOrder': appOrder,
      'tabTitle': tabTitle,
    };
  }

  LocalAppTabConfig copyWith({
    bool? enabled,
    String? defaultTermAppId,
    bool clearDefaultTermAppId = false,
    String? defaultSentenceAppId,
    bool clearDefaultSentenceAppId = false,
    String? defaultAppId,
    bool clearDefaultAppId = false,
    bool? autoInvokeDefault,
    List<String>? hiddenAppIds,
    List<String>? appOrder,
    String? tabTitle,
  }) {
    final effectiveClearTerm = clearDefaultTermAppId || clearDefaultAppId;
    final effectiveTerm = effectiveClearTerm
        ? null
        : (defaultTermAppId ??
            (defaultAppId ?? (clearDefaultAppId ? null : this.defaultTermAppId ?? _legacyDefaultAppId)));

    final effectiveSentence = clearDefaultSentenceAppId
        ? null
        : (defaultSentenceAppId ?? this.defaultSentenceAppId);

    return LocalAppTabConfig(
      enabled: enabled ?? this.enabled,
      defaultTermAppId: effectiveTerm,
      defaultSentenceAppId: effectiveSentence,
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
          defaultTermAppId == other.defaultTermAppId &&
          defaultSentenceAppId == other.defaultSentenceAppId &&
          defaultAppId == other.defaultAppId &&
          autoInvokeDefault == other.autoInvokeDefault &&
          listEquals(hiddenAppIds, other.hiddenAppIds) &&
          listEquals(appOrder, other.appOrder) &&
          tabTitle == other.tabTitle;

  @override
  int get hashCode =>
      enabled.hashCode ^
      defaultTermAppId.hashCode ^
      defaultSentenceAppId.hashCode ^
      defaultAppId.hashCode ^
      autoInvokeDefault.hashCode ^
      hiddenAppIds.hashCode ^
      appOrder.hashCode ^
      tabTitle.hashCode;
}
