import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/ui/widgets/app_icon.dart';

void main() {
  test('every icon key parses into paintable geometry', () {
    for (final name in iconNames) {
      expect(() => AppIcon(name), returnsNormally, reason: name);
    }
    expect(iconNames.length, 83);
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
}
