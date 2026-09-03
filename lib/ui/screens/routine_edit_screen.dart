import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/muscles.dart';
import '../../domain/plan_share.dart';
import '../../domain/progression.dart';
import '../../platform/backup.dart';
import '../../state/app_state_provider.dart';
import '../sheets/exercise_sheets.dart';
import '../sheets/plan_sheets.dart';
import '../sheets/routine_sheets.dart';
import '../sheets/sheet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/body_map.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// Build one routine: name it, give it an icon, order its exercises, link supersets, and see
/// what the session actually hits while you are still building it.
class RoutineEditScreen extends ConsumerStatefulWidget {
  const RoutineEditScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends ConsumerState<RoutineEditScreen> {
  TextEditingController? _name;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  Routine? _routine(WidgetRef ref) =>
      ref.watch(appStateProvider).routines.where((r) => r.id == widget.id).firstOrNull;

  /// Every edit reaches the exercise list of this routine and nothing else.
  void _edit(void Function(List<ExerciseConfig> ex) f) =>
      ref.read(appStateProvider.notifier).update((s) {
        final r = s.routines.where((x) => x.id == widget.id).firstOrNull;
        if (r != null) f(r.ex);
      });

  void _move(int i, int dir) => _edit((ex) {
        final j = i + dir;
        if (j < 0 || j >= ex.length) return;
        final tmp = ex[i];
        ex[i] = ex[j];
        ex[j] = tmp;
        cleanupSg(ex);
      });

  /// Link or unlink an exercise with the one above it.
  void _toggleLink(int i) => _edit((ex) {
        if (i < 1) return;
        final cur = ex[i];
        final prev = ex[i - 1];
        if (cur.sg != null && prev.sg != null && cur.sg == prev.sg) {
          cur.sg = null;
        } else {
          final gid = prev.sg ?? 'sg${uid()}';
          prev.sg = gid;
          cur.sg = gid;
        }
        cleanupSg(ex);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final r = _routine(ref);
    // The routine can be deleted underneath this screen — from another flow, or by the delete
    // button below. Leave rather than render half of one.
    if (r == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/plan');
      });
      return const SizedBox.shrink();
    }
    _name ??= TextEditingController(text: r.name);

    final units = supersetUnits(r.ex);
    final unitFirst = {for (final u in units.where((u) => u.length > 1)) u.first};
    final inSuperset = {for (final u in units.where((u) => u.length > 1)) ...u};

    return AppPage(
      children: [
        PageHeader(
          title: r.name,
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/plan')),
          titleWidget: TextField(
            controller: _name,
            style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600),
            cursorColor: c.acc,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => ref.read(appStateProvider.notifier).update((st) {
              final target = st.routines.where((x) => x.id == widget.id).firstOrNull;
              if (target != null) target.name = v.trim().isEmpty ? t('Routine') : v.trim();
            }),
          ),
          trailing: IconButtonRound(
            glyphOf(r.emoji),
            onTap: () => glyphPicker(
              r.emoji,
              (g) => ref.read(appStateProvider.notifier).update((st) {
                final target = st.routines.where((x) => x.id == widget.id).firstOrNull;
                if (target != null) target.emoji = g;
              }),
            ),
          ),
        ),
        Section(children: [
          SelectRow<String>(
            icon: 'chartLine',
            title: t('Progression'),
            sheetTitle: t('Progression'),
            value: r.prog ?? 'linear',
            onChanged: (v) => ref.read(appStateProvider.notifier).update((st) {
              final target = st.routines.where((x) => x.id == widget.id).firstOrNull;
              if (target != null) target.prog = v;
            }),
            options: [
              for (final p in policiesFor['reps']!)
                SelectOption(p, t(policyName[p]!), subtitle: t(policyDesc[p]!)),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
          child: Text(
            t('Applies to every exercise in this routine that does not set its own rule.'),
            style: ts(TypeScale.foot, color: c.label3),
          ),
        ),
        if (r.ex.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < r.ex.length; i++) ...[
                if (unitFirst.contains(i))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 0, 5),
                    child: Row(children: [
                      AppIcon('link', size: 13, color: c.acc),
                      const SizedBox(width: 5),
                      Text(t('Superset'),
                          style: ts(TypeScale.cap, color: c.acc, weight: FontWeight.w600)),
                    ]),
                  ),
                if (i > 0 && !unitFirst.contains(i)) const SizedBox(height: 8),
                _exerciseRow(context, s.unit, r, i, inSuperset.contains(i)),
              ],
            ],
          )
        else
          EmptyState(icon: 'dumbbell', message: t('No exercises yet — add your first one.')),
        // Coverage of the routine as planned, so a gap shows up while you are building it
        // rather than after a month of training around it.
        if (r.ex.isNotEmpty) _coverage(context, s.body, r),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppIcon('link', size: 13, color: c.label3),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                t('Tap the link button on an exercise to superset it with the one above — you’ll do them back-to-back.'),
                style: ts(TypeScale.foot, color: c.label3),
              ),
            ),
          ]),
        ),
        AppButton(
          t('Add exercise'),
          variant: BtnVariant.primary,
          icon: 'plus',
          onTap: () => exercisePicker((ex) => exConfigSheet(
                ex: ex,
                routine: r,
                onSave: (cfg) => _edit((list) => list.add(cfg.copy()..id = ex.id)),
              )),
        ),
        const SizedBox(height: 10),
        // Tinted, not primary: 'Add exercise' above is already this screen's one filled slab,
        // and two stacked primaries read as two equal calls to action. The OS share sheet is
        // the only feedback needed, exactly as for the whole-plan export.
        AppButton(
          t('Share routine'),
          variant: BtnVariant.tinted,
          icon: 'upload',
          enabled: r.ex.isNotEmpty,
          onTap: () async {
            try {
              await Backup.shareJson(buildRoutineBundle(s, r), routineFileName(r));
            } catch (_) {
              // The share sheet was dismissed.
            }
          },
        ),
        const SizedBox(height: 10),
        AppButton(
          t('Delete routine'),
          variant: BtnVariant.danger,
          onTap: () => confirmSheet(
            title: t('Delete routine?'),
            message: t('“{0}” and its exercises will be removed.', r.name),
            confirmText: t('Delete'),
            danger: true,
            onConfirm: () {
              ref.read(appStateProvider.notifier).update((st) {
                st.routines.removeWhere((x) => x.id == widget.id);
                st.week.removeWhere((_, v) => v == widget.id);
                st.dayPlan.removeWhere((_, v) => v == widget.id);
              });
              if (mounted) context.go('/plan');
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _exerciseRow(BuildContext context, String unit, Routine r, int i, bool inSuperset) {
    final e = r.ex[i];
    // An unresolvable id is shown rather than skipped — hiding it left an entry you could
    // neither see nor delete, but that still turned up in the workout.
    final ex = exdb.or(e.id ?? '');
    final linkedPrev = i > 0 && e.sg != null && r.ex[i - 1].sg == e.sg;

    return ListItem(
      accentEdge: inSuperset,
      leading: ExerciseThumb(ex: ex),
      onTap: () => exConfigSheet(
        ex: ex,
        existing: e,
        routine: r,
        onSave: (cfg) => _edit((list) {
          final keptId = list[i].id;
          final keptSg = list[i].sg;
          list[i] = cfg.copy()
            ..id = keptId
            ..sg = keptSg;
        }),
        onDelete: () => _edit((list) {
          list.removeAt(i);
          cleanupSg(list);
        }),
      ),
      trailing: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              IconButtonRound('link',
                  size: 30, iconSize: 15, radius: 8, active: linkedPrev,
                  onTap: () => _toggleLink(i)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButtonRound('chevronUp',
                  size: 26, iconSize: 12, radius: 7, onTap: () => _move(i, -1)),
              const SizedBox(width: 2),
              IconButtonRound('chevronDown',
                  size: 26, iconSize: 12, radius: 7, onTap: () => _move(i, 1)),
            ]),
          ],
        ),
      ],
      child: ItemText(ex.n, capitalize: true, subtitle: exLine(e, unit)),
    );
  }

  Widget _coverage(BuildContext context, String body, Routine r) {
    final load = loadOfRoutine(r);
    final worked = rankOf(load).worked;
    return AppCard(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t('What this session hits'),
                style: ts(TypeScale.foot, color: context.c.label2)),
          ),
          BodyMap(load: load, body: body),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in worked.take(6)) MuscleChip(t(muscleName[m]!)),
          ]),
        ],
      ),
    );
  }
}

/// A muscle name as a pill. `miss` marks one the period never trained.
class MuscleChip extends StatelessWidget {
  const MuscleChip(this.label, {super.key, this.miss = false});

  final String label;
  final bool miss;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: miss ? mixT(c.sys.orange, .16) : c.surface2,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: ts(TypeScale.cap, color: miss ? c.sys.orange : c.label2)),
    );
  }
}
