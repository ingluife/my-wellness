import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/plan_share.dart';
import '../../domain/starter.dart';
import '../../platform/backup.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';
import 'sheet_service.dart';

/// Load the Push/Pull/Legs starter plan, scheduled Mon/Wed/Fri.
///
/// The one action that takes an empty app to a usable one, which is why it is offered from
/// Home, from Plan and from Settings.
void loadStarterPlan(WidgetRef ref) {
  final routines = starterRoutines();
  ref.read(appStateProvider.notifier).update((s) {
    s.routines.addAll(routines);
    s.week['1'] = routines[0].id;
    s.week['3'] = routines[1].id;
    s.week['5'] = routines[2].id;
  });
  ref.read(uiProvider).toast(t('Starter plan loaded — Mon Push · Wed Pull · Fri Legs'));
}

/// Assign a routine to a weekday — the weekly plan itself.
Future<void> dayAssignSheet(int day) =>
    showSheet<void>((context, close) => _DayAssign(day: day, close: close));

class _DayAssign extends ConsumerWidget {
  const _DayAssign({required this.day, required this.close});

  final int day;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    void set(String? routineId) {
      ref.read(appStateProvider.notifier).update((st) {
        if (routineId == null) {
          st.week.remove('$day');
        } else {
          st.week['$day'] = routineId;
        }
      });
      close();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t(dayn[day])),
        AppList(children: [
          ListItem(
            leading: GlyphTile('moon', background: c.surface3),
            onTap: () => set(null),
            trailing: [
              if (s.week['$day'] == null) AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
            ],
            child: ItemText(t('Rest day')),
          ),
          for (final r in s.routines)
            ListItem(
              leading: GlyphTile(glyphOf(r.emoji)),
              onTap: () => set(r.id),
              trailing: [
                if (s.week['$day'] == r.id)
                  AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
              ],
              child: ItemText(r.name, subtitle: exCount(r.ex.length)),
            ),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Change what one *date* holds, without touching the weekly plan.
///
/// Sick, missed a day, or want a different session — this is the escape hatch that keeps the
/// weekly plan meaningful instead of being edited around every disruption.
Future<void> dayOverrideSheet(String iso) =>
    showSheet<void>((context, close) => _DayOverride(iso: iso, close: close));

class _DayOverride extends ConsumerWidget {
  const _DayOverride({required this.iso, required this.close});

  final String iso;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final weekly = s.routines.where((r) => r.id == s.week['${jsDay(dayOf(iso))}']).firstOrNull;
    final hasOverride = s.dayPlan.containsKey(iso);
    final effId = effectiveRoutineId(s, iso);

    void set(String? value) {
      ref.read(appStateProvider.notifier).update((st) {
        if (value == null) {
          st.dayPlan.remove(iso);
        } else {
          st.dayPlan[iso] = value;
        }
      });
      close();
      final ui = ref.read(uiProvider);
      if (value == null) {
        ui.toast(t('Back to weekly plan'));
      } else if (value == 'rest') {
        ui.toast(t('{0} set to rest', fmtDate(iso)));
      } else {
        final r = s.routines.where((x) => x.id == value).firstOrNull;
        ui.toast(t('{0} planned for {1}', r?.name ?? '', fmtDate(iso)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(fmtDate(iso, true)),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${t('Weekly plan:')} ${weekly?.name ?? t('Rest')}'),
            if (hasOverride)
              TextSpan(
                text: ' · ${t('changed for this day')}',
                style: ts(TypeScale.foot, color: c.sys.orange),
              ),
          ]),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 2),
        Text(t('Sick, missed a day or want a different session? Pick what to train instead.'),
            style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 12),
        AppList(children: [
          for (final r in s.routines)
            ListItem(
              leading: GlyphTile(glyphOf(r.emoji)),
              onTap: () => set(r.id),
              trailing: [
                if (effId == r.id) AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
              ],
              child: ItemText(r.name, subtitle: exCount(r.ex.length)),
            ),
          ListItem(
            leading: GlyphTile('moon', background: c.surface3),
            onTap: () => set('rest'),
            trailing: [
              if (effId == null) AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
            ],
            child: ItemText(t('Rest / skip this day')),
          ),
          if (hasOverride)
            ListItem(
              leading: GlyphTile('reset', background: c.surface3),
              onTap: () => set(null),
              child: ItemText(t('Back to weekly plan')),
            ),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Pick a routine's icon.
///
/// Grouped by what the glyph means for a training day, so picking one is a scan of four short
/// rows rather than a hunt through twenty loose icons.
Future<void> glyphPicker(String? current, void Function(String glyph) onPick) =>
    showSheet<void>((context, close) {
      final c = context.c;
      final cur = glyphOf(current);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Pick an icon')),
          for (final g in glyphGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
              child: Text(t(g.key), style: ts(TypeScale.foot, color: c.label2)),
            ),
            Row(
              children: [
                for (final n in g.items)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: n == g.items.last ? 0 : 9),
                      child: GestureDetector(
                        onTap: () {
                          close();
                          onPick(n);
                        },
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: n == cur ? c.acc : c.surface,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            alignment: Alignment.center,
                            child: AppIcon(n, size: 24, color: n == cur ? c.onAcc : c.label),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 4),
        ],
      );
    });

/// Send your routines to someone, or take theirs.
Future<void> planToolsSheet(WidgetRef ref) =>
    showSheet<void>((context, close) => _PlanTools(close: close));

class _PlanTools extends ConsumerWidget {
  const _PlanTools({required this.close});

  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final hasRoutines = s.routines.any((r) => r.ex.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Share your plan')),
        Text(t('Send your routines to a friend, or put your week on paper.'),
            style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 16),
        AppButton(
          t('Export plan file'),
          variant: BtnVariant.primary,
          icon: 'upload',
          enabled: hasRoutines,
          onTap: () async {
            close();
            try {
              await Backup.shareJson(
                  buildPlanBundle(s, ''), 'opengym-plan-${todayISO()}.json');
            } catch (_) {
              // The share sheet was dismissed.
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
          child: Text(
            t('A small file a friend imports into their own openGym — routines only, none of your workouts or weigh-ins.'),
            style: ts(TypeScale.foot, color: c.label3),
          ),
        ),
        if (!hasRoutines)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
            child: Text(
              t('Add an exercise to a routine first — an empty plan has nothing to share.'),
              style: ts(TypeScale.foot, color: c.label3),
            ),
          ),
        SecHeading(t('Got a plan from a friend?')),
        AppButton(t('Import a plan file'), variant: BtnVariant.ghost, icon: 'folder',
            onTap: () async {
          final raw = await Backup.pickText(['json']);
          if (raw == null) return;
          final PlanBundle bundle;
          try {
            bundle = parsePlan(raw);
          } catch (e) {
            ref.read(uiProvider).toast(
                t('Import failed: {0}', t('this isn’t an openGym plan file')));
            return;
          }
          close();
          await planImportSheet(bundle);
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// What a shared plan would add, before it is added.
Future<void> planImportSheet(PlanBundle bundle) =>
    showSheet<void>((context, close) => _PlanImport(bundle: bundle, close: close));

class _PlanImport extends ConsumerStatefulWidget {
  const _PlanImport({required this.bundle, required this.close});

  final PlanBundle bundle;
  final void Function([void]) close;

  @override
  ConsumerState<_PlanImport> createState() => _PlanImportState();
}

class _PlanImportState extends ConsumerState<_PlanImport> {
  bool _schedule = false;

  void _commit({String? replaceId, required String toast}) {
    ref.read(appStateProvider.notifier).update(
        (st) => mergePlan(st, widget.bundle, schedule: _schedule, replaceId: replaceId));
    widget.close();
    ref.read(uiProvider).toast(toast);
    appNavigatorKey.currentContext?.go('/plan');
  }

  /// The plain import, and the "Keep both" answer to a name collision.
  void _add() => _commit(
        toast: t(
            widget.bundle.routineCount == 1
                ? 'Added {0} routine to your plan'
                : 'Added {0} routines to your plan',
            widget.bundle.routineCount),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = widget.bundle;
    // Only ever set for a single-routine file — a whole plan imports as it always has.
    final dup = duplicateOf(ref.watch(appStateProvider), b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(b.name.isNotEmpty ? t('Import “{0}”', b.name) : t('Import this plan')),
        Text(
          [
            t(b.routineCount == 1 ? '{0} routine' : '{0} routines', b.routineCount),
            exCount(b.exerciseCount),
            if (b.scheduledDays > 0)
              t(b.scheduledDays == 1 ? 'scheduled on {0} day' : 'scheduled on {0} days',
                  b.scheduledDays),
          ].join(' · '),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 14),
        Text(t('These are added as new routines — nothing you already have is changed.'),
            style: ts(TypeScale.foot, color: c.label3)),
        if (b.dropped > 0) ...[
          const SizedBox(height: 14),
          Text(
            t(
              b.dropped == 1
                  ? '{0} exercise in the file isn’t in your library and was left out.'
                  : '{0} exercises in the file aren’t in your library and were left out.',
              b.dropped,
            ),
            style: ts(TypeScale.foot, color: c.sys.yellow),
          ),
        ],
        if (dup != null) ...[
          const SizedBox(height: 14),
          Text(t('You already have a routine called “{0}”.', dup.name),
              style: ts(TypeScale.foot, color: c.sys.yellow)),
        ],
        if (b.scheduledDays > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration: BoxDecoration(
              border: Border.symmetric(
                  horizontal: BorderSide(color: c.sep, width: R.hair)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t('Use this weekly schedule'),
                        style: ts(TypeScale.sub, color: c.label)),
                    Text(t('Replaces your current Mon–Sun assignments.'),
                        style: ts(TypeScale.foot, color: c.label3)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppSwitch(value: _schedule, onChanged: (v) => setState(() => _schedule = v)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        if (dup != null) ...[
          // Replacing overwrites the routine in place, keeping its id — so a weekday it is
          // scheduled on stays scheduled.
          AppButton(t('Replace it'),
              variant: BtnVariant.primary,
              onTap: () => _commit(
                  replaceId: dup.id, toast: t('Replaced “{0}”', dup.name))),
          const SizedBox(height: 8),
          AppButton(t('Keep both'), variant: BtnVariant.tinted, onTap: _add),
        ] else
          AppButton(t('Add to my plan'), variant: BtnVariant.primary, onTap: _add),
        const SizedBox(height: 8),
        AppButton(t('Cancel'),
            variant: BtnVariant.ghost, color: c.label3, onTap: widget.close),
        const SizedBox(height: 8),
      ],
    );
  }
}
