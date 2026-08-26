import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_plan.dart';
import '../../domain/foods.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
import 'nutrition_sheets.dart';
import 'sheet_service.dart';

/// A day the app would eat, offered as an example.
///
/// Each meal logs on its own, when it is actually eaten. There is no "use this whole day"
/// button and that is deliberate: the food log is a record of what happened, and a plan
/// written into it wholesale would quietly corrupt the one comparison — predicted weight change
/// against real weight change — that tells the user how much to trust any of this.
Future<void> dayPlanSheet(WidgetRef ref, {required String iso}) =>
    showSheet<void>((context, close) => _DayPlanSheet(iso: iso));

class _DayPlanSheet extends ConsumerStatefulWidget {
  const _DayPlanSheet({required this.iso});

  final String iso;

  @override
  ConsumerState<_DayPlanSheet> createState() => _DayPlanSheetState();
}

class _DayPlanSheetState extends ConsumerState<_DayPlanSheet> {
  int _seed = 0;
  final _logged = <double>{};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final plan = buildDayPlan(s, widget.iso, seed: _seed);
    final target = macroTargets(s, iso: widget.iso);

    if (plan.isEmpty || target == null) {
      return EmptyState(
        icon: 'meal',
        message: t('Nothing to plan yet'),
        detail: t('Set your details and a goal first.'),
      );
    }

    final totals = dayPlanTotals(plan);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('A day that fits')),
          Text(
            t('Built from food you already eat. Log each meal when you have it — nothing is recorded until you do.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(t('This day comes to'),
                        style: ts(TypeScale.foot, color: c.label2)),
                  ),
                  Text(
                    '${totals.kcal.round()} / ${target.kcal.round()} ${t('kcal')}',
                    style: ts(TypeScale.foot, color: c.label, weight: FontWeight.w600),
                  ),
                ]),
                const SizedBox(height: 10),
                MacroSplit(macros: totals),
                const SizedBox(height: 8),
                MacroLegend(macros: totals),
              ],
            ),
          ),
          for (final meal in plan) _meal(context, meal),
          const SizedBox(height: 6),
          AppButton(
            t('Show me another'),
            icon: 'shuffle',
            onTap: () => setState(() {
              _seed++;
              // A reshuffled day is a different day; what was logged from the old one stays
              // logged, but the buttons should not claim the new meals are done.
              _logged.clear();
            }),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _meal(BuildContext context, PlannedMeal meal) {
    final c = context.c;
    final done = _logged.contains(meal.slot);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(t(meal.name),
                  style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
            ),
            Text('${meal.macros.kcal.round()} ${t('kcal')}',
                style: ts(TypeScale.foot, color: c.label2)),
          ]),
          const SizedBox(height: 10),
          for (final item in meal.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                FoodThumb(food: foods.or(item.fid ?? ''), size: 34),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    mealItemLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(TypeScale.foot, color: c.label),
                  ),
                ),
                Text('${item.kcal.round()}', style: ts(TypeScale.cap, color: c.label3)),
              ]),
            ),
          const SizedBox(height: 4),
          AppButton(
            done ? t('Logged') : t('Log this meal'),
            variant: done ? BtnVariant.tinted : BtnVariant.plain,
            size: BtnSize.sm,
            icon: done ? 'check' : 'plus',
            enabled: !done,
            onTap: () {
              for (final item in meal.items) {
                addMealItem(ref, iso: widget.iso, slot: meal.slot, item: item);
              }
              setState(() => _logged.add(meal.slot));
              ref.read(uiProvider).toast(t('Logged {0}', t(meal.name)));
            },
          ),
        ],
      ),
    );
  }
}
