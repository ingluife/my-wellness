import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/i18n.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../sheets/plan_ai_sheet.dart';
import '../sheets/plan_sheets.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// The weekly plan: which routine each weekday holds, and the routines themselves.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  /// Monday first — the week the plan is actually read in, whatever `getDay()` numbers it.
  static const _order = [1, 2, 3, 4, 5, 6, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    void addRoutine() {
      final r = Routine(id: uid(), name: t('New routine'), emoji: defaultGlyph);
      ref.read(appStateProvider.notifier).update((st) => st.routines.add(r));
      context.go('/plan/r/${r.id}');
    }

    return AppPage(
      children: [
        PageHeader(
          title: t('Plan'),
          subtitle: t('Your weekly routine'),
          trailing: IconButtonRound('upload', onTap: () => planToolsSheet(ref)),
        ),
        SecHeading(t('Week schedule'), margin: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
        AppList(children: [
          for (final d in _order)
            () {
              final r = s.routines.where((x) => x.id == s.week['$d']).firstOrNull;
              return ListItem(
                onTap: () => dayAssignSheet(d),
                trailing: [
                  r != null
                      ? Tag(r.name, icon: glyphOf(r.emoji), accent: true, capitalize: false)
                      : Tag(t('Rest')),
                  AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4),
                ],
                child: ItemText(t(dayn[d])),
              );
            }(),
        ]),
        SecHeading(
          t('Routines'),
          trailing: AppButton(t('New'),
              size: BtnSize.sm, variant: BtnVariant.tinted, icon: 'plus', onTap: addRoutine),
        ),
        // Honest when it is off rather than absent: a row saying "set this up" is better than a
        // feature nobody finds, and better than a button that fails on the first tap. Same
        // pattern the nutrition screen uses for meal photos.
        _draftRow(context, ref),
        if (s.routines.isNotEmpty)
          AppList(children: [
            for (final r in s.routines)
              ListItem(
                leading: GlyphTile(glyphOf(r.emoji)),
                onTap: () => context.go('/plan/r/${r.id}'),
                trailing: [AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4)],
                child: ItemText(r.name, subtitle: exCount(r.ex.length)),
              ),
          ])
        else ...[
          EmptyState(
            icon: 'clipboard',
            message: t('No routines yet.'),
            detail: t('Create one or load the starter plan.'),
          ),
          AppButton(t('Load starter plan (Push / Pull / Legs)'),
              icon: 'sparkles', onTap: () => loadStarterPlan(ref)),
        ],
        // The catalogue's only door, now that it is not a tab. It belongs to this screen rather
        // than to Settings: browsing it is something you do while building a routine, and the
        // routines are the list directly above it.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ListItem(
            leading: GlyphTile('list'),
            onTap: () => context.go('/library'),
            trailing: [AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4)],
            child: ItemText(
              t('Exercises'),
              subtitle: t('{0} exercises with animations', exdb.db.length),
            ),
          ),
        ),
      ],
    );
  }

  /// The AI drafting entry point, which is a different row depending on whether it can run.
  Widget _draftRow(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final on = ref.watch(aiWorkoutPlanProvider).isAvailable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListItem(
        leading: GlyphTile('sparkles', background: on ? c.acc : c.surface3),
        onTap: () => on ? aiPlanSheet(ref) : context.go('/settings/ai'),
        trailing: [AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4)],
        child: ItemText(
          on ? t('Draft a routine with AI') : t('Set up AI routines'),
          subtitle: on
              ? t('From your goals, using the exercises already here')
              : t('Use your own AI provider to draft a routine'),
        ),
      ),
    );
  }
}
