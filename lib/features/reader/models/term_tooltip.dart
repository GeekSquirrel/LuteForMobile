import 'package:flutter/foundation.dart';

@immutable
class TermTooltip {
  final String term;
  final String? translation;
  final int? termId;
  final String status;
  final String? statusText;
  final List<String> sentences;
  final String? language;
  final int? languageId;
  final String? imageUrl;
  final String? imageFilename;
  final List<TermParent> parents;
  final List<TermChild> children;

  const TermTooltip({
    required this.term,
    this.translation,
    this.termId,
    required this.status,
    this.statusText,
    this.sentences = const [],
    this.language,
    this.languageId,
    this.imageUrl,
    this.imageFilename,
    this.parents = const [],
    this.children = const [],
  });

  bool get hasData {
    return term.isNotEmpty;
  }

  String get statusLabel {
    switch (status) {
      case '99':
        return 'Well Known';
      case '0':
        return 'Unknown';
      case '1':
        return 'Learning 1';
      case '2':
        return 'Learning 2';
      case '3':
        return 'Learning 3';
      case '4':
        return 'Learning 4';
      case '5':
        return 'Learning 5';
      case '98':
        return 'Ignored';
      default:
        return statusText ?? 'Unknown';
    }
  }

  TermTooltip copyWith({
    String? term,
    String? translation,
    int? termId,
    String? status,
    String? statusText,
    List<String>? sentences,
    String? language,
    int? languageId,
    String? imageUrl,
    String? imageFilename,
    List<TermParent>? parents,
    List<TermChild>? children,
  }) {
    return TermTooltip(
      term: term ?? this.term,
      translation: translation ?? this.translation,
      termId: termId ?? this.termId,
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      sentences: sentences ?? this.sentences,
      language: language ?? this.language,
      languageId: languageId ?? this.languageId,
      imageUrl: imageUrl ?? this.imageUrl,
      imageFilename: imageFilename ?? this.imageFilename,
      parents: parents ?? this.parents,
      children: children ?? this.children,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TermTooltip &&
          runtimeType == other.runtimeType &&
          term == other.term &&
          translation == other.translation &&
          termId == other.termId &&
          status == other.status &&
          statusText == other.statusText &&
          listEquals(sentences, other.sentences) &&
          language == other.language &&
          languageId == other.languageId &&
          imageUrl == other.imageUrl &&
          imageFilename == other.imageFilename &&
          listEquals(parents, other.parents) &&
          listEquals(children, other.children);

  @override
  int get hashCode =>
      term.hashCode ^
      translation.hashCode ^
      termId.hashCode ^
      status.hashCode ^
      statusText.hashCode ^
      sentences.hashCode ^
      language.hashCode ^
      languageId.hashCode ^
      imageUrl.hashCode ^
      imageFilename.hashCode ^
      parents.hashCode ^
      children.hashCode;
}

@immutable
class TermParent {
  final int? id;
  final String term;
  final String? translation;
  final int? status;
  final bool? syncStatus;

  const TermParent({
    this.id,
    required this.term,
    this.translation,
    this.status,
    this.syncStatus,
  });

  TermParent copyWith({
    int? id,
    String? term,
    String? translation,
    int? status,
    bool? syncStatus,
  }) {
    return TermParent(
      id: id ?? this.id,
      term: term ?? this.term,
      translation: translation ?? this.translation,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TermParent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          term == other.term &&
          translation == other.translation &&
          status == other.status &&
          syncStatus == other.syncStatus;

  @override
  int get hashCode =>
      id.hashCode ^
      term.hashCode ^
      translation.hashCode ^
      status.hashCode ^
      syncStatus.hashCode;
}

@immutable
class TermChild {
  final String term;
  final String? translation;

  const TermChild({required this.term, this.translation});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TermChild &&
          runtimeType == other.runtimeType &&
          term == other.term &&
          translation == other.translation;

  @override
  int get hashCode => term.hashCode ^ translation.hashCode;
}
