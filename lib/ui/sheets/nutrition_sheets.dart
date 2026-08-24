import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/foods.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../../ui/app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/page.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/select_row.dart';
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

class _BodyProfileSheetState extends ConsumerState<_BodyProfileSheet> {
  double? _age;
  double? _height;
  String? _sex;
  String? _activity;
  bool _seeded = false;

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
            trailing: SizedBox(
              width: 76,
              child: NumberField(
                value: _age,
                decimal: false,
                nullable: true,
                onChanged: (v) => _age = v,
              ),
            ),
          ),
          AppRow(
            title: t('Height'),
            subtitle: t('centimetres'),
            trailing: SizedBox(
              width: 76,
              child: NumberField(
                value: _height,
                decimal: false,
                nullable: true,
                onChanged: (v) => _height = v,
              ),
            ),
          ),
          AppRow(
            title: t('Sex'),
            subtitle: t('Changes the resting-rate formula only'),
            trailing: Segmented<String>(
              inline: true,
              value: _sex ?? 'male',
              options: [
                SegOption('male', label: t('Male')),
                SegOption('female', label: t('Female')),
              ],
              onChanged: (v) => setState(() => _sex = v),
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
          final age = _age;
          final height = _height;
          if (age == null || age < 13 || age > 100) {
            ref.read(uiProvider).toast(t('Enter an age between 13 and 100'));
            return;
          }
          if (height == null || height < 120 || height > 230) {
            ref.read(uiProvider).toast(t('Enter a height between 120 and 230 cm'));
            return;
          }
          ref.read(appStateProvider.notifier).update((st) {
            st.nutrition.profile
              ..age = age
              ..height = height
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
                  width: 76,
                  child: NumberField(
                    value: _rate,
                    onChanged: (v) => setState(() => _rate = v ?? 0),
                  ),
                ),
              ),
            ],
          ),
        ],
        Section(
          title: t('Meals'),
          footer: t('Only decides how the day is split up. What you eat in total is what moves the scale.'),
          children: [
            AppRow(
              title: t('Meals per day'),
              trailing: Segmented<double>(
                inline: true,
                value: (_meals ?? 4).clamp(2, 6),
                options: [for (var i = 2; i <= 6; i++) SegOption(i.toDouble(), label: '$i')],
                onChanged: (v) => setState(() => _meals = v),
              ),
            ),
          ],
        ),
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

/// One food: what it is, and how much of it you had.
Future<void> foodDetailSheet(Food food, {String? iso, double? slot}) =>
    showSheet<void>((context, close) =>
        _FoodDetailSheet(food: food, iso: iso, slot: slot, close: close));

class _FoodDetailSheet extends ConsumerStatefulWidget {
  const _FoodDetailSheet({
    required this.food,
    required this.close,
    this.iso,
    this.slot,
  });

  final Food food;
  final String? iso;
  final double? slot;
  final void Function([void]) close;

  @override
  ConsumerState<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<_FoodDetailSheet> {
  double _grams = 100;

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
          Row(
            children: [
              Tag(t(foodCategoryName[f.cat] ?? f.cat), icon: foodCategoryGlyph[f.cat]),
              const SizedBox(width: 6),
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
                  width: 88,
                  child: NumberField(
                    value: _grams,
                    decimal: false,
                    onChanged: (v) => setState(() => _grams = v ?? 0),
                  ),
                ),
              ),
            ],
          ),
          ChipRow(children: [
            for (final g in const [50.0, 100.0, 150.0, 200.0, 250.0])
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
              ],
            ),
          ),
          if (widget.iso != null) ...[
            AppButton(t('Add to the day'), variant: BtnVariant.primary, onTap: () {
              if (_grams <= 0) {
                ref.read(uiProvider).toast(t('Enter a portion first'));
                return;
              }
              addMealItem(ref, iso: widget.iso!, slot: widget.slot, item: item);
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
        AppButton(t('Add your own food'), icon: 'plus', onTap: () {
          widget.close();
          customFoodSheet(iso: widget.iso, slot: widget.slot);
        }),
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
            for (final row in [
              (t('Calories'), _kcal, (double? v) => _kcal = v),
              (t('Protein'), _p, (double? v) => _p = v),
              (t('Carbs'), _c, (double? v) => _c = v),
              (t('Fat'), _f, (double? v) => _f = v),
            ])
              AppRow(
                title: row.$1,
                trailing: SizedBox(
                  width: 80,
                  child: NumberField(value: row.$2, nullable: true, onChanged: row.$3),
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
