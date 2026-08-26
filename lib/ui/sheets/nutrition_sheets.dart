import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/coaching.dart';
import '../../domain/foods.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../../ui/app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/page.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/stepper.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
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
Future<void> foodDetailSheet(Food food,
        {String? iso, double? slot, double? initialGrams, VoidCallback? onLogged}) =>
    showSheet<void>((context, close) => _FoodDetailSheet(
        food: food, iso: iso, slot: slot, initialGrams: initialGrams, onLogged: onLogged, close: close));

class _FoodDetailSheet extends ConsumerStatefulWidget {
  const _FoodDetailSheet({
    required this.food,
    required this.close,
    this.iso,
    this.slot,
    this.initialGrams,
    this.onLogged,
  });

  final Food food;
  final String? iso;
  final double? slot;
  final double? initialGrams;
  final VoidCallback? onLogged;
  final void Function([void]) close;

  @override
  ConsumerState<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<_FoodDetailSheet> {
  double _grams = 100;

  @override
  void initState() {
    super.initState();
    if (widget.initialGrams != null) _grams = widget.initialGrams!;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = widget.food;
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
              AppRow(
                title: t('Grams'),
                trailing: SizedBox(
                  width: 110,
                  child: NumberBox(
                    value: _grams,
                    decimal: false,
                    suffix: t('g'),
                    max: 5000,
                    onChanged: (v) => setState(() => _grams = v ?? 0),
                  ),
                ),
              ),
            ],
          ),
          ChipRow(children: [
            // The food's own household measures come first, because nobody can picture 180 g
            // of chicken and everybody can picture one breast. Grams stay in the field above
            // and stay authoritative — this only fills it in.
            for (final portion in f.portions)
              AppChip('1 ${t(portion.n)}',
                  selected: _grams == portion.g,
                  capitalize: false,
                  onTap: () => setState(() => _grams = portion.g)),
            for (final g in const [100.0, 200.0])
              AppChip('${g.round()} g',
                  selected: _grams == g,
                  capitalize: false,
                  onTap: () => setState(() => _grams = g)),
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
                const SizedBox(height: 10),
                MacroSplit(macros: macros),
                const SizedBox(height: 8),
                MacroLegend(macros: macros),
                if (f.fibreIn(_grams) case final fibre? when fibre > 0) ...[
                  const SizedBox(height: 6),
                  Text('${t('Fibre')} ${fmtNum(fibre)} g',
                      style: ts(TypeScale.cap, color: c.label3)),
                ],
              ],
            ),
          ),
          if (swapsFor(ref.watch(appStateProvider), f) case final swaps
              when swaps.isNotEmpty) ...[
            const SizedBox(height: 4),
            SecHeading(t('More protein for the same calories')),
            for (final swap in swaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListItem(
                  leading: FoodThumb(food: swap, size: 40),
                  onTap: () => foodDetailSheet(swap, iso: widget.iso, slot: widget.slot),
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
          if (widget.iso != null) ...[
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

/// Logs a whole saved meal into a slot in one tap.
///
/// Goes through [addMealItem] rather than appending a Meal directly, so slot-merging behaves
/// exactly as it does for a food added by hand — a template dropped into a slot that already
/// has something in it joins that meal instead of creating a second one.
void logTemplate(WidgetRef ref, MealTemplate template,
    {required String iso, double? slot}) {
  for (final item in template.items) {
    addMealItem(ref, iso: iso, slot: slot, item: item);
  }
  ref.read(appStateProvider.notifier).update((st) {
    final saved = st.nutrition.templates.where((x) => x.id == template.id).firstOrNull;
    if (saved == null) return;
    saved.used = (saved.used ?? 0) + 1;
    saved.last = DateTime.now().millisecondsSinceEpoch;
  });
}

/// Name a meal and keep it.
Future<void> saveMealSheet(WidgetRef ref, List<MealItem> items, {String? suggestedName}) =>
    showSheet<void>((context, close) =>
        _SaveMealSheet(items: items, suggestedName: suggestedName, close: close));

class _SaveMealSheet extends ConsumerStatefulWidget {
  const _SaveMealSheet({required this.items, required this.close, this.suggestedName});

  final List<MealItem> items;
  final String? suggestedName;
  final void Function([void]) close;

  @override
  ConsumerState<_SaveMealSheet> createState() => _SaveMealSheetState();
}

class _SaveMealSheetState extends ConsumerState<_SaveMealSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.suggestedName ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kcal = widget.items.fold(0.0, (a, i) => a + i.kcal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Save this meal')),
        Text(t('Give it a name and it is one tap next time.'),
            style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 12),
        AppTextField(controller: _name, placeholder: t('Name')),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in widget.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text(mealItemName(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(TypeScale.cap, color: c.label2)),
                    ),
                    Text('${i.kcal.round()}', style: ts(TypeScale.cap, color: c.label3)),
                  ]),
                ),
              const SizedBox(height: 6),
              Text('${kcal.round()} ${t('kcal')}',
                  style: ts(TypeScale.foot, color: c.label, weight: FontWeight.w600)),
            ],
          ),
        ),
        AppButton(t('Save'), variant: BtnVariant.primary, onTap: () {
          final name = _name.text.trim();
          if (name.isEmpty) {
            ref.read(uiProvider).toast(t('Give it a name'));
            return;
          }
          ref.read(appStateProvider.notifier).update((st) {
            st.nutrition.templates.add(MealTemplate(
              id: 'mt${uid()}',
              n: name,
              items: [for (final i in widget.items) i.copy()],
              used: 0,
              last: DateTime.now().millisecondsSinceEpoch,
            ));
          });
          widget.close();
          ref.read(uiProvider).toast(t('Saved {0}', name));
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Repeat a day you have already logged.
///
/// Most days are a variation on a day you have already had, and re-entering one food at a time
/// is the friction that ends food logs.
Future<void> copyDaySheet(WidgetRef ref, {required String to}) =>
    showSheet<void>((context, close) => _CopyDaySheet(to: to, close: close));

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
Future<void> logMealSheet(WidgetRef ref, {required String iso, double? slot, String? title}) =>
    showSheet<void>((context, close) =>
        _LogMealSheet(iso: iso, slot: slot, title: title, close: close));

class _LogMealSheet extends ConsumerStatefulWidget {
  const _LogMealSheet({required this.iso, required this.close, this.slot, this.title});

  final String iso;
  final double? slot;
  final String? title;
  final void Function([void]) close;

  @override
  ConsumerState<_LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends ConsumerState<_LogMealSheet> {
  String _query = '';
  String? _cat;

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
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (recent.isNotEmpty) ...[
                SecHeading(t('Recent')),
                for (final f in recent) _FoodRow(food: f, iso: widget.iso, slot: widget.slot),
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
                for (final f in list) _FoodRow(food: f, iso: widget.iso, slot: widget.slot),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: AppButton(t('Quick add'), icon: 'bolt', onTap: () {
              widget.close();
              quickAddSheet(ref, iso: widget.iso, slot: widget.slot);
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(t('Your own food'), icon: 'plus', onTap: () {
              widget.close();
              customFoodSheet(iso: widget.iso, slot: widget.slot);
            }),
          ),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.iso, required this.slot});

  final Food food;
  final String iso;
  final double? slot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListItem(
        leading: FoodThumb(food: food, size: 44),
        onTap: () => foodDetailSheet(food, iso: iso, slot: slot),
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
                  onChanged: (v) => _kcal = v,
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
                  onChanged: (v) => _p = v,
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

/// A food the catalogue does not carry.
Future<void> customFoodSheet({String? iso, double? slot}) =>
    showSheet<void>((context, close) => _CustomFoodSheet(iso: iso, slot: slot, close: close));

class _CustomFoodSheet extends ConsumerStatefulWidget {
  const _CustomFoodSheet({required this.close, this.iso, this.slot});

  final String? iso;
  final double? slot;
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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Your own food')),
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
              (t('Calories'), _kcal, (double? v) => _kcal = v, t('kcal'), 900.0),
              (t('Protein'), _p, (double? v) => _p = v, t('g'), 100.0),
              (t('Carbs'), _c, (double? v) => _c = v, t('g'), 100.0),
              (t('Fat'), _f, (double? v) => _f = v, t('g'), 100.0),
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
          const SizedBox(height: 6),
          AppButton(t('Save food'), variant: BtnVariant.primary, onTap: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              ref.read(uiProvider).toast(t('Give it a name'));
              return;
            }
            if ((_kcal ?? 0) <= 0) {
              ref.read(uiProvider).toast(t('Enter the calories per 100 g'));
              return;
            }
            final food = CustomFood(
              id: 'cf${uid()}',
              n: name,
              cat: _cat,
              kcal: _kcal ?? 0,
              p: _p ?? 0,
              c: _c ?? 0,
              f: _f ?? 0,
            );
            ref.read(appStateProvider.notifier)
                .update((st) => st.nutrition.foods.add(food.copy()));
            widget.close();
            // Straight on to the portion, because adding a food is almost never the actual
            // goal — logging what you just ate is.
            if (widget.iso != null) {
              foodDetailSheet(Food.fromCustom(food), iso: widget.iso, slot: widget.slot);
            }
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
