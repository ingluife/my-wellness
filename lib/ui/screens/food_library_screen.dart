import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/foods.dart';
import '../../domain/format.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../sheets/nutrition_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// The food catalogue, browsable by category and sortable by protein density.
///
/// The density sort is the reason this screen is worth having rather than just a search box in
/// a sheet: "what should I be eating more of" is a real question, and per-100 g protein answers
/// it wrongly. Parmesan carries more protein per 100 g than chicken breast and three times the
/// calories with it.
class FoodLibraryScreen extends ConsumerStatefulWidget {
  const FoodLibraryScreen({super.key});

  @override
  ConsumerState<FoodLibraryScreen> createState() => _FoodLibraryScreenState();
}

class _FoodLibraryScreenState extends ConsumerState<FoodLibraryScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _cat = '';
  String _sort = 'density';
  int _shown = 40;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    var list = foods.search(s, _q);
    if (_cat.isNotEmpty) list = [for (final f in list) if (f.cat == _cat) f];
    list = [...list];
    switch (_sort) {
      case 'density':
        list.sort((a, b) => b.proteinDensity.compareTo(a.proteinDensity));
      case 'protein':
        list.sort((a, b) => b.p.compareTo(a.p));
      case 'kcal':
        list.sort((a, b) => a.kcal.compareTo(b.kcal));
    }

    final shown = list.take(_shown).toList();

    return AppPage(
      children: [
        PageHeader(
          title: t('Foods'),
          subtitle: t('{0} foods', list.length),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/nutrition')),
        ),
        SearchField(
          value: _q,
          controller: _search,
          placeholder: t('Search foods'),
          onChanged: (v) => setState(() {
            _q = v;
            _shown = 40;
          }),
        ),
        const SizedBox(height: 10),
        ChipRow(children: [
          AppChip(t('All'),
              selected: _cat.isEmpty,
              onTap: () => setState(() {
                    _cat = '';
                    _shown = 40;
                  })),
          for (final cat in foodCategories)
            AppChip(
              t(foodCategoryName[cat] ?? cat),
              icon: foodCategoryGlyph[cat],
              selected: _cat == cat,
              onTap: () => setState(() {
                _cat = _cat == cat ? '' : cat;
                _shown = 40;
              }),
            ),
        ]),
        const SizedBox(height: 10),
        Segmented<String>(
          value: _sort,
          options: [
            SegOption('density', label: t('Protein / kcal')),
            SegOption('protein', label: t('Protein')),
            SegOption('kcal', label: t('Lightest')),
          ],
          onChanged: (v) => setState(() => _sort = v),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          EmptyState(
            icon: 'magnifier',
            message: t('No foods match'),
            detail: t('Try another word, or add one of your own.'),
          )
        else
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListItem(
                leading: FoodThumb(food: f),
                onTap: () => foodDetailSheet(f, iso: todayISO(), slot: null),
                trailing: [
                  if (_sort == 'density' && f.p > 0)
                    Tag(fmtNum(f.proteinDensity),
                        accent: f.proteinDensity >= 10, capitalize: false),
                ],
                child: ItemText(
                  t(f.n),
                  subtitle: '${f.kcal.round()} ${t('kcal')} · '
                      '${fmtNum(f.p)}P ${fmtNum(f.c)}C ${fmtNum(f.f)}F',
                ),
              ),
            ),
        if (shown.length < list.length) ...[
          const SizedBox(height: 6),
          AppButton(t('Show more'), onTap: () => setState(() => _shown += 40)),
        ],
        const SizedBox(height: 8),
        Text(
          t('Per 100 g. Numbers from USDA FoodData Central.'),
          textAlign: TextAlign.center,
          style: ts(TypeScale.cap, color: c.label3),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
