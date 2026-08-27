import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../sheets/nutrition_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/page.dart';

/// The user's own recipes: what they actually cook, written down once.
///
/// The storage for these has existed since the food log did, but there was no way to reach it.
/// A recipe could only come into being by logging the identical meal three times and accepting
/// an offer on the day screen, and once saved it could never be renamed, corrected or thrown
/// away — it surfaced as one of at most three chips on an empty slot and nowhere else.
///
/// That gap mattered more than it looks. A bundled catalogue of dishes can only ever guess at
/// what somebody eats; this is the same question answered by the person who eats it, in their
/// own words and their own language. It is what makes the day plan theirs rather than a
/// nutritionally correct list of ingredients.
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _slot = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    // Frequency then recency, the order `orderedTemplates` already argues for: a breakfast
    // eaten every weekday should outrank the dinner you happened to have last night.
    var list = orderedTemplates(s);
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = [
        for (final r in list)
          if (r.n.toLowerCase().contains(q) ||
              r.items.any((i) => mealItemName(i).toLowerCase().contains(q)))
            r
      ];
    }
    if (_slot.isNotEmpty) list = [for (final r in list) if (r.slot == _slot) r];

    return AppPage(
      children: [
        PageHeader(
          title: t('Recipes'),
          subtitle: t('{0} saved', list.length),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/nutrition')),
        ),
        AppButton(
          t('New recipe'),
          icon: 'plus',
          variant: BtnVariant.primary,
          onTap: () => recipeSheet(ref),
        ),
        const SizedBox(height: 12),
        if (s.nutrition.templates.isNotEmpty) ...[
          SearchField(
            value: _q,
            controller: _search,
            placeholder: t('Search recipes'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 10),
          ChipRow(children: [
            AppChip(t('All'), selected: _slot.isEmpty, onTap: () => setState(() => _slot = '')),
            for (final slot in recipeSlots)
              AppChip(
                t(slot),
                selected: _slot == slot,
                onTap: () => setState(() => _slot = _slot == slot ? '' : slot),
              ),
          ]),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty)
          EmptyState(
            icon: 'meal',
            message: s.nutrition.templates.isEmpty
                ? t('No recipes yet')
                : t('No recipes match'),
            detail: s.nutrition.templates.isEmpty
                ? t('Save the meals you cook and the day plan will start suggesting them back.')
                : t('Try another word.'),
          )
        else
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecipeCard(recipe: r),
            ),
        const SizedBox(height: 8),
        Text(
          t('A recipe is yours: nothing here is shared, and nothing is logged until you log it.'),
          textAlign: TextAlign.center,
          style: ts(TypeScale.cap, color: c.label3),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _RecipeCard extends ConsumerWidget {
  const _RecipeCard({required this.recipe});

  final MealTemplate recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final macros = (kcal: recipe.kcal, p: recipe.p, c: recipe.c, f: recipe.f);

    return AppCard(
      onTap: () => recipeSheet(ref, existing: recipe),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(recipe.n,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
            ),
            Text('${recipe.kcal.round()} ${t('kcal')}',
                style: ts(TypeScale.foot, color: c.label2)),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (recipe.slot case final slot?) Tag(t(slot), icon: 'meal'),
              if (recipe.servings != null && recipe.perServing > 1)
                Tag(t('Makes {0}', recipe.perServing.round()), capitalize: false),
              if ((recipe.used ?? 0) > 0)
                Tag(t('Logged {0}x', (recipe.used ?? 0).round()), capitalize: false),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            // The ingredients, in the order they were added. This is what tells one recipe from
            // another at a glance far better than the name does — two of yours will be called
            // something like "lunch".
            [for (final i in recipe.items) mealItemName(i)].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ts(TypeScale.cap, color: c.label3),
          ),
          const SizedBox(height: 9),
          MacroSplit(macros: macros, height: 4),
          const SizedBox(height: 8),
          MacroLegend(macros: macros),
        ],
      ),
    );
  }
}
