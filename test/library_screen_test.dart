import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/ui/screens/library_screen.dart';
import 'package:my_wellness/ui/theme/app_theme.dart';
import 'package:my_wellness/ui/theme/tokens.dart';
import 'package:my_wellness/ui/widgets/controls/fields.dart';
import 'package:my_wellness/ui/widgets/controls/surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host() => ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, Accent.lime),
          home: const Scaffold(body: LibraryScreen()),
        ),
      );

  testWidgets('opens on the whole catalogue', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('1324 exercises with animations'), findsOneWidget);
    expect(find.text('Create your own exercise'), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.enterText(find.byType(SearchField), 'barbell bench press');
    await tester.pump();
    // Names are capitalised for display, though the dataset stores them lowercase.
    expect(find.textContaining('Bench Press'), findsWidgets);
  });

  testWidgets('a search with no results says so instead of showing an empty page',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.enterText(find.byType(SearchField), 'zzzzzznotanexercise');
    await tester.pump();
    expect(find.text('No match'), findsOneWidget);
  });

  testWidgets('the equipment filter offers only options with results behind it',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    // Cardio is the narrowest body part in the dataset, so its equipment row is short and
    // every chip on it must resolve to real exercises.
    await tester.tap(find.widgetWithText(AppChip, 'Cardio').first);
    await tester.pump();

    final chips = tester.widgetList<AppChip>(find.byType(AppChip));
    final labels = chips.map((c) => c.label).toList();
    expect(labels, contains('Any equipment'));
    // Nothing from another body part's kit leaks into the row.
    expect(labels, isNot(contains('Barbell')));
  });
}
