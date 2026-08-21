import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lute_for_mobile/features/reader/widgets/reader_drawer_settings.dart';
import 'package:lute_for_mobile/features/books/widgets/books_drawer_settings.dart';
import 'package:lute_for_mobile/shared/theme/app_theme.dart';
import 'package:lute_for_mobile/features/settings/models/settings.dart';

import 'package:lute_for_mobile/shared/providers/language_data_provider.dart';

void main() {
  Widget createTestWidget(
    Widget child, {
    dynamic overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides is List ? overrides.cast() : const [],
      child: MaterialApp(
        theme: AppTheme.darkTheme(ThemeSettings()),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 600,
            child: child,
          ),
        ),
      ),
    );
  }

  group('ReaderDrawerSettings', () {
    testWidgets('renders and expands Text Formatting in reader route without overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(
          const ReaderDrawerSettings(currentRoute: 'reader'),
        ),
      );

      // Verify ExpansionTile is present
      expect(find.text('Text Formatting'), findsOneWidget);

      // Tap to expand Text Formatting
      await tester.tap(find.text('Text Formatting'));
      await tester.pumpAndSettle();

      // Verify expanded elements are present
      expect(find.textContaining('Text Size:'), findsOneWidget);
      expect(find.textContaining('Line Spacing:'), findsOneWidget);
      expect(find.text('Font'), findsOneWidget);
      expect(find.textContaining('Weight:'), findsOneWidget);
      expect(find.text('Italic'), findsOneWidget);

      // Verify toggle rows are present
      expect(find.text('Fullscreen Mode'), findsOneWidget);
      expect(find.text('Word Glow'), findsOneWidget);
      expect(find.text('Show Tooltip Images'), findsOneWidget);
      expect(find.text('Show Page Numbers'), findsOneWidget);

      // Verify no Flutter error / overflow occurred during pumpAndSettle
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders and expands Text Formatting in sentence-reader route without overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(
          const ReaderDrawerSettings(currentRoute: 'sentence-reader'),
        ),
      );

      // Verify ExpansionTile is present
      expect(find.text('Text Formatting'), findsOneWidget);

      // Tap to expand Text Formatting
      await tester.tap(find.text('Text Formatting'));
      await tester.pumpAndSettle();

      // Verify expanded elements are present
      expect(find.textContaining('Text Size:'), findsOneWidget);
      expect(find.textContaining('Line Spacing:'), findsOneWidget);
      expect(find.text('Font'), findsOneWidget);
      expect(find.textContaining('Weight:'), findsOneWidget);
      expect(find.text('Italic'), findsOneWidget);

      // Verify sentence reader specific buttons
      expect(find.text('Flush Cache & Rebuild'), findsOneWidget);
      expect(find.text('Show Known Terms'), findsOneWidget);

      // Verify no Flutter error / overflow occurred during pumpAndSettle
      expect(tester.takeException(), isNull);
    });
  });
}
