import 'dart:convert';
import 'package:flutter/foundation.dart';

final Map<String, Uint8List> _iconBytesCache = {};

/// Cached decoding of base64 app icons to preserve identical Uint8List references
/// across widget rebuilds and prevent image reloading/flicker in Flutter.
Uint8List getOrDecodeAppIconBytes(String base64Str) {
  return _iconBytesCache.putIfAbsent(
    base64Str,
    () => base64Decode(base64Str),
  );
}

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

  Uint8List? get iconBytes {
    if (iconBase64 == null || iconBase64!.isEmpty) return null;
    return getOrDecodeAppIconBytes(iconBase64!);
  }

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
class CustomAppWidgetConfig {
  final String id; // unique ID, e.g. "custom_1724213890123"
  final String name; // widget label
  final String template; // e.g. "翻译 [LUTE]"
  final String targetAppId; // packageName/activityName
  final String targetAppLabel;
  final String? targetAppIconBase64;
  final String actionType; // 'PROCESS_TEXT' or 'SEND'
  final int? colorValue; // optional accent color (ARGB)

  const CustomAppWidgetConfig({
    required this.id,
    required this.name,
    required this.template,
    required this.targetAppId,
    required this.targetAppLabel,
    this.targetAppIconBase64,
    this.actionType = 'PROCESS_TEXT',
    this.colorValue,
  });

  /// Replaces the placeholder [LUTE] with the given text.
  /// If the template does not contain [LUTE], appends the text after template.
  String resolveText(String rawText) {
    if (template.contains('[LUTE]')) {
      return template.replaceAll('[LUTE]', rawText);
    }
    if (template.trim().isEmpty) {
      return rawText;
    }
    return '$template $rawText';
  }

  factory CustomAppWidgetConfig.fromJson(Map<String, dynamic> json) {
    return CustomAppWidgetConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      template: json['template'] as String? ?? '[LUTE]',
      targetAppId: json['targetAppId'] as String? ?? '',
      targetAppLabel: json['targetAppLabel'] as String? ?? '',
      targetAppIconBase64: json['targetAppIconBase64'] as String?,
      actionType: json['actionType'] as String? ?? 'PROCESS_TEXT',
      colorValue: json['colorValue'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'template': template,
      'targetAppId': targetAppId,
      'targetAppLabel': targetAppLabel,
      if (targetAppIconBase64 != null) 'targetAppIconBase64': targetAppIconBase64,
      'actionType': actionType,
      if (colorValue != null) 'colorValue': colorValue,
    };
  }

  CustomAppWidgetConfig copyWith({
    String? id,
    String? name,
    String? template,
    String? targetAppId,
    String? targetAppLabel,
    String? targetAppIconBase64,
    String? actionType,
    int? colorValue,
  }) {
    return CustomAppWidgetConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      template: template ?? this.template,
      targetAppId: targetAppId ?? this.targetAppId,
      targetAppLabel: targetAppLabel ?? this.targetAppLabel,
      targetAppIconBase64: targetAppIconBase64 ?? this.targetAppIconBase64,
      actionType: actionType ?? this.actionType,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomAppWidgetConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          template == other.template &&
          targetAppId == other.targetAppId &&
          targetAppLabel == other.targetAppLabel &&
          actionType == other.actionType &&
          colorValue == other.colorValue;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      template.hashCode ^
      targetAppId.hashCode ^
      targetAppLabel.hashCode ^
      actionType.hashCode ^
      colorValue.hashCode;
}

@immutable
class LocalAppTabConfig {
  final bool enabled;
  final String? defaultTermAppId;
  final String? defaultSentenceAppId;
  final bool autoInvokeDefault;
  final List<String> termHiddenAppIds;
  final List<String> sentenceHiddenAppIds;
  final List<String> termAppOrder;
  final List<String> sentenceAppOrder;
  final String tabTitle;
  final List<CustomAppWidgetConfig> customWidgets;

  const LocalAppTabConfig({
    this.enabled = true,
    this.defaultTermAppId,
    this.defaultSentenceAppId,
    String? defaultAppId,
    this.autoInvokeDefault = true,
    this.termHiddenAppIds = const [],
    this.sentenceHiddenAppIds = const [],
    List<String>? hiddenAppIds,
    this.termAppOrder = const [],
    this.sentenceAppOrder = const [],
    List<String>? appOrder,
    this.tabTitle = 'Apps',
    this.customWidgets = const [],
  })  : _legacyDefaultAppId = defaultAppId,
        _legacyHiddenAppIds = hiddenAppIds,
        _legacyAppOrder = appOrder;

  final String? _legacyDefaultAppId;
  final List<String>? _legacyHiddenAppIds;
  final List<String>? _legacyAppOrder;

  /// Default app ID for terms (or fallback to legacy defaultAppId)
  String? get defaultAppId => defaultTermAppId ?? _legacyDefaultAppId;

  /// Legacy getter for hiddenAppIds
  List<String> get hiddenAppIds => getHiddenAppIds(isSentence: false);

  /// Legacy getter for appOrder
  List<String> get appOrder => getAppOrder(isSentence: false);

  /// Returns the default app ID for the given context (sentence or term).
  String? getDefaultAppId({bool isSentence = false}) {
    if (isSentence) {
      return defaultSentenceAppId;
    }
    return defaultTermAppId ?? _legacyDefaultAppId;
  }

  /// Returns the hidden app IDs for the given context (sentence or term).
  List<String> getHiddenAppIds({bool isSentence = false}) {
    if (isSentence) {
      if (sentenceHiddenAppIds.isNotEmpty) return sentenceHiddenAppIds;
      return _legacyHiddenAppIds ?? const [];
    }
    if (termHiddenAppIds.isNotEmpty) return termHiddenAppIds;
    return _legacyHiddenAppIds ?? const [];
  }

  /// Returns the app order for the given context (sentence or term).
  List<String> getAppOrder({bool isSentence = false}) {
    if (isSentence) {
      if (sentenceAppOrder.isNotEmpty) return sentenceAppOrder;
      return _legacyAppOrder ?? const [];
    }
    if (termAppOrder.isNotEmpty) return termAppOrder;
    return _legacyAppOrder ?? const [];
  }

  factory LocalAppTabConfig.fromJson(Map<String, dynamic> json) {
    final legacyDefault = json['defaultAppId'] as String?;
    final legacyHidden = (json['hiddenAppIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final legacyOrder = (json['appOrder'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final termHidden = (json['termHiddenAppIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        legacyHidden;
    final sentenceHidden = (json['sentenceHiddenAppIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        legacyHidden;

    final termOrder = (json['termAppOrder'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        legacyOrder;
    final sentenceOrder = (json['sentenceAppOrder'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        legacyOrder;

    return LocalAppTabConfig(
      enabled: json['enabled'] as bool? ?? true,
      defaultTermAppId: json['defaultTermAppId'] as String? ?? legacyDefault,
      defaultSentenceAppId: json['defaultSentenceAppId'] as String?,
      autoInvokeDefault: json['autoInvokeDefault'] as bool? ?? true,
      termHiddenAppIds: termHidden,
      sentenceHiddenAppIds: sentenceHidden,
      termAppOrder: termOrder,
      sentenceAppOrder: sentenceOrder,
      tabTitle: json['tabTitle'] as String? ?? 'Apps',
      customWidgets: (json['customWidgets'] as List<dynamic>?)
              ?.map((e) =>
                  CustomAppWidgetConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'defaultTermAppId': defaultTermAppId,
      'defaultSentenceAppId': defaultSentenceAppId,
      'defaultAppId': defaultAppId,
      'autoInvokeDefault': autoInvokeDefault,
      'termHiddenAppIds': getHiddenAppIds(isSentence: false),
      'sentenceHiddenAppIds': getHiddenAppIds(isSentence: true),
      'hiddenAppIds': getHiddenAppIds(isSentence: false),
      'termAppOrder': getAppOrder(isSentence: false),
      'sentenceAppOrder': getAppOrder(isSentence: true),
      'appOrder': getAppOrder(isSentence: false),
      'tabTitle': tabTitle,
      'customWidgets': customWidgets.map((e) => e.toJson()).toList(),
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
    List<String>? termHiddenAppIds,
    List<String>? sentenceHiddenAppIds,
    List<String>? hiddenAppIds,
    List<String>? termAppOrder,
    List<String>? sentenceAppOrder,
    List<String>? appOrder,
    String? tabTitle,
    List<CustomAppWidgetConfig>? customWidgets,
  }) {
    final effectiveClearTerm = clearDefaultTermAppId || clearDefaultAppId;
    final effectiveTerm = effectiveClearTerm
        ? null
        : (defaultTermAppId ??
            (defaultAppId ??
                (clearDefaultAppId
                    ? null
                    : this.defaultTermAppId ?? _legacyDefaultAppId)));

    final effectiveSentence = clearDefaultSentenceAppId
        ? null
        : (defaultSentenceAppId ?? this.defaultSentenceAppId);

    final effectiveTermHidden = termHiddenAppIds ??
        (hiddenAppIds ??
            (this.termHiddenAppIds.isNotEmpty
                ? this.termHiddenAppIds
                : (_legacyHiddenAppIds ?? const [])));
    final effectiveSentenceHidden = sentenceHiddenAppIds ??
        (hiddenAppIds ??
            (this.sentenceHiddenAppIds.isNotEmpty
                ? this.sentenceHiddenAppIds
                : (_legacyHiddenAppIds ?? const [])));
    final effectiveTermOrder = termAppOrder ??
        (appOrder ??
            (this.termAppOrder.isNotEmpty
                ? this.termAppOrder
                : (_legacyAppOrder ?? const [])));
    final effectiveSentenceOrder = sentenceAppOrder ??
        (appOrder ??
            (this.sentenceAppOrder.isNotEmpty
                ? this.sentenceAppOrder
                : (_legacyAppOrder ?? const [])));

    return LocalAppTabConfig(
      enabled: enabled ?? this.enabled,
      defaultTermAppId: effectiveTerm,
      defaultSentenceAppId: effectiveSentence,
      autoInvokeDefault: autoInvokeDefault ?? this.autoInvokeDefault,
      termHiddenAppIds: effectiveTermHidden,
      sentenceHiddenAppIds: effectiveSentenceHidden,
      termAppOrder: effectiveTermOrder,
      sentenceAppOrder: effectiveSentenceOrder,
      tabTitle: tabTitle ?? this.tabTitle,
      customWidgets: customWidgets ?? this.customWidgets,
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
          listEquals(getHiddenAppIds(isSentence: false),
              other.getHiddenAppIds(isSentence: false)) &&
          listEquals(getHiddenAppIds(isSentence: true),
              other.getHiddenAppIds(isSentence: true)) &&
          listEquals(getAppOrder(isSentence: false),
              other.getAppOrder(isSentence: false)) &&
          listEquals(getAppOrder(isSentence: true),
              other.getAppOrder(isSentence: true)) &&
          tabTitle == other.tabTitle &&
          listEquals(customWidgets, other.customWidgets);

  @override
  int get hashCode =>
      enabled.hashCode ^
      defaultTermAppId.hashCode ^
      defaultSentenceAppId.hashCode ^
      defaultAppId.hashCode ^
      autoInvokeDefault.hashCode ^
      getHiddenAppIds(isSentence: false).hashCode ^
      getHiddenAppIds(isSentence: true).hashCode ^
      getAppOrder(isSentence: false).hashCode ^
      getAppOrder(isSentence: true).hashCode ^
      tabTitle.hashCode ^
      customWidgets.hashCode;
}
