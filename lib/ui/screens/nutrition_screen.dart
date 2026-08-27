import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_state.dart';
import '../../domain/coaching.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../sheets/day_plan_sheet.dart';
import '../sheets/meal_photo_sheet.dart';
import '../sheets/nutrition_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
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

  /// Day is the default; the week is a second lens, not a replacement. The daily number is
  /// what you act on at dinner; the weekly one is what actually determines the outcome.
  bool _weekly = false;

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
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Segmented<bool>(
              value: _weekly,
              options: [SegOption(false, label: t('Day')), SegOption(true, label: t('Week'))],
              onChanged: (v) => setState(() => _weekly = v),
            ),
          ),
          _focusCard(context, s),
          _adjustmentCard(context, s),
          if (_weekly) _weekCard2(context, s) else _todayCard(context, s),
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
                    Pressable(
                      scale: 1,
                      onTap: () => targetBreakdownSheet(iso: _iso),
                      child: Row(children: [
                        Expanded(
                          child: Text(t('Target'), style: ts(TypeScale.foot, color: c.label2)),
                        ),
                        Text('${target.kcal.round()}',
                            style: ts(TypeScale.body,
                                color: c.label, weight: FontWeight.w600)),
                        const SizedBox(width: 3),
                        AppIcon('info', size: 12, color: c.label3),
                      ]),
                    ),
                    const SizedBox(height: 6),
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

  /// One thing to work on, and the number that says so.
  ///
  /// Never a list. Someone told to fix five things fixes none of them, and the ordering here
  /// is the actual hierarchy: you cannot hit a target you are not measuring, protein is what
  /// protects lean mass in a deficit, and total calories decide the direction.
  Widget _focusCard(BuildContext context, AppState s) {
    final c = context.c;
    final f = focusOf(s);

    final (icon, title, body) = switch (f.what) {
      NutritionFocus.logConsistently => (
          'clipboard',
          t('Log what you eat'),
          t('{0} of the last 14 days so far. Nothing else here means much until there are about seven — an unlogged day reads as a day you did not eat.', f.loggedDays),
        ),
      NutritionFocus.hitProtein => (
          'fish',
          t('Get your protein in'),
          t('You hit it on {0}% of logged days. It is the one macro worth chasing — in a deficit it is what keeps the weight you lose from being muscle.', (f.proteinRate * 100).round()),
        ),
      NutritionFocus.hitCalories => (
          'target',
          t('Close in on your calories'),
          t('Protein is handled. You land near your calorie target on {0}% of days — that is the number that decides which direction the scale moves.', (f.kcalRate * 100).round()),
        ),
      NutritionFocus.refine => (
          'checkCircle',
          t('This is working'),
          t('Protein and calories are both landing. Keep going, and let Stats tell you whether the scale agrees.'),
        ),
    };

    return AppCard(
      borderColor: f.what == NutritionFocus.refine ? null : c.accLine,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, size: 20, color: c.acc),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: ts(TypeScale.cap, color: c.label2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A target change the scale is asking for — offered, never applied.
  Widget _adjustmentCard(BuildContext context, AppState s) {
    final c = context.c;
    final a = suggestedAdjustment(s);
    if (a == null) return const SizedBox.shrink();

    return AppCard(
      borderColor: c.sys.orange.withValues(alpha: .5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            AppIcon('chartLine', size: 18, color: c.sys.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t('Your target may be off'),
                  style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${a.reason} ${a.delta < 0 ? t('Dropping the target by {0} would match what is actually happening.', a.delta.abs().round()) : t('There is room for {0} more a day.', a.delta.round())}',
            style: ts(TypeScale.cap, color: c.label2),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AppButton(
                t('Use {0}', '${a.kcal.round()}'),
                variant: BtnVariant.primary,
                size: BtnSize.sm,
                onTap: () {
                  ref.read(appStateProvider.notifier).update((st) {
                    st.nutrition.goal.kcal = a.kcal;
                    st.nutrition.dismissedAdj = null;
                  });
                  ref.read(uiProvider).toast(t('Target set to {0}', '${a.kcal.round()}'));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                t('Not now'),
                size: BtnSize.sm,
                onTap: () => ref.read(appStateProvider.notifier).update((st) =>
                    st.nutrition.dismissedAdj = DateTime.now().millisecondsSinceEpoch),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// The week as a budget with a running balance.
  ///
  /// The teaching is in `perDayLeft`: under on Tuesday buys you Saturday, and that is both how
  /// the physiology works and the only version of this anyone sustains.
  Widget _weekCard2(BuildContext context, AppState s) {
    final c = context.c;
    final b = weekBudget(s, _iso);
    final eaten = _weekMacros(s);
    final target = macroTargets(s, iso: _iso);
    if (target == null) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KcalRing(
                eaten: b.spent,
                target: b.budget,
                size: 116,
                label: b.left >= 0 ? t('left') : t('over'),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _line(context, t('Budget'), '${b.budget.round()}'),
                    _line(context, t('Spent'), '${b.spent.round()}'),
                    if (b.daysLeft > 0)
                      _line(
                        context,
                        t('{0} days left', b.daysLeft),
                        '${b.perDayLeft.round()}/${t('day')}',
                        tint: b.perDayLeft < 0 ? c.sys.orange : c.acc,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(t('Eaten this week'), style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 6),
          MacroLegend(macros: eaten),
        ],
      ),
    );
  }

  Macros _weekMacros(AppState s) {
    var kcal = 0.0, p = 0.0, cb = 0.0, f = 0.0;
    for (final d in weekDays(_iso)) {
      final t = dayTotals(s, d);
      kcal += t.kcal;
      p += t.p;
      cb += t.c;
      f += t.f;
    }
    return (kcal: kcal, p: p, c: cb, f: f);
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
          // The discovery path, and honest about being off: a row that says "set this up" is
          // better than a feature nobody finds, and better than a button that does nothing.
          Consumer(
            builder: (context, ref, _) {
              final on = ref.watch(aiMealPhotoProvider).isAvailable;
              return AppRow(
                icon: 'sparkles',
                iconTint: context.c.sys.purple,
                title: on ? t('Log from a photo') : t('Set up meal photos'),
                subtitle: on
                    ? t('Photograph a plate and check what the app makes of it')
                    : t('Use your own AI provider to draft a meal from a photo'),
                accessory: RowAccessory.chevron,
                onTap: () => on
                    ? mealPhotoSheet(ref, iso: _iso)
                    : context.go('/settings/ai'),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) => AppRow(
              icon: 'sparkles',
              iconTint: context.c.acc,
              title: t('Plan my day'),
              subtitle: t('An example day that hits your target'),
              accessory: RowAccessory.chevron,
              onTap: () => dayPlanSheet(ref, iso: _iso),
            ),
          ),
          Consumer(
            builder: (context, ref, _) => AppRow(
              icon: 'meal',
              iconTint: context.c.sys.green,
              title: t('Recipes'),
              subtitle: orderedTemplates(ref.watch(appStateProvider)).isEmpty
                  ? t('Write down what you cook, once')
                  : t('{0} saved · one tap to log',
                      orderedTemplates(ref.watch(appStateProvider)).length),
              accessory: RowAccessory.chevron,
              onTap: () => context.go('/nutrition/recipes'),
            ),
          ),
          Consumer(
            builder: (context, ref, _) => AppRow(
              icon: 'history',
              iconTint: context.c.sys.indigo,
              title: t('Copy a day'),
              subtitle: t('Most days are a version of one you have already had'),
              accessory: RowAccessory.chevron,
              onTap: () => copyDaySheet(ref, to: _iso),
            ),
          ),
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
              // The photo affordance sits exactly where the user already taps to log this meal,
              // and carries the slot with it. Absent — not disabled — when the feature is off,
              // so a build with no key looks like the app always did.
              if (ref.watch(aiMealPhotoProvider).isAvailable) ...[
                Pressable(
                  onTap: () => mealPhotoSheet(ref, iso: iso, slot: slot),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AppIcon('sparkles', size: 15, color: c.label3),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              AppIcon('plus', size: 15, color: c.label3),
            ],
          ),
          if (m == null || m.items.isEmpty) ...[
            // An empty slot is where a saved meal is worth the most: it is the moment the user
            // would otherwise start assembling one food at a time.
            if (orderedTemplates(ref.watch(appStateProvider)).isNotEmpty) ...[
              const SizedBox(height: 9),
              ChipRow(
                padding: EdgeInsets.zero,
                children: [
                  for (final tpl in orderedTemplates(ref.watch(appStateProvider)).take(3))
                    AppChip(
                      '${t(tpl.n)} · ${tpl.kcal.round()}',
                      selected: false,
                      capitalize: false,
                      icon: 'plus',
                      onTap: () => logTemplate(ref, tpl, iso: iso, slot: slot),
                    ),
                ],
              ),
            ],
          ],
          if (m != null && m.items.isNotEmpty) ...[
            const SizedBox(height: 9),
            MacroSplit(macros: (kcal: m.kcal, p: m.p, c: m.c, f: m.f), height: 4),
            const SizedBox(height: 8),
            // The picture and the list it produced, side by side. Only when there is one — most
            // meals are logged by hand and the card has to look untouched for them.
            if (m.photo case final photo?)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MealPhoto(name: photo),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final item in m.items) _itemLine(context, ref, m, item)],
                    ),
                  ),
                ],
              )
            else
              for (final item in m.items) _itemLine(context, ref, m, item),
            if (_repeatCount(ref.watch(appStateProvider), m) case final n? when n >= 3) ...[
              const SizedBox(height: 6),
              Pressable(
                scale: 1,
                // The slot goes across untranslated: it is stored and matched on, while the
                // name is only ever read.
                onTap: () => saveMealSheet(ref, m.items, suggestedName: t(name), slot: name),
                child: Row(children: [
                  AppIcon('star', size: 12, color: c.acc),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      t('Logged this {0} times — save it?', n),
                      style: ts(TypeScale.cap, color: c.acc),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _itemLine(BuildContext context, WidgetRef ref, Meal m, MealItem item) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              mealItemLabel(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(TypeScale.cap, color: c.label2),
            ),
          ),
          Text('${item.kcal.round()}', style: ts(TypeScale.cap, color: c.label3)),
          const SizedBox(width: 6),
          Pressable(
            scale: .9,
            onTap: () => _remove(ref, m, item),
            child: AppIcon('xmark', size: 12, color: c.label4),
          ),
        ],
      ),
    );
  }

  /// How many times this exact meal has been logged, if it is worth offering to save.
  ///
  /// Null once it is saved, so the offer disappears the moment it is taken rather than
  /// continuing to ask for something the user has already done.
  int? _repeatCount(AppState s, Meal m) {
    final sig = signatureOf(m.items);
    for (final r in repeatedMeals(s)) {
      if (r.signature == sig) return r.count;
    }
    return null;
  }

  void _remove(WidgetRef ref, Meal m, MealItem item) {
    ref.read(appStateProvider.notifier).update((st) {
      final meal = st.meals.where((x) => x.id == m.id).firstOrNull;
      if (meal == null) return;
      final i = meal.items.indexWhere((x) =>
          x.fid == item.fid && x.g == item.g && x.kcal == item.kcal && x.n == item.n);
      if (i >= 0) meal.items.removeAt(i);
      // An empty meal is not a meal. Its photograph goes with it — not here, but at the next boot
      // sweep, which is where every "this file has nothing pointing at it" decision is made.
      if (meal.items.isEmpty) st.meals.removeWhere((x) => x.id == meal.id);
    });
  }
}

/// The photograph a meal was drafted from, if it is still on the phone.
///
/// Every branch here except one renders nothing at all, and that is the normal case rather than an
/// error path: the file is not in a backup, it is deleted after 90 days, and the user can switch
/// keeping them off entirely. A meal whose picture has gone is a meal, and the card is complete
/// without it — so an absent photo collapses silently instead of leaving a placeholder behind.
class _MealPhoto extends ConsumerWidget {
  const _MealPhoto({required this.name});

  final String name;

  static const _size = 46.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(mealPhotoProvider(name)).value;
    if (bytes == null) return const SizedBox.shrink();
    // The gap belongs to the picture, so a meal whose file has gone leaves the list flush against
    // the card edge exactly as an unphotographed one does.
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.memory(
          bytes,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          // Image.memory throws asynchronously on bytes it cannot decode, and an uncaught throw
          // out of the image service takes the whole day view down — over a thumbnail. FoodThumb
          // sets the same precedent.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
