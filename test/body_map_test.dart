import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/domain/muscles.dart';
import 'package:my_open_gym/ui/theme/app_theme.dart';
import 'package:my_open_gym/ui/theme/tokens.dart';
import 'package:my_open_gym/ui/widgets/body_map.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  Widget host(Widget child, {Brightness b = Brightness.dark}) => MaterialApp(
        theme: buildTheme(b, Accent.lime),
        home: Scaffold(body: child),
      );

  testWidgets('the geometry parses and paints for both figures, in both themes',
      (tester) async {
    for (final body in ['male', 'female']) {
      for (final b in Brightness.values) {
        await tester.pumpWidget(host(
          BodyMap(body: body, load: const {'chest': 12, 'biceps': 4, 'quadriceps': 8}),
          b: b,
        ));
        // The path data is loaded from an asset, so the first frame is the placeholder.
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$body/${b.name}');
        expect(find.byType(CustomPaint), findsWidgets);
      }
    }
  });

  testWidgets('an empty load still draws the body rather than nothing', (tester) async {
    await tester.pumpWidget(host(const BodyMap(load: {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('shading is relative to the hardest-worked muscle in the same window', () {
    // The map answers "is my training balanced", so the top muscle is always level 4 whether
    // the week held 4 sets or 40.
    final light = levelsOf({'chest': 4, 'biceps': 1});
    final heavy = levelsOf({'chest': 40, 'biceps': 10});
    expect(light['chest'], 4);
    expect(heavy['chest'], 4);
    expect(light['biceps'], heavy['biceps']);
    // Anything untrained is level 0, and everything trained is at least 1.
    expect(light['calves'], 0);
    expect(levelsOf({'chest': 0.1, 'biceps': 100})['chest'], 1);
  });
}
