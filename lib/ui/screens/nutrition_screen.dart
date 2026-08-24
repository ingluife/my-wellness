import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/foods.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../sheets/nutrition_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/page.dart';

/// What to eat today, and what you have eaten so far.
///
/// The counterpart to Home: that screen answers "am I training today", this one answers "what
/// am I eating for it". They are deliberately separate screens rather than one long feed —
/// logging a meal happens four times a day and should not require scrolling past a week strip.
class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  String _iso = todayISO();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final ready = s.nutrition.profile.isComplete && bodyKg(s) != null;

    return AppPage(
      children: [
        PageHeader(
          title: t('Nutrition'),
          subtitle: DateFormat('EEEE, d MMMM', dateLocale).format(dayOf(_iso)),
          trailing: IconButtonRound('gear', onTap: nutritionGoalSheet),
        ),
        if (!ready)
          _setupCard(context, s)
        else ...[
          _todayCard(context, s),
          _weekCard(context, s),
          _mealsCard(context, s),
          _sourcesCard(context),
        ],
      ],
    );
  }

  /// Nothing can be estimated without a profile, so the screen asks for one rather than
  /// showing a grid of dashes.
  Widget _setupCard(BuildContext context, AppState s) {
    final c = context.c;
    final noWeight = bodyKg(s) == null;
    return AppCard(
      borderColor: c.accLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            AppIcon('meal', size: 22, color: c.acc),
            const SizedBox(width: 8),
            Text(t('Set this up once'),
                style: ts(TypeScale.head, color: c.label, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(
            noWeight
                ? t('Weigh in first — every number here is worked out from your body weight.')
                : t('Your age, height and sex are all it takes to work out what you burn, and your plan does the rest.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 14),
          AppButton(
            noWeight ? t('Weigh in') : t('About you'),
            variant: BtnVariant.primary,
            onTap: noWeight ? () => context.go('/home') : bodyProfileSheet,
          ),
        ],
      ),
    );
  }

  Widget _todayCard(BuildContext context, AppState s) {
    final c = context.c;
    final target = macroTargets(s, iso: _iso);
    final eaten = dayTotals(s, _iso);
    final burn = plannedBurn(s, _iso);
    if (target == null) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KcalRing(eaten: eaten.kcal, target: target.kcal, size: 116),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _line(context, t('Target'), '${target.kcal.round()}'),
                    _line(context, t('Eaten'), '${eaten.kcal.round()}'),
                    if (burn > 0)
                      _line(context, t('Training'), '+${burn.round()}', tint: c.sys.orange),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MacroBars(eaten: eaten, target: target),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value, {Color? tint}) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ts(TypeScale.foot, color: c.label2))),
          Text(value,
              style: ts(TypeScale.body, color: tint ?? c.label, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// The week, with each day's target and whether it is a training day.
  ///
  /// The point of the strip is the link the whole feature rests on: the days you train are the
  /// days you get more food, and that comes straight from the plan already set in Plan.
  Widget _weekCard(BuildContext context, AppState s) {
    final c = context.c;
    final days = weekDays(_iso);
    final today = todayISO();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('This week'), style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final iso in days)
                Expanded(
                  child: _WeekDay(
                    iso: iso,
                    selected: iso == _iso,
                    isToday: iso == today,
                    training: effectiveRoutine(s, iso) != null,
                    kcal: macroTargets(s, iso: iso)?.kcal,
                    logged: mealsOn(s, iso).isNotEmpty,
                    onTap: () => setState(() => _iso = iso),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The day, split into its meals.
  Widget _mealsCard(BuildContext context, AppState s) {
    final target = macroTargets(s, iso: _iso);
    final split = mealSplit(s.nutrition.goal);
    final meals = mealsOn(s, _iso);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecHeading(t('Meals')),
        for (var i = 0; i < split.length; i++)
          _MealSlot(
            name: split[i].$1,
            share: split[i].$2,
            slot: i.toDouble(),
            iso: _iso,
            targetKcal: (target?.kcal ?? 0) * split[i].$2,
            meal: meals.where((m) => m.slot == i).firstOrNull,
          ),
        // Anything logged without a slot — added before the meal count changed, or imported.
        for (final m in meals.where((m) => m.slot == null || m.slot! >= split.length))
          _MealSlot(
            name: t('Other'),
            share: 0,
            slot: m.slot,
            iso: _iso,
            targetKcal: 0,
            meal: m,
          ),
      ],
    );
  }

  Widget _sourcesCard(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Section(children: [
          AppRow(
            icon: 'fish',
            title: t('Protein sources'),
            subtitle: t('Ranked by protein per calorie'),
            accessory: RowAccessory.chevron,
            onTap: () => context.go('/nutrition/foods'),
          ),
          AppRow(
            icon: 'person',
            title: t('About you'),
            subtitle: t('Age, height, activity'),
            accessory: RowAccessory.chevron,
            onTap: bodyProfileSheet,
          ),
        ]),
      );
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.iso,
    required this.selected,
    required this.isToday,
    required this.training,
    required this.kcal,
    required this.logged,
    required this.onTap,
  });

  final String iso;
  final bool selected;
  final bool isToday;
  final bool training;
  final double? kcal;
  final bool logged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = dayOf(iso);
    return Pressable(
      scale: 1,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.accSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
          border: isToday && !selected ? Border.all(color: c.sep) : null,
        ),
        child: Column(
          children: [
            Text(
              DateFormat.E(dateLocale).format(d).substring(0, 1).toUpperCase(),
              style: ts(TypeScale.cap,
                  color: selected ? c.acc : c.label3, weight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            // A dot for a training day, a hollow ring for a rest day: the strip has to be
            // readable at a glance and there is no room for a word.
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: training ? c.acc : Colors.transparent,
                border: training ? null : Border.all(color: c.label4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Thousands, to one decimal: "2.4k". A seventh of the screen width has room for
              // four glyphs, and the exact calorie count of next Thursday is not a number
              // anyone needs to read off a strip.
              kcal == null ? '–' : '${(kcal! / 100).round() / 10}k',
              style: ts(TypeScale.cap,
                  size: 9, color: logged ? c.label2 : c.label4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSlot extends ConsumerWidget {
  const _MealSlot({
    required this.name,
    required this.share,
    required this.slot,
    required this.iso,
    required this.targetKcal,
    required this.meal,
  });

  final String name;
  final double share;
  final double? slot;
  final String iso;
  final double targetKcal;
  final Meal? meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final m = meal;
    final eaten = m?.kcal ?? 0;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      onTap: () => logMealSheet(ref, iso: iso, slot: slot, title: t(name)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t(name),
                    style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
              ),
              Text(
                targetKcal > 0
                    ? '${eaten.round()} / ${targetKcal.round()}'
                    : '${eaten.round()}',
                style: ts(TypeScale.foot, color: c.label2),
              ),
              const SizedBox(width: 6),
              AppIcon('plus', size: 15, color: c.label3),
            ],
          ),
          if (m != null && m.items.isNotEmpty) ...[
            const SizedBox(height: 9),
            MacroSplit(macros: (kcal: m.kcal, p: m.p, c: m.c, f: m.f), height: 4),
            const SizedBox(height: 8),
            for (final item in m.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_itemName(item)} · ${item.g.round()} g',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(TypeScale.cap, color: c.label2),
                      ),
                    ),
                    Text('${item.kcal.round()}',
                        style: ts(TypeScale.cap, color: c.label3)),
                    const SizedBox(width: 6),
                    Pressable(
                      scale: .9,
                      onTap: () => _remove(ref, m, item),
                      child: AppIcon('xmark', size: 12, color: c.label4),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _itemName(MealItem item) =>
      item.n ?? (item.fid == null ? t('Food') : t(foods.or(item.fid!).n));

  void _remove(WidgetRef ref, Meal m, MealItem item) {
    ref.read(appStateProvider.notifier).update((st) {
      final meal = st.meals.where((x) => x.id == m.id).firstOrNull;
      if (meal == null) return;
      final i = meal.items.indexWhere((x) =>
          x.fid == item.fid && x.g == item.g && x.kcal == item.kcal && x.n == item.n);
      if (i >= 0) meal.items.removeAt(i);
      // An empty meal is not a meal.
      if (meal.items.isEmpty) st.meals.removeWhere((x) => x.id == meal.id);
    });
  }
}
