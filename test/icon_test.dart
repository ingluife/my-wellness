import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/ui/widgets/app_icon.dart';

void main() {
  test('every icon key parses into paintable geometry', () {
    for (final name in iconNames) {
      expect(() => AppIcon(name), returnsNormally, reason: name);
    }
    // Counted as two halves on purpose. icon_paths.dart is regenerated from openGym by
    // tool/gen_icons.mjs and icon_paths_food.dart is hand-drawn here; a regeneration that
    // clobbered the food glyphs would leave a single total looking merely different, not wrong.
    expect(foodIconNames.length, 9, reason: 'hand-drawn food glyphs');
    expect(iconNames.length - foodIconNames.length, 83, reason: 'generated openGym set');
    for (final n in foodIconNames) {
      expect(iconNames, contains(n));
    }
  });

  testWidgets('every icon paints without throwing', (tester) async {
    // Painting is where a malformed path command actually surfaces — parseSvgPathData is
    // lenient about some input that then fails on the canvas.
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Wrap(
            children: [for (final n in iconNames) AppIcon(n, size: 24, color: Colors.black)],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppIcon), findsNWidgets(iconNames.length));
  });

  testWidgets('every icon actually draws something at the size it was asked for',
      (tester) async {
    // The test above passes even for an icon that draws nothing: an unknown name renders
    // `SizedBox.shrink()`, which is still an AppIcon in the tree and still throws no exception.
    // That is precisely how the food glyphs came to be invisible everywhere — the name guard
    // checked only the generated half of the merged icon map, so all nine drew empty boxes and
    // no test noticed. Asserting the laid-out size is what makes a silent glyph fail loudly.
    for (final n in iconNames) {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: AppIcon(n, size: 24, color: Colors.black)),
        ),
      ));
      expect(tester.getSize(find.byType(AppIcon)), const Size(24, 24), reason: n);
      expect(find.descendant(of: find.byType(AppIcon), matching: find.byType(CustomPaint)),
          findsOneWidget,
          reason: n);
    }
  });
}
