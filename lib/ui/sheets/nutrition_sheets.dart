import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/coaching.dart';
import '../../domain/dishes.dart';
import '../../domain/foods.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../../ui/app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/page.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/stepper.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
// A cycle: the photo sheet's "Log it by hand" and "Add something it missed" reach back into this
// file. That is what the two sheets genuinely are to each other — either can be the way out of
// the other — and Dart resolves it without complaint.
import 'meal_photo_sheet.dart';
import 'sheet_service.dart';

/// Age, height, sex and activity — the numbers a calorie estimate cannot be made without.
///
/// This is the app's first ever profile form. Everything before it was derivable from what you
/// logged; a resting metabolic rate is not, and the honest options were to ask or to guess.
Future<void> bodyProfileSheet() =>
    showSheet<void>((context, close) => _BodyProfileSheet(close: close));

class _BodyProfileSheet extends ConsumerStatefulWidget {
  const _BodyProfileSheet({required this.close});

  final void Function([void]) close;

  @override
  ConsumerState<_BodyProfileSheet> createState() => _BodyProfileSheetState();
}

/// The range each body metric is accepted in.
///
/// Wide enough not to argue with real people, narrow enough to catch the mistakes that
/// actually happen — a height typed in metres, an age typed as a birth year. Mifflin-St Jeor
/// was fitted on adults, so an age below 13 is outside what the equation can honestly answer
/// rather than merely unusual.
const _ageRange = (min: 13.0, max: 100.0);
const _heightRange = (min: 120.0, max: 230.0);

class _BodyProfileSheetState extends ConsumerState<_BodyProfileSheet> {
  double? _age;
  double? _height;
  String? _sex;
  String? _activity;
  bool _seeded = false;

  /// Errors are held back until the field has been left or Save has been pressed, so a
  /// half-typed "1" on the way to "178" is not shouted at.
  bool _showErrors = false;

  String? get _ageError {
    final v = _age;
    if (v == null) return t('How old are you?');
    // The ceiling is enforced by the field, so only the floor can be reached from here.
    if (v < _ageRange.min) {
      return t('Between {0} and {1}', _ageRange.min.round(), _ageRange.max.round());
    }
    return null;
  }

  String? get _heightError {
    final v = _height;
    if (v == null) return t('How tall are you?');
    if (v < _heightRange.min) {
      // The mistake this catches most often is metres: 1.78 rather than 178.
      return v < 3
          ? t('In centimetres — 178, not 1.78')
          : t('Between {0} and {1} cm', _heightRange.min.round(), _heightRange.max.round());
    }
    return null;
  }

  bool get _valid => _ageError == null && _heightError == null;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final p = s.nutrition.profile;
    if (!_seeded) {
      _seeded = true;
      _age = p.age;
      _height = p.height;
      // The muscle map's figure is a reasonable opening guess and a terrible silent default,
      // so it seeds the control and the user still has to look at it.
      _sex = p.sex ?? s.body;
      _activity = p.activity ?? 'light';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('About you')),
        Text(
          t('Used only to estimate what you burn at rest. It stays on this phone like everything else.'),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 14),
        Section(children: [
          AppRow(
            title: t('Age'),
            subtitle: _showErrors && _ageError != null ? null : t('Years'),
            trailing: SizedBox(
              width: 92,
              child: NumberBox(
                value: _age,
                decimal: false,
                nullable: true,
                placeholder: '34',
                max: _ageRange.max,
                invalid: _showErrors && _ageError != null,
                onChanged: (v) => setState(() => _age = v),
              ),
            ),
          ),
          if (_showErrors && _ageError != null) _error(context, _ageError!),
          AppRow(
            title: t('Height'),
            subtitle: _showErrors && _heightError != null ? null : t('Centimetres'),
            trailing: SizedBox(
              width: 110,
              child: NumberBox(
                value: _height,
                decimal: false,
                nullable: true,
                placeholder: '178',
                suffix: t('cm'),
                max: _heightRange.max,
                invalid: _showErrors && _heightError != null,
                onChanged: (v) => setState(() => _height = v),
              ),
            ),
          ),
          if (_showErrors && _heightError != null) _error(context, _heightError!),
          AppRow(
            title: t('Sex'),
            subtitle: t('Changes the resting-rate formula only'),
            // Segmented divides its width with Expanded, and AppRow lays its trailing slot
            // out in an unbounded Row — so it has to be given one. 150 is what every other
            // in-row segmented control in the app uses.
            trailing: SizedBox(
              width: 150,
              child: Segmented<String>(
                inline: true,
                value: _sex ?? 'male',
                options: [
                  SegOption('male', label: t('Male')),
                  SegOption('female', label: t('Female')),
                ],
                onChanged: (v) => setState(() => _sex = v),
              ),
            ),
          ),
        ]),
        Section(
          title: t('Daily activity'),
          footer: t('Not counting training — your workouts are added from what you actually log, so choosing a higher level here would count them twice.'),
          children: [
            SelectRow<String>(
              title: t('Activity'),
              value: _activity ?? 'light',
              sheetTitle: t('Daily activity'),
              options: [
                SelectOption('sedentary', t('Sedentary'), subtitle: t('Desk work, little walking')),
                SelectOption('light', t('Lightly active'), subtitle: t('Some walking most days')),
                SelectOption('moderate', t('Moderately active'), subtitle: t('On your feet regularly')),
                SelectOption('active', t('Very active'), subtitle: t('On your feet most of the day')),
              ],
              onChanged: (v) => setState(() => _activity = v),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppButton(t('Save'), variant: BtnVariant.primary, onTap: () {
          if (!_valid) {
            // Both problems at once, marked where they are. A toast names one, disappears,
            // and leaves you guessing which box it meant.
            setState(() => _showErrors = true);
            return;
          }
          ref.read(appStateProvider.notifier).update((st) {
            st.nutrition.profile
              ..age = _age
              ..height = _height
              ..sex = _sex ?? 'male'
              ..activity = _activity ?? 'light';
          });
          widget.close();
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A validation message, sitting directly under the row it belongs to.
Widget _error(BuildContext context, String message) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      child: Row(children: [
        AppIcon('info', size: 12, color: context.c.sys.red),
        const SizedBox(width: 5),
        Expanded(
          child: Text(message, style: ts(TypeScale.cap, color: context.c.sys.red)),
        ),
      ]),
    );

/// Cut, maintain or gain, and how fast.
Future<void> nutritionGoalSheet() =>
    showSheet<void>((context, close) => _GoalSheet(close: close));

/// "Lose 0.5 kg a week", or the mode alone when it has no rate.
///
/// Lives beside the sheet that edits it rather than in the screen that shows it: two screens now
/// summarise the same goal, and a line that reads differently in each is a line that makes you
/// check which one is right.
String goalLine(AppState s) {
  final g = s.nutrition.goal;
  final mode = goalMode(g);
  if (mode == 'maintain') return t('Maintain');
  final rate = goalRate(g).abs();
  return mode == 'cut'
      ? t('Lose {0} kg a week', fmtNum(rate))
      : t('Gain {0} kg a week', fmtNum(rate));
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.close});

  final void Function([void]) close;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  String? _mode;
  double? _rate;
  double? _meals;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final g = s.nutrition.goal;
    if (!_seeded) {
      _seeded = true;
      _mode = goalMode(g);
      _rate = goalRate(g).abs();
      _meals = mealsPerDay(g).toDouble();
    }
    final mode = _mode ?? 'maintain';

    // Recomputed live against the pending choice, so the effect of a heavier rate is visible
    // before it is saved rather than one screen later.
    final draft = s.copy();
    draft.nutrition.goal
      ..mode = mode
      ..rate = mode == 'maintain' ? 0 : (mode == 'cut' ? -(_rate ?? .5) : (_rate ?? .25))
      ..meals = _meals;
    final target = macroTargets(draft);
    final floored = targetFloored(draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Your goal')),
        Segmented<String>(
          value: mode,
          options: [
            SegOption('cut', label: t('Lose')),
            SegOption('maintain', label: t('Maintain')),
            SegOption('gain', label: t('Gain')),
          ],
          onChanged: (v) => setState(() {
            _mode = v;
            _rate = v == 'cut' ? 0.5 : (v == 'gain' ? 0.25 : 0);
          }),
        ),
        if (mode != 'maintain') ...[
          const SizedBox(height: 14),
          Section(
            title: t('Rate'),
            footer: mode == 'cut'
                ? t('About 0.5 kg a week is the fastest most people hold on to muscle through.')
                : t('Above about 0.25 kg a week, most of the gain stops being lean.'),
            children: [
              AppRow(
                title: t('Kilos per week'),
                trailing: SizedBox(
                  width: 110,
                  child: NumberBox(
                    value: _rate,
                    suffix: t('kg'),
                    // Beyond about a kilo a week the target hits its floor anyway.
                    max: 3,
                    onChanged: (v) => setState(() => _rate = v ?? 0),
                  ),
                ),
              ),
            ],
          ),
        ],
        SectionTitle(t('Meals')),
        // Five cells will not fit beside a label — the same reason added weight in the routine
        // editor is full width rather than squeezed into a row.
        AppStepper(
          label: t('Meals per day'),
          value: (_meals ?? 4).clamp(2, 6),
          step: 1,
          decimal: false,
          onChanged: (v) => setState(() => _meals = (v ?? 4).clamp(2, 6)),
        ),
        const SizedBox(height: 8),
        Text(
          t('Only decides how the day is split up. What you eat in total is what moves the scale.'),
          style: ts(TypeScale.foot, color: c.label3),
        ),
        const SizedBox(height: 14),
        Section(
          title: t('Kitchen'),
          footer: t('Which food the day plan suggests. Your own saved recipes always come first.'),
          children: [
            SelectRow<String>(
              icon: 'meal',
              title: t('Kitchen'),
              value: cuisineOf(s),
              sheetTitle: t('Which food do you cook?'),
              options: [
                for (final key in cuisines)
                  SelectOption(key, t(cuisineName[key] ?? key)),
              ],
              // Written straight through rather than held in a draft field: this changes what
              // the plan suggests, never what the day has to add up to, so it has no business
              // in the target being recomputed below.
              onChanged: (v) => ref
                  .read(appStateProvider.notifier)
                  .update((st) => st.nutrition.goal.cuisine = v),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (target != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t('Daily target'),
                          style: ts(TypeScale.foot, color: c.label2)),
                    ),
                    Text('${target.kcal.round()} ${t('kcal')}',
                        style: ts(TypeScale.head, color: c.label, weight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                MacroLegend(macros: target),
                if (floored) ...[
                  const SizedBox(height: 10),
                  Text(
                    // Names the rate they will actually get, rather than only saying no. A
                    // target that quietly differs from the goal is the thing worth explaining.
                    t('That rate would put you under what your body burns at rest, so the target is held there — about {0} kg a week. More activity, or a smaller number, closes the gap.',
                        fmtNum((achievableRate(draft) ?? 0).abs())),
                    style: ts(TypeScale.cap, color: c.sys.orange),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        AppButton(t('Save goal'), variant: BtnVariant.primary, onTap: () {
          ref.read(appStateProvider.notifier).update((st) {
            st.nutrition.goal
              ..mode = mode
              ..rate = mode == 'maintain'
                  ? null
                  : (mode == 'cut' ? -(_rate ?? .5).abs() : (_rate ?? .25).abs())
              ..meals = _meals;
          });
          widget.close();
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The arithmetic behind the number on screen.
///
/// A target nobody can take apart is one they can only believe or reject. This is the same
/// calculation the app already ran, written out — including the part where it overrode the
/// goal, which is the step most worth seeing.
Future<void> targetBreakdownSheet({String? iso}) =>
    showSheet<void>((context, close) => _BreakdownSheet(iso: iso));

class _BreakdownSheet extends ConsumerWidget {
  const _BreakdownSheet({this.iso});

  final String? iso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final steps = targetBreakdown(s, iso: iso);
    final target = macroTargets(s, iso: iso);

    if (steps.isEmpty || target == null) {
      return EmptyState(icon: 'info', message: t('Nothing to work out yet'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('How this was worked out')),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.label,
                            style: ts(TypeScale.body, color: c.label, weight: FontWeight.w500)),
                        if (step.note != null) ...[
                          const SizedBox(height: 2),
                          Text(step.note!, style: ts(TypeScale.cap, color: c.label3)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    // Signed, because a step that takes calories away should look like it.
                    '${step.value > 0 && step.label != t('Resting') && step.label != t('Maintenance') && step.label != t('Your own number') ? '+' : ''}'
                    '${step.value.round()}',
                    style: ts(TypeScale.body,
                        color: step.value < 0 ? c.sys.orange : c.label,
                        weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          Container(height: R.hair, color: c.sep),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text(t('Your target'),
                  style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
            ),
            Text('${target.kcal.round()} ${t('kcal')}',
                style: ts(TypeScale.head, color: c.acc, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Text(
            t('Every one of these is an estimate. Stats compares what your log predicts against what the scale actually does, which is the only way to find out how close they are for you.'),
            style: ts(TypeScale.cap, color: c.label3),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One food: what it is, and how much of it you had.
///
/// [initialGrams] seeds the portion field — used when the food arrives with a quantity already
/// attached, such as a suggested day plan's proposed portion. [onLogged] fires right after "Add
/// to the day" actually writes the item, so a caller showing its own pending/logged state (the
/// day plan sheet) can update without this sheet knowing anything about that state itself.
///
/// [onPicked] switches the sheet from logging to *choosing*: the portion is handed back and
/// nothing is written. That is what the recipe editor needs — an ingredient list is not a day,
/// and a food chosen for a recipe has not been eaten. Given [onPicked], [iso] is ignored.
Future<void> foodDetailSheet(Food food,
        {String? iso,
        double? slot,
        double? initialGrams,
        String? actionLabel,
        VoidCallback? onLogged,
        void Function(MealItem)? onPicked}) =>
    showSheet<void>((context, close) => _FoodDetailSheet(
        food: food,
        iso: iso,
        slot: slot,
        initialGrams: initialGrams,
        actionLabel: actionLabel,
        onLogged: onLogged,
        onPicked: onPicked,
        close: close));

class _FoodDetailSheet extends ConsumerStatefulWidget {
  const _FoodDetailSheet({
    required this.food,
    required this.close,
    this.iso,
    this.slot,
    this.initialGrams,
    this.actionLabel,
    this.onLogged,
    this.onPicked,
  });

  final Food food;
  final String? iso;
  final double? slot;
  final double? initialGrams;

  /// Overrides the button label the [onPicked] branch renders — "Add" reads wrong for the one
  /// caller reopening this sheet to change a quantity already in a list rather than to add a new
  /// one to it.
  final String? actionLabel;
  final VoidCallback? onLogged;
  final void Function(MealItem)? onPicked;
  final void Function([void]) close;

  @override
  ConsumerState<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<_FoodDetailSheet> {
  double _grams = 100;

  /// The household measure the count below multiplies, when the user picked one.
  ///
  /// Null means free grams: they typed a weight, or came in on one. Grams stay the single source
  /// of truth either way — this pair only decides which control is on screen and what it does to
  /// [_grams]. Nothing downstream stores "3 eggs"; `MealItem` holds a weight, so a portion that
  /// was later corrected in grams cannot disagree with itself.
  FoodPortion? _portion;
  double _count = 1;

  @override
  void initState() {
    super.initState();
    final grams = widget.initialGrams;
    if (grams == null) return;
    _grams = grams;
    // Reopening an ingredient that was entered as "3 x medium" should come back showing that,
    // not a bare 150 g — the weight is all that was stored, so the count is recovered by seeing
    // which measure divides it evenly. Only ever changes which control is preselected; the grams
    // are identical whichever branch is taken, so a coincidental match costs nothing.
    for (final p in widget.food.portions) {
      if (p.g <= 0) continue;
      final n = grams / p.g;
      if ((n - n.roundToDouble()).abs() < 0.01 && n >= 1 && n <= _maxCount) {
        _portion = p;
        _count = n.roundToDouble();
        return;
      }
    }
  }

  /// Well past any real serving, and what stops a held-down stepper from running away.
  static const _maxCount = 50.0;

  /// Picks a household measure, or goes back to typing grams.
  void _choosePortion(FoodPortion? p, {double count = 1}) => setState(() {
        _portion = p;
        _count = count;
        if (p != null) _grams = p.g * count;
      });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    ref.watch(appStateProvider);
    // A custom food can be edited from this very sheet, so the numbers below have to come from
    // the live registry rather than the (possibly stale) instance the caller opened us with —
    // `registerCustom` runs before the state that triggers this rebuild is assigned, so the
    // index is always ahead of the widget tree that reads it.
    final f = widget.food.custom ? (foods[widget.food.id] ?? widget.food) : widget.food;
    final item = f.portion(_grams);
    final macros = (kcal: item.kcal, p: item.p, c: item.c, f: item.f);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FoodImage(food: f),
          const SizedBox(height: 12),
          SheetTitle(t(f.n)),
          // Wrap, not Row: "18.8 g protein / 100 kcal" beside a category tag is wider than a
          // phone, and a Row would simply overflow rather than move it to a second line.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag(t(foodCategoryName[f.cat] ?? f.cat), icon: foodCategoryGlyph[f.cat]),
              if (f.p > 0)
                Tag('${fmtNum(f.proteinDensity)} ${t('g protein / 100 kcal')}',
                    accent: f.proteinDensity >= 10, capitalize: false),
            ],
          ),
          const SizedBox(height: 16),
          Section(
            title: t('Portion'),
            children: [
              // Three scrambled eggs is one ingredient with a count, not the same food added
              // three times — so the measure chosen below gets a multiplier of its own rather
              // than the user doing the arithmetic into the grams field.
              if (_portion case final p?)
                AppRow(
                  title: t('How many'),
                  subtitle: t(p.n),
                  trailing: SizedBox(
                    width: 128,
                    child: AppStepper(
                      value: _count,
                      decimal: false,
                      onChanged: (v) =>
                          _choosePortion(p, count: (v ?? 1).clamp(1, _maxCount)),
                    ),
                  ),
                ),
              AppRow(
                title: t('Grams'),
                trailing: SizedBox(
                  width: 110,
                  child: NumberBox(
                    value: _grams,
                    decimal: false,
                    suffix: t('g'),
                    max: 5000,
                    // Typing a weight is the override, so it drops the measure rather than
                    // leaving a count on screen that no longer multiplies out to what is shown.
                    onChanged: (v) => setState(() {
                      _grams = v ?? 0;
                      _portion = null;
                      _count = 1;
                    }),
                  ),
                ),
              ),
            ],
          ),
          ChipRow(children: [
            // The food's own household measures come first, because nobody can picture 180 g
            // of chicken and everybody can picture one breast. Grams stay in the field above
            // and stay authoritative — these only fill it in.
            //
            // The label is the measure alone, not "1 medium": with a count above it, a chip
            // that says "1" while the row says 3 contradicts itself.
            for (final portion in f.portions)
              AppChip(t(portion.n),
                  selected: _portion?.n == portion.n,
                  capitalize: false,
                  onTap: () => _choosePortion(portion)),
            for (final g in const [100.0, 200.0])
              AppChip('${g.round()} g',
                  selected: _portion == null && _grams == g,
                  capitalize: false,
                  onTap: () => setState(() {
                        _portion = null;
                        _count = 1;
                        _grams = g;
                      })),
          ]),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${_grams.round()} g',
                          style: ts(TypeScale.foot, color: c.label2)),
                    ),
                    Text('${item.kcal.round()} ${t('kcal')}',
                        style: ts(TypeScale.head, color: c.label, weight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                Center(child: MacroDonut(macros: macros)),
                const SizedBox(height: 14),
                MacroRows(
                  macros: macros,
                  extras: [
                    if (Food.per(f.fib, _grams) case final v? when v > 0)
                      (label: 'Fibre', g: v),
                    if (Food.per(f.sug, _grams) case final v? when v > 0)
                      (label: 'Sugars', g: v),
                    if (Food.per(f.sat, _grams) case final v? when v > 0)
                      (label: 'Saturates', g: v),
                    if (Food.per(f.salt, _grams) case final v? when v > 0)
                      (label: 'Salt', g: v),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${t('Per 100 g')}: ${f.kcal.round()} ${t('kcal')} · '
                  '${fmtNum(f.p)}P ${fmtNum(f.c)}C ${fmtNum(f.f)}${t('F')}',
                  style: ts(TypeScale.cap, color: c.label3),
                ),
              ],
            ),
          ),
          if (f.custom) ...[
            const SizedBox(height: 8),
            AppButton(t('Edit food'),
                icon: 'pencil',
                variant: BtnVariant.tinted,
                onTap: () {
                  final cf = ref.read(appStateProvider).nutrition.foods
                      .where((x) => x.id == f.id)
                      .firstOrNull;
                  if (cf != null) customFoodSheet(existing: cf);
                }),
          ],
          if (swapsFor(ref.watch(appStateProvider), f) case final swaps
              when swaps.isNotEmpty) ...[
            const SizedBox(height: 4),
            SecHeading(t('More protein for the same calories')),
            for (final swap in swaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListItem(
                  leading: FoodThumb(food: swap, size: 40),
                  onTap: () => foodDetailSheet(swap,
                      iso: widget.iso, slot: widget.slot, onPicked: widget.onPicked),
                  trailing: [
                    Tag('+${fmtNum(swap.p - f.p)}P', accent: true, capitalize: false),
                  ],
                  child: ItemText(
                    t(swap.n),
                    subtitle: '${swap.kcal.round()} ${t('kcal')} · '
                        '${fmtNum(swap.p)}P ${t('per 100 g')}',
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
          if (widget.onPicked case final picked?)
            AppButton(widget.actionLabel ?? t('Add'), variant: BtnVariant.primary, onTap: () {
              if (_grams <= 0) {
                ref.read(uiProvider).toast(t('Enter a portion first'));
                return;
              }
              // Closed before the callback runs, not after: the picker underneath closes itself
              // from inside [picked], and popping these two in any order but last-in-first-out
              // takes the wrong route off the stack.
              widget.close();
              picked(item);
            })
          else if (widget.iso != null) ...[
            AppButton(t('Add to the day'), variant: BtnVariant.primary, onTap: () {
              if (_grams <= 0) {
                ref.read(uiProvider).toast(t('Enter a portion first'));
                return;
              }
              addMealItem(ref, iso: widget.iso!, slot: widget.slot, item: item);
              widget.onLogged?.call();
              widget.close();
              ref.read(uiProvider).toast(t('Added {0}', t(f.n)));
            }),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Appends one item to the day, reusing the slot's meal if it already has one.
///
/// Reusing rather than always appending is what keeps a day readable: three eggs, toast and
/// coffee logged one at a time should be one breakfast, not three breakfasts.
void addMealItem(WidgetRef ref, {required String iso, double? slot, required MealItem item}) {
  ref.read(appStateProvider.notifier).update((st) {
    final existing = st.meals.where((m) => m.d == iso && m.slot == slot).firstOrNull;
    if (existing != null) {
      existing.items.add(item.copy());
      return;
    }
    st.meals.add(Meal(
      id: 'ml${uid()}',
      d: iso,
      t: DateTime.now().millisecondsSinceEpoch,
      slot: slot,
      items: [item.copy()],
    ));
  });
}

/// Logs one portion of a saved recipe into a slot in one tap.
///
/// Goes through [addMealItem] rather than appending a Meal directly, so slot-merging behaves
/// exactly as it does for a food added by hand — a template dropped into a slot that already
/// has something in it joins that meal instead of creating a second one.
///
/// One *portion*, not the whole ingredient list: a recipe written down as the pot it was cooked
/// in is eaten a bowl at a time, and `MealTemplate.portion` is where that division lives.
void logTemplate(WidgetRef ref, MealTemplate template,
    {required String iso, double? slot}) {
  for (final item in template.portion()) {
    addMealItem(ref, iso: iso, slot: slot, item: item);
  }
  ref.read(appStateProvider.notifier).update((st) {
    final saved = st.nutrition.templates.where((x) => x.id == template.id).firstOrNull;
    if (saved == null) return;
    saved.used = (saved.used ?? 0) + 1;
    saved.last = DateTime.now().millisecondsSinceEpoch;
  });
}

/// The meal slots a recipe can be filed under, as English source strings.
///
/// Taken from the meal splits rather than invented, so a recipe's slot and the slot the planner
/// is filling are the same word. Deliberately the four names every split is built out of and not
/// whatever `mealSplit` returns for the current setting: a recipe outlives a change to how many
/// meals a day is divided into, and re-filing every breakfast because the user moved from four
/// meals to five would be absurd.
const recipeSlots = <String>['Breakfast', 'Lunch', 'Snack', 'Dinner'];

/// Write down a recipe, or change one already written down.
///
/// [existing] edits in place; without it this is a new recipe, optionally seeded with [items]
/// from a meal already on the day — which is how the "logged this three times, save it?" offer
/// arrives here with the work already done.
/// [slot] pre-files a new recipe under a meal — an English name from [recipeSlots], never a
/// translated one, since that is what gets stored and what the planner matches on.
Future<void> recipeSheet(
  WidgetRef ref, {
  MealTemplate? existing,
  List<MealItem>? items,
  String? suggestedName,
  String? slot,
}) =>
    showSheet<void>((context, close) => _RecipeSheet(
          existing: existing,
          items: items,
          suggestedName: suggestedName,
          slot: slot,
          close: close,
        ));

/// Name a meal and keep it — the shape the day screen's "save it?" offer still calls.
Future<void> saveMealSheet(WidgetRef ref, List<MealItem> items,
        {String? suggestedName, String? slot}) =>
    recipeSheet(ref, items: items, suggestedName: suggestedName, slot: slot);

class _RecipeSheet extends ConsumerStatefulWidget {
  const _RecipeSheet({
    required this.close,
    this.existing,
    this.items,
    this.suggestedName,
    this.slot,
  });

  final MealTemplate? existing;
  final List<MealItem>? items;
  final String? suggestedName;
  final String? slot;
  final void Function([void]) close;

  @override
  ConsumerState<_RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends ConsumerState<_RecipeSheet> {
  late final TextEditingController _name = TextEditingController(
      text: widget.existing?.n ?? widget.suggestedName ?? '');

  /// The draft ingredient list. Copied out of whatever seeded it, because a sheet the user can
  /// close without saving must not have edited the stored recipe on the way.
  late final List<MealItem> _items = [
    for (final i in widget.existing?.items ?? widget.items ?? const <MealItem>[]) i.copy()
  ];

  late String? _slot =
      widget.existing?.slot ?? (recipeSlots.contains(widget.slot) ? widget.slot : null);

  late double _servings = widget.existing?.perServing ?? 1;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  double get _batchKcal => _items.fold(0.0, (a, i) => a + i.kcal);

  ({double kcal, double p, double c, double f}) get _perServing => (
        kcal: _batchKcal / _servings,
        p: _items.fold<double>(0, (a, i) => a + i.p) / _servings,
        c: _items.fold<double>(0, (a, i) => a + i.c) / _servings,
        f: _items.fold<double>(0, (a, i) => a + i.f) / _servings,
      );

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ref.read(uiProvider).toast(t('Give it a name'));
      return;
    }
    if (_items.isEmpty) {
      ref.read(uiProvider).toast(t('Add at least one ingredient'));
      return;
    }

    ref.read(appStateProvider.notifier).update((st) {
      final saved = st.nutrition.templates.where((x) => x.id == widget.existing?.id).firstOrNull;
      final target = saved ??
          () {
            final made = MealTemplate(id: 'mt${uid()}', n: name, used: 0);
            st.nutrition.templates.add(made);
            return made;
          }();
      target
        ..n = name
        ..items = [for (final i in _items) i.copy()]
        ..slot = _slot
        // Absent rather than 1, so a recipe nobody batch-cooks stays out of the export the way
        // every other never-chosen field does.
        ..servings = _servings == 1 ? null : _servings
        ..last = DateTime.now().millisecondsSinceEpoch;
    });
    widget.close();
    ref.read(uiProvider).toast(t('Saved {0}', name));
  }

  /// Reopens the same detail sheet an ingredient was added through, seeded with the grams it
  /// already carries, and replaces that entry rather than appending a new one.
  void _editIngredient(int index) {
    final item = _items[index];
    foodDetailSheet(
      foods.or(item.fid ?? ''),
      initialGrams: item.g,
      actionLabel: t('Save'),
      onPicked: (edited) => setState(() => _items[index] = edited),
    );
  }

  void _delete() {
    final id = widget.existing?.id;
    if (id == null) return;
    ref
        .read(appStateProvider.notifier)
        .update((st) => st.nutrition.templates.removeWhere((x) => x.id == id));
    widget.close();
    ref.read(uiProvider).toast(t('Deleted {0}', widget.existing!.n));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final per = _perServing;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(_isNew ? t('New recipe') : t('Edit recipe')),
          Text(
            t('Write down what you actually cook. Saved recipes log in one tap, and the day plan builds itself out of them.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 12),
          AppTextField(controller: _name, placeholder: t('Name')),
          const SizedBox(height: 10),
          Section(children: [
            SelectRow<String?>(
              icon: 'meal',
              title: t('Meal'),
              value: _slot,
              sheetTitle: t('When do you eat this?'),
              options: [
                SelectOption<String?>(null, t('Any meal')),
                for (final slot in recipeSlots) SelectOption<String?>(slot, t(slot)),
              ],
              onChanged: (v) => setState(() => _slot = v),
            ),
            AppRow(
              icon: 'copy',
              title: t('Makes'),
              subtitle: t('Portions this recipe serves'),
              trailing: SizedBox(
                width: 128,
                child: AppStepper(
                  value: _servings,
                  decimal: false,
                  onChanged: (v) => setState(() => _servings = (v ?? 1).clamp(1, 20)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SecHeading(t('Ingredients')),
          if (_items.isEmpty)
            EmptyState(
              icon: 'meal',
              message: t('Nothing in it yet'),
              detail: t('Add the foods it is made of.'),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(children: [
                        // Tapping the row is how a quantity already on the list changes — reusing
                        // the same detail sheet the ingredient was added through, seeded with what
                        // is already there, rather than the only way out being to delete this row
                        // and search for the same food again to add it back at a new weight.
                        Expanded(
                          child: Pressable(
                            scale: .98,
                            onTap: () => _editIngredient(i),
                            child: Row(children: [
                              FoodThumb(food: foods.or(_items[i].fid ?? ''), size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(mealItemLabel(_items[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(TypeScale.cap, color: c.label2)),
                              ),
                              Text('${_items[i].kcal.round()}',
                                  style: ts(TypeScale.cap, color: c.label3)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Pressable(
                          scale: .9,
                          onTap: () => setState(() => _items.removeAt(i)),
                          child: AppIcon('xmark', size: 12, color: c.label4),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          AppButton(t('Add ingredient'), icon: 'plus', onTap: () {
            logMealSheet(
              ref,
              title: t('Add ingredient'),
              onPicked: (item) => setState(() => _items.add(item)),
            );
          }),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        _servings > 1 ? t('One portion') : t('This recipe'),
                        style: ts(TypeScale.foot, color: c.label2),
                      ),
                    ),
                    Text('${per.kcal.round()} ${t('kcal')}',
                        style: ts(TypeScale.head, color: c.label, weight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  MacroSplit(macros: per),
                  const SizedBox(height: 8),
                  MacroLegend(macros: per),
                  if (_servings > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      t('{0} portions, {1} kcal in all', _servings.round(), _batchKcal.round()),
                      style: ts(TypeScale.cap, color: c.label3),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppButton(t('Save'), variant: BtnVariant.primary, onTap: _save),
          if (!_isNew) ...[
            const SizedBox(height: 8),
            AppButton(t('Delete'), variant: BtnVariant.danger, onTap: _delete),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Repeat a day you have already logged.
///
/// Most days are a variation on a day you have already had, and re-entering one food at a time
/// is the friction that ends food logs.
Future<void> copyDaySheet(WidgetRef ref, {required String to}) =>
    // Same shape as the food picker, same reason: a list of every day ever logged, which is a
    // list with no ceiling on it.
    showSheet<void>(
        scrollable: false, (context, close) => _CopyDaySheet(to: to, close: close));

class _CopyDaySheet extends ConsumerWidget {
  const _CopyDaySheet({required this.to, required this.close});

  final String to;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final days = loggedDays(s, excluding: to);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Copy a day')),
        if (days.isEmpty)
          EmptyState(
            icon: 'calendar',
            message: t('Nothing to copy yet'),
            detail: t('Log a day and it becomes a starting point for the next one.'),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListItem(
                      onTap: () {
                        final meals = mealsOn(s, d);
                        ref.read(appStateProvider.notifier).update((st) {
                          for (final m in meals) {
                            st.meals.add(Meal(
                              id: 'ml${uid()}',
                              d: to,
                              t: DateTime.now().millisecondsSinceEpoch,
                              slot: m.slot,
                              items: [for (final i in m.items) i.copy()],
                            ));
                          }
                        });
                        close();
                        ref.read(uiProvider).toast(t('Copied {0} meals', meals.length));
                      },
                      child: ItemText(
                        DateFormat('EEEE, d MMM', dateLocale).format(dayOf(d)),
                        subtitle: '${dayTotals(s, d).kcal.round()} ${t('kcal')} · '
                            '${mealsOn(s, d).length} ${t('meals')}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The display name for a logged item, resolving a catalogue id when it has one.
String mealItemName(MealItem item) =>
    item.n ?? (item.fid == null ? t('Food') : t(foods.or(item.fid!).n));

/// The name plus its portion — "Chicken breast · 220 g".
///
/// A quick-added item has no weight at all, and "0 g" would read as a bug rather than as the
/// deliberate absence it is.
String mealItemLabel(MealItem item) {
  final name = mealItemName(item);
  return item.g > 0 ? '$name · ${item.g.round()} g' : name;
}

/// Search the catalogue and add something to a meal.
/// [onPicked] makes this a chooser rather than a logger — see [foodDetailSheet]. With it set,
/// [iso] is not needed: the recipe editor is picking an ingredient, not filling in a day.
Future<void> logMealSheet(WidgetRef ref,
        {String? iso, double? slot, String? title, void Function(MealItem)? onPicked}) =>
    showSheet<void>((context, close) => _LogMealSheet(
        iso: iso, slot: slot, title: title, onPicked: onPicked, close: close));

class _LogMealSheet extends ConsumerStatefulWidget {
  const _LogMealSheet({
    required this.close,
    this.iso,
    this.slot,
    this.title,
    this.onPicked,
  });

  final String? iso;
  final double? slot;
  final String? title;
  final void Function(MealItem)? onPicked;
  final void Function([void]) close;

  @override
  ConsumerState<_LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends ConsumerState<_LogMealSheet> {
  String _query = '';
  String? _cat;

  /// Picking an ingredient finishes with this sheet too, not just the one on top of it.
  ///
  /// Choosing a food to log leaves the picker up, because the next thing you do is usually log
  /// another one. Choosing an ingredient for a recipe is the opposite: the recipe is what you
  /// came here from and what you need to see the result on.
  void Function(MealItem)? get _picked {
    final onPicked = widget.onPicked;
    if (onPicked == null) return null;
    return (item) {
      widget.close();
      onPicked(item);
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    var list = foods.search(s, _query);
    if (_cat != null) list = [for (final f in list) if (f.cat == _cat) f];

    // With no query, what you logged recently is far more likely than anything else.
    final recent = _query.isEmpty && _cat == null ? recentFoods(s) : const <Food>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(widget.title ?? t('Add food')),
        SearchField(
          value: _query,
          placeholder: t('Search foods'),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        ChipRow(children: [
          AppChip(t('All'), selected: _cat == null, onTap: () => setState(() => _cat = null)),
          for (final cat in foodCategories)
            AppChip(t(foodCategoryName[cat] ?? cat),
                icon: foodCategoryGlyph[cat],
                selected: _cat == cat,
                onTap: () => setState(() => _cat = _cat == cat ? null : cat)),
        ]),
        const SizedBox(height: 10),
        // A hard cap, not `Flexible`. `Flexible` only means something under an ancestor with a
        // bounded height to divide up, and the sheet shell scrolls its content under an
        // unbounded `SingleChildScrollView` — the shape that let this list grow to all 240-odd
        // foods and push everything below it, buttons included, off the bottom of the screen.
        // Capping it here means the list is compact for a short result and scrolls on its own
        // once it outgrows the cap; the sheet as a whole still scrolls too, for whatever the cap
        // plus the rest of this content adds up to on a short phone.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .4),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (recent.isNotEmpty) ...[
                SecHeading(t('Recent')),
                for (final f in recent)
                  _FoodRow(
                      food: f,
                      iso: widget.iso,
                      slot: widget.slot,
                      onPicked: _picked),
                const SizedBox(height: 10),
                SecHeading(t('All foods')),
              ],
              if (list.isEmpty)
                EmptyState(
                  icon: 'magnifier',
                  message: t('No foods match'),
                  detail: t('Add one of your own instead.'),
                )
              else
                for (final f in list)
                  _FoodRow(
                      food: f,
                      iso: widget.iso,
                      slot: widget.slot,
                      onPicked: _picked),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // The plate is usually still in front of the user when they open this sheet, and it fills
        // it in one action rather than one food at a time — so it goes above the two that add a
        // single item, at full width, rather than becoming a third narrow button beside them.
        //
        // It was reachable before only from a 15px glyph on the card behind this sheet, which is
        // not an entry point anybody finds. Absent rather than disabled when the feature is off,
        // like every other affordance this feature owns.
        if (widget.iso case final iso?
            when widget.onPicked == null && ref.watch(aiMealPhotoProvider).isAvailable) ...[
          AppButton(t('Log from a photo'), icon: 'sparkles', onTap: () {
            // Closed first: this sheet has served its purpose, and leaving it under the review
            // sheet would put the user back in a food search after they confirmed a meal.
            widget.close();
            mealPhotoSheet(ref, iso: iso, slot: widget.slot);
          }),
          const SizedBox(height: 8),
        ],
        Row(children: [
          // Calories with no food behind them belong to a day, not to a recipe: an ingredient
          // list whose entries cannot be re-costed is not one the planner can scale.
          //
          // Icon tiles rather than full-width buttons: these two are the fallbacks for when the
          // search above has come up empty, not the primary way in, and a pair of tall bold-text
          // buttons was heavier than that role earns. The caption underneath is what the tab bar
          // already does to pair an icon with a word without the icon losing to it.
          if (widget.iso case final iso? when widget.onPicked == null) ...[
            _QuickAction(icon: 'bolt', label: t('Quick add'), onTap: () {
              widget.close();
              quickAddSheet(ref, iso: iso, slot: widget.slot);
            }),
            const SizedBox(width: 8),
          ],
          _QuickAction(icon: 'plus', label: t('Your own food'), onTap: () {
            widget.close();
            customFoodSheet(iso: widget.iso, slot: widget.slot);
          }),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, this.iso, this.slot, this.onPicked});

  final Food food;
  final String? iso;
  final double? slot;
  final void Function(MealItem)? onPicked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListItem(
        leading: FoodThumb(food: food, size: 44),
        onTap: () => foodDetailSheet(food, iso: iso, slot: slot, onPicked: onPicked),
        child: ItemText(
          t(food.n),
          subtitle: '${food.kcal.round()} ${t('kcal')} · '
              '${fmtNum(food.p)}P ${fmtNum(food.c)}C ${fmtNum(food.f)}F · '
              '${t('per 100 g')}',
        ),
      ),
    );
  }
}

/// A compact icon-and-caption tile, for the two fallbacks under the food search.
///
/// The same pairing the tab bar uses — an icon carries the recognition, the small caption
/// underneath is what keeps "bolt" and "plus" from being two visually identical grey glyphs.
/// Sized to the plain [AppButton] fill so the row still reads as part of the same control family,
/// just a quieter one.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Pressable.builder(
        onTap: onTap,
        build: (context, pressed) => AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: pressed ? c.surface3 : c.surface2,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 19, color: c.label),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(TypeScale.cap, size: 11, color: c.label2, weight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calories without a food behind them.
///
/// A restaurant meal, someone else's cooking, a guess. There is no honest way to itemise those,
/// and forcing the attempt is how a day ends up with nothing logged at all — which hurts far
/// more than a rough number does, because `evolution()` reads an unlogged day as a day nobody
/// ate on and quietly poisons the comparison the whole feature rests on.
Future<void> quickAddSheet(WidgetRef ref, {required String iso, double? slot}) =>
    showSheet<void>((context, close) => _QuickAddSheet(iso: iso, slot: slot, close: close));

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({required this.iso, required this.close, this.slot});

  final String iso;
  final double? slot;
  final void Function([void]) close;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _name = TextEditingController();
  double? _kcal;
  double? _p;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Quick add')),
        Text(
          t('For a meal you cannot break down. A rough number beats an empty day — a day with nothing logged is read as a day you did not eat.'),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 12),
        AppTextField(controller: _name, placeholder: t('What was it? (optional)')),
        const SizedBox(height: 10),
        Section(
          footer: t('Protein is worth guessing at if you can. Everything else can wait.'),
          children: [
            AppRow(
              title: t('Calories'),
              trailing: SizedBox(
                width: 120,
                child: NumberBox(
                  value: _kcal,
                  decimal: false,
                  nullable: true,
                  placeholder: '600',
                  suffix: t('kcal'),
                  max: 10000,
                  onChanged: (v) => setState(() => _kcal = v),
                ),
              ),
            ),
            AppRow(
              title: t('Protein'),
              subtitle: t('grams, if you know'),
              trailing: SizedBox(
                width: 110,
                child: NumberBox(
                  value: _p,
                  decimal: false,
                  nullable: true,
                  suffix: t('g'),
                  max: 500,
                  onChanged: (v) => setState(() => _p = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppButton(t('Add'), variant: BtnVariant.primary, onTap: () {
          final kcal = _kcal ?? 0;
          if (kcal <= 0) {
            ref.read(uiProvider).toast(t('Enter the calories'));
            return;
          }
          final name = _name.text.trim();
          addMealItem(
            ref,
            iso: widget.iso,
            slot: widget.slot,
            item: MealItem(
              n: name.isEmpty ? t('Quick add') : name,
              // Grams are unknown and must not be invented: a zero here is honest, and nothing
              // downstream divides by it.
              g: 0,
              kcal: kcal,
              p: _p ?? 0,
              c: 0,
              f: 0,
            ),
          );
          widget.close();
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The foods logged most recently, most recent first, one entry each.
List<Food> recentFoods(AppState s, {int take = 8}) {
  final seen = <String>{};
  final out = <Food>[];
  for (final m in s.meals.reversed) {
    for (final i in m.items.reversed) {
      final id = i.fid;
      if (id == null || !seen.add(id)) continue;
      final f = foods[id];
      if (f != null) out.add(f);
      if (out.length >= take) return out;
    }
  }
  return out;
}

/// A food the catalogue does not carry — created, or edited.
///
/// Opened empty from the food library, and prefilled from the photo sheet, where the model has
/// just described a food the catalogue does not have and the figures are already on screen. The
/// prefill arrives as loose numbers rather than as the photo feature's `Per100` record on
/// purpose: this sheet is the app's ordinary way of adding a food, and it should not have to know
/// that an AI feature exists to be handed a starting point.
///
/// [existing] switches the sheet to editing: every field seeds from it instead of the loose
/// prefill arguments, saving mutates that same food in place, and a delete button appears —
/// the same shape `customExSheet` uses for custom exercises.
///
/// [onSaved] replaces the jump to `foodDetailSheet` — a caller that has its own idea of what
/// happens next (the photo review, which wants the new food back in the row it came from) says so
/// by passing one.
Future<void> customFoodSheet({
  CustomFood? existing,
  String? iso,
  double? slot,
  String? name,
  String? cat,
  double? kcal,
  double? p,
  double? c,
  double? f,
  void Function(CustomFood)? onSaved,
}) =>
    showSheet<void>((context, close) => _CustomFoodSheet(
          existing: existing,
          iso: iso,
          slot: slot,
          close: close,
          name: name,
          cat: cat,
          kcal: kcal,
          p: p,
          c: c,
          f: f,
          onSaved: onSaved,
        ));

class _CustomFoodSheet extends ConsumerStatefulWidget {
  const _CustomFoodSheet({
    required this.close,
    this.existing,
    this.iso,
    this.slot,
    this.name,
    this.cat,
    this.kcal,
    this.p,
    this.c,
    this.f,
    this.onSaved,
  });

  final CustomFood? existing;
  final String? iso;
  final double? slot;
  final String? name;
  final String? cat;
  final double? kcal;
  final double? p;
  final double? c;
  final double? f;
  final void Function(CustomFood)? onSaved;
  final void Function([void]) close;

  @override
  ConsumerState<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends ConsumerState<_CustomFoodSheet> {
  final _name = TextEditingController();
  String _cat = 'protein';
  double? _kcal;
  double? _p;
  double? _c;
  double? _f;
  double? _fib;
  double? _sug;
  double? _sat;
  double? _salt;

  @override
  void initState() {
    super.initState();
    // Every field stays editable. A prefill is a starting point the user can overwrite, which is
    // the whole reason the photo sheet sends them here instead of saving a food behind their back.
    final e = widget.existing;
    _name.text = e?.n ?? widget.name ?? '';
    final cat = e?.cat ?? widget.cat;
    // Only a category the app actually has; anything else keeps the default rather than putting
    // a value in the picker that none of its options match.
    if (cat != null && foodCategories.contains(cat)) _cat = cat;
    _kcal = e?.kcal ?? widget.kcal;
    _p = e?.p ?? widget.p;
    _c = e?.c ?? widget.c;
    _f = e?.f ?? widget.f;
    _fib = e?.fib;
    _sug = e?.sug;
    _sat = e?.sat;
    _salt = e?.salt;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final editing = widget.existing != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(editing ? t('Edit food') : t('Your own food')),
          Text(t('Per 100 g, the way the labels are written.'),
              style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 12),
          AppTextField(controller: _name, placeholder: t('Name')),
          const SizedBox(height: 10),
          SelectRow<String>(
            title: t('Category'),
            value: _cat,
            options: [
              for (final cat in foodCategories)
                SelectOption(cat, t(foodCategoryName[cat] ?? cat)),
            ],
            onChanged: (v) => setState(() => _cat = v),
          ),
          Section(children: [
            // Per 100 g, so these are not preferences: 100 g of anything cannot hold more than
            // 100 g of one macro, and pure fat is about 900 kcal.
            for (final row in [
              (t('Calories'), _kcal, (double? v) => setState(() => _kcal = v), t('kcal'), 900.0),
              (t('Protein'), _p, (double? v) => setState(() => _p = v), t('g'), 100.0),
              (t('Carbs'), _c, (double? v) => setState(() => _c = v), t('g'), 100.0),
              (t('Fat'), _f, (double? v) => setState(() => _f = v), t('g'), 100.0),
            ])
              AppRow(
                title: row.$1,
                trailing: SizedBox(
                  width: 110,
                  child: NumberBox(
                    value: row.$2,
                    nullable: true,
                    suffix: row.$4,
                    max: row.$5,
                    onChanged: row.$3,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(t('Optional, the rest of the label'), style: ts(TypeScale.foot, color: c.label3)),
          Section(children: [
            for (final row in [
              (t('Fibre'), _fib, (double? v) => setState(() => _fib = v)),
              (t('Sugars'), _sug, (double? v) => setState(() => _sug = v)),
              (t('Saturates'), _sat, (double? v) => setState(() => _sat = v)),
              (t('Salt'), _salt, (double? v) => setState(() => _salt = v)),
            ])
              AppRow(
                title: row.$1,
                trailing: SizedBox(
                  width: 110,
                  child: NumberBox(
                    value: row.$2,
                    nullable: true,
                    suffix: t('g'),
                    max: 100.0,
                    onChanged: row.$3,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          AppButton(editing ? t('Save') : t('Save food'), variant: BtnVariant.primary, onTap: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              ref.read(uiProvider).toast(t('Give it a name'));
              return;
            }
            if ((_kcal ?? 0) <= 0) {
              ref.read(uiProvider).toast(t('Enter the calories per 100 g'));
              return;
            }
            final id = widget.existing?.id ?? 'cf${uid()}';
            final food = CustomFood(
              id: id,
              n: name,
              cat: _cat,
              kcal: _kcal ?? 0,
              p: _p ?? 0,
              c: _c ?? 0,
              f: _f ?? 0,
              fib: _fib,
              sug: _sug,
              sat: _sat,
              salt: _salt,
            );
            ref.read(appStateProvider.notifier).update((st) {
              if (editing) {
                for (final cf in st.nutrition.foods) {
                  if (cf.id == id) {
                    cf
                      ..n = name
                      ..cat = _cat
                      ..kcal = food.kcal
                      ..p = food.p
                      ..c = food.c
                      ..f = food.f
                      ..fib = _fib
                      ..sug = _sug
                      ..sat = _sat
                      ..salt = _salt;
                  }
                }
              } else {
                st.nutrition.foods.add(food.copy());
              }
            });
            widget.close();
            final saved = widget.onSaved;
            if (saved != null) {
              // The caller is mid-flow and wants the food, not a portion form on top of it.
              saved(food);
              return;
            }
            if (editing) {
              ref.read(uiProvider).toast(t('Saved'));
              return;
            }
            // Straight on to the portion, because adding a food is almost never the actual
            // goal — logging what you just ate is.
            if (widget.iso != null) {
              foodDetailSheet(Food.fromCustom(food), iso: widget.iso, slot: widget.slot);
            }
          }),
          if (editing) ...[
            const SizedBox(height: 8),
            AppButton(t('Delete food'),
                variant: BtnVariant.danger,
                icon: 'trash',
                onTap: () {
                  widget.close();
                  deleteCustomFood(ref, widget.existing!);
                }),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Remove one of your own foods.
///
/// Already-logged meals keep their stored numbers — `MealItem` snapshots them at the moment
/// they were eaten, and a dangling id renders through `Foods.or` — so nothing else needs to
/// change on the way out, unlike a deleted exercise's name.
///
/// The notifier and the toast are read out of [ref] up front, not inside `onConfirm`: the sheet
/// this is called from closes itself right away, and by the time the confirm dialog's own button
/// is actually tapped its widget is long unmounted — `ref.read` at that point throws rather than
/// reading stale state.
void deleteCustomFood(WidgetRef ref, CustomFood food) {
  final notifier = ref.read(appStateProvider.notifier);
  final ui = ref.read(uiProvider);
  confirmSheet(
    title: t('Delete “{0}”?', food.n),
    message: t('Already-logged meals keep their numbers.'),
    confirmText: t('Delete'),
    danger: true,
    onConfirm: () {
      notifier.update((st) => st.nutrition.foods.removeWhere((x) => x.id == food.id));
      ui.toast(t('Deleted {0}', food.n));
    },
  );
}
