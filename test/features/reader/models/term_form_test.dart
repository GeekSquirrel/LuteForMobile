import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lute_for_mobile/features/reader/models/term_form.dart';
import 'package:lute_for_mobile/features/reader/models/term_tooltip.dart';

void main() {
  group('TermParent', () {
    test('copyWith and equality work properly', () {
      const parent1 = TermParent(
        id: 10,
        term: 'cat',
        translation: '猫',
        status: 1,
        syncStatus: true,
      );

      const parent2 = TermParent(
        id: 10,
        term: 'cat',
        translation: '猫',
        status: 1,
        syncStatus: true,
      );

      expect(parent1, equals(parent2));
      expect(parent1.hashCode, equals(parent2.hashCode));

      final updated = parent1.copyWith(translation: '猫咪');
      expect(updated.translation, equals('猫咪'));
      expect(updated.id, equals(10));
      expect(updated == parent1, isFalse);
    });
  });

  group('TermForm', () {
    test('toFormData includes parents and sync_status correctly', () {
      const parent = TermParent(
        id: 10,
        term: 'cat',
        translation: '猫',
        status: 1,
        syncStatus: true,
      );

      final termForm = TermForm(
        term: 'cats',
        translation: '猫（复数）',
        languageId: 1,
        status: '1',
        parents: [parent],
        syncStatus: true,
      );

      final formData = termForm.toFormData();
      expect(formData['text'], equals('cats'));
      expect(formData['translation'], equals('猫（复数）'));
      expect(formData['sync_status'], equals('y'));

      final parentsListJson = formData['parentslist'] as String?;
      expect(parentsListJson, isNotNull);
      final decodedParents = jsonDecode(parentsListJson!) as List<dynamic>;
      expect(decodedParents.length, equals(1));
      expect(decodedParents.first['value'], equals('cat'));
    });

    test('copyWith correctly updates parent list and translation', () {
      const parent = TermParent(
        id: 10,
        term: 'cat',
        translation: null,
      );

      final termForm = TermForm(
        term: 'cats',
        languageId: 1,
        parents: [parent],
        syncStatus: false,
      );

      final updatedParent = parent.copyWith(translation: '猫');
      final updatedParents = termForm.parents.map((p) {
        if (p.term == updatedParent.term) return updatedParent;
        return p;
      }).toList();

      final updatedForm = termForm.copyWith(parents: updatedParents);

      expect(updatedForm.parents.first.translation, equals('猫'));
      expect(updatedForm == termForm, isFalse);
    });
  });
}
