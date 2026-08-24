import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/ui/theme/app_theme.dart';
import 'package:my_open_gym/ui/theme/tokens.dart';
import 'package:my_open_gym/ui/widgets/app_icon.dart';
import 'package:my_open_gym/ui/widgets/controls/app_button.dart';
import 'package:my_open_gym/ui/widgets/controls/fields.dart';
import 'package:my_open_gym/ui/widgets/controls/slider.dart';
import 'package:my_open_gym/ui/widgets/controls/stepper.dart';
import 'package:my_open_gym/ui/widgets/controls/surfaces.dart';
import 'package:my_open_gym/ui/widgets/controls/toggles.dart';

/// Every control, in both themes and all eight accents, must build and paint. This is the
/// headless equivalent of the design gallery the plan called for.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.dark, Accent accent = Accent.lime}) =>
      MaterialApp(
        theme: buildTheme(brightness, accent),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('the control set builds in every theme and accent', (tester) async {
    for (final b in Brightness.values) {
      for (final a in Accent.values) {
        await tester.pumpWidget(host(
          Column(
            children: [
              for (final v in BtnVariant.values)
                for (final s in BtnSize.values)
                  AppButton('${v.name} ${s.name}',
                      variant: v, size: s, icon: 'plus', trailingIcon: 'chevronRight', onTap: () {}),
              const AppButton('disabled', onTap: null),
              AppSwitch(value: true, onChanged: (_) {}),
              AppSwitch(value: false, onChanged: (_) {}),
              AppCheck(value: true, onChanged: (_) {}),
              AppCheck(value: false, onChanged: (_) {}),
              Segmented<int>(
                options: const [SegOption(0, label: 'Week'), SegOption(1, label: '30d')],
                value: 0,
                onChanged: (_) {},
              ),
              AppStepper(value: 62.5, step: 2.5, label: 'Weight (kg)', onChanged: (_) {}),
              AppSlider(value: 70, min: 1, max: 300, step: .5, onChanged: (_) {}),
              const SearchField(value: '', onChanged: _noop),
              const AppTextField(placeholder: 'Your name'),
              const Section(title: 'General', footer: 'a footer', children: [
                AppRow(icon: 'globe', title: 'Language', value: 'English', accessory: RowAccessory.chevron),
                AppRow(icon: 'scale', title: 'Weight unit'),
                AppRow(title: 'No icon row', subtitle: 'with a subtitle'),
              ]),
              const AppCard(child: Text('a card')),
              ListItem(child: const ItemText('Push Day', subtitle: '6 exercises'), onTap: () {}),
              const Row(children: [
                Tag('barbell'),
                Tag('Start', accent: true),
              ]),
              AppChip('chest', selected: true, onTap: () {}),
              const EmptyState(icon: 'clipboard', message: 'No routines yet.'),
              IconButtonRound('gear', onTap: () {}),
            ],
          ),
          brightness: b,
          accent: a,
        ));
        expect(tester.takeException(), isNull, reason: '${b.name}/${a.name}');
      }
    }
  });

  testWidgets('NumberField accepts a comma as the decimal separator', (tester) async {
    double? got;
    await tester.pumpWidget(host(NumberField(value: 0, onChanged: (v) => got = v)));
    await tester.enterText(find.byType(EditableText), '33,5');
    expect(got, 33.5);
  });

  testWidgets('NumberField clears to null only when it is nullable', (tester) async {
    double? got = 1;
    await tester.pumpWidget(host(NumberField(value: 2, nullable: true, onChanged: (v) => got = v)));
    await tester.enterText(find.byType(EditableText), '');
    // An unrated effort is not "went to failure" — it has to come back as null, not 0.
    expect(got, isNull);

    // A distinct key, so this is a fresh field rather than the same State re-parented — the
    // draft it is holding would otherwise make the empty entry a no-op.
    await tester.pumpWidget(
        host(NumberField(key: const Key('plain'), value: 2, onChanged: (v) => got = v)));
    await tester.enterText(find.byType(EditableText), '');
    expect(got, 0);
  });

  testWidgets('a non-decimal NumberField refuses a fractional part', (tester) async {
    double? got;
    await tester.pumpWidget(host(NumberField(value: 8, decimal: false, onChanged: (v) => got = v)));
    await tester.enterText(find.byType(EditableText), '12.5');
    expect(got, 12);
  });

  testWidgets('the stepper walks by its step and never goes below zero', (tester) async {
    var value = 2.5;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) => AppStepper(
        value: value,
        step: 2.5,
        onChanged: (v) => setState(() => value = v ?? 0),
      ),
    )));

    final minus = find.byType(AppIcon).at(0);
    final plus = find.byType(AppIcon).at(1);

    await tester.tap(plus);
    await tester.pump();
    expect(value, 5);

    await tester.tap(minus);
    await tester.pump();
    await tester.tap(minus);
    await tester.pump();
    expect(value, 0);

    // A step below zero clamps rather than going negative — no set was ever performed at −2.5.
    await tester.tap(minus);
    await tester.pump();
    expect(value, 0);
  });
}

void _noop(String _) {}
