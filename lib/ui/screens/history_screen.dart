import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../sheets/workout_flow.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/page.dart';

/// Every workout, newest first. Reached from Stats, because it is the long tail of the same
/// question that screen answers.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    return AppPage(
      children: [
        PageHeader(
          title: t('History'),
          subtitle: t('{0} workouts', s.workouts.length),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/stats')),
        ),
        if (s.workouts.isEmpty)
          EmptyState(icon: 'history', message: t('No workouts yet.'))
        else
          AppList(children: [
            for (final w in s.workouts.reversed)
              WorkoutRow(workout: w, onTap: () => workoutDetailSheet(w)),
          ]),
      ],
    );
  }
}
