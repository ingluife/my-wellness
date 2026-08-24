import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../sheets/exercise_sheets.dart';
import '../sheets/routine_sheets.dart';
import '../theme/app_colors.dart';
import '../../state/app_state_provider.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// The exercise library: 1,324 exercises, searchable, filtered by body part and by the
/// equipment you actually own.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _bp = '';
  String _eq = '';

  /// Paged rather than lazily built: the list carries a search field, two chip rows and a
  /// "create your own" row above it, and 40 at a time is what the original shows.
  int _shown = 40;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() => _shown = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final ql = _q.toLowerCase().trim();

    final base = exdb.all(s).where((e) {
      if (_bp.isNotEmpty && e.bp != _bp) return false;
      if (ql.isEmpty) return true;
      return e.n.toLowerCase().contains(ql) ||
          e.tg.contains(ql) ||
          e.eq.contains(ql) ||
          e.desc.toLowerCase().contains(ql);
    }).toList();

    final eqOpts = exdb.equipmentOf(base);
    // Drop the equipment filter if the search narrowed it away, so you never hit a dead end.
    final eqOn = eqOpts.contains(_eq) ? _eq : '';
    final f = eqOn.isEmpty ? base : base.where((e) => e.eq == eqOn).toList();

    return AppPage(
      children: [
        PageHeader(
          title: t('Exercises'),
          subtitle: t('{0} exercises with animations', exdb.db.length),
        ),
        SearchField(
          controller: _search,
          value: _q,
          placeholder: t('Search…'),
          onChanged: (v) => setState(() {
            _q = v;
            _reset();
          }),
        ),
        SizedBox(height: eqOpts.length > 1 ? 8 : 12),
        ChipRow(children: [
          AppChip(t('All'),
              capitalize: false,
              selected: _bp.isEmpty,
              onTap: () => setState(() {
                    _bp = '';
                    _eq = '';
                    _reset();
                  })),
          for (final b in exdb.bodyParts)
            AppChip(t(b),
                selected: _bp == b,
                onTap: () => setState(() {
                      _bp = b;
                      _eq = '';
                      _reset();
                    })),
        ]),
        if (eqOpts.length > 1) ...[
          const SizedBox(height: 8),
          ChipRow(children: [
            AppChip(t('Any equipment'),
                capitalize: false,
                selected: eqOn.isEmpty,
                onTap: () => setState(() {
                      _eq = '';
                      _reset();
                    })),
            for (final x in eqOpts)
              AppChip(t(x),
                  selected: eqOn == x,
                  onTap: () => setState(() {
                        _eq = x;
                        _reset();
                      })),
          ]),
        ],
        const SizedBox(height: 12),
        AppList(children: [
          ListItem(
            leading: Container(
              width: 50,
              height: 50,
              decoration:
                  BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: AppIcon('sparkles', size: 21, color: c.label2),
            ),
            trailing: [AppIcon('plus', size: 15, color: c.label, stroke: 2.4)],
            onTap: () => customExSheet(prefill: _q.trim(), onDone: exerciseDetailSheet),
            child: ItemText(t('Create your own exercise'),
                subtitle: t('name + body part, no animation')),
          ),
          for (final e in f.take(_shown)) _row(context, s.unit, e),
          if (f.isEmpty) EmptyState(icon: 'magnifier', message: t('No match')),
        ]),
        if (f.length > _shown) ...[
          const SizedBox(height: 10),
          AppButton(t('Show more'), onTap: () => setState(() => _shown += 40)),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String unit, Exercise e) {
    final s = ref.read(appStateProvider);
    final best = bestWeightFor(s, e.id);
    return ListItem(
      leading: ExerciseThumb(ex: e),
      onTap: () => exerciseDetailSheet(e),
      trailing: [
        if (best > 0) Tag(fmtNum(best), accent: true, capitalize: false),
        AppButton(t('Plan'),
            size: BtnSize.sm,
            variant: BtnVariant.tinted,
            icon: 'plus',
            onTap: () => addToRoutineSheet(e)),
      ],
      child: ItemText(
        e.n,
        capitalize: true,
        subtitle: '${t(e.tg.isNotEmpty ? e.tg : e.bp)} · ${t(e.eq)}',
      ),
    );
  }
}
