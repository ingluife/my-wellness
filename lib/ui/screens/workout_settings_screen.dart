import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../sheets/effort_help_sheet.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/page.dart';

/// How a session behaves while it is running.
///
/// Four settings you decide once and then live with for months — which is exactly why they are
/// behind a row on Settings rather than in the middle of it.
class WorkoutSettingsScreen extends ConsumerWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    return AppPage(
      children: [
        PageHeader(
          title: t('During a workout'),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/settings')),
        ),
        Section(
          footer: t('The screen stays on while a workout is running, so you don’t have to unlock your phone between sets.'),
          children: [
            SelectRow<double>(
              icon: 'timer',
              iconTint: c.sys.orange,
              title: t('Rest timer'),
              value: s.restSec,
              onChanged: (v) => notifier.update((st) => st.restSec = v),
              options: [
                for (final v in [60.0, 90.0, 120.0, 150.0, 180.0])
                  SelectOption(v, '${v.toInt()}s'),
              ],
            ),
            AppRow(
              icon: 'sun',
              iconTint: c.sys.yellow,
              title: t('Keep screen awake'),
              trailing: AppSwitch(
                value: s.keepAwake,
                onChanged: (v) => notifier.update((st) => st.keepAwake = v),
              ),
            ),
            AppRow(
              icon: 'bell',
              iconTint: c.sys.pink,
              title: t('Sounds'),
              trailing: AppSwitch(
                value: s.sound,
                onChanged: (v) => notifier.update((st) => st.sound = v),
              ),
            ),
            // Two names for the same judgement, so the column asks in the scale you already
            // think in. The (i) sits before the control — you read it on the way to the
            // choice, not after it.
            AppRow(
              icon: 'target',
              iconTint: c.sys.purple,
              title: t('Effort per set'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Pressable(
                  onTap: effortHelpSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AppIcon('info', size: 16, color: c.label3),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 150,
                  child: Segmented<String>(
                    inline: true,
                    value: effortOf(s),
                    onChanged: (v) => notifier.update((st) {
                      st.effort = v;
                      st.showRir = null;
                    }),
                    options: [
                      SegOption('none', label: t('Off')),
                      SegOption('rir', label: t('RIR')),
                      SegOption('rpe', label: t('RPE')),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ],
    );
  }
}
