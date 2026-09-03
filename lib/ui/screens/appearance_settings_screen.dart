import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/page.dart';

/// What the app looks like. Nothing here changes what it does.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    return AppPage(
      children: [
        PageHeader(
          title: t('Appearance'),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/settings')),
        ),
        Section(children: [
          AppRow(
            icon: 'moon',
            iconTint: c.sys.indigo,
            title: t('Theme'),
            trailing: SizedBox(
              width: 150,
              child: Segmented<String>(
                inline: true,
                value: s.theme == 'light' ? 'light' : 'dark',
                onChanged: (v) => notifier.update((st) => st.theme = v),
                options: [
                  SegOption('dark', icon: 'moon', label: t('Dark')),
                  SegOption('light', icon: 'sun', label: t('Light')),
                ],
              ),
            ),
          ),
          // Purely how the muscle map is drawn — nothing else in the app reads this.
          AppRow(
            icon: 'figureStrength',
            iconTint: c.sys.teal,
            title: t('Body diagram'),
            trailing: SizedBox(
              width: 150,
              child: Segmented<String>(
                inline: true,
                value: s.body == 'female' ? 'female' : 'male',
                onChanged: (v) => notifier.update((st) => st.body = v),
                options: [
                  SegOption('male', label: t('Male')),
                  SegOption('female', label: t('Female')),
                ],
              ),
            ),
          ),
          _AccentRow(
            selected: accentFrom(s.accent),
            onPick: (a) => notifier.update((st) => st.accent = a.name),
          ),
        ]),
      ],
    );
  }
}

/// The eight accent swatches.
class _AccentRow extends StatelessWidget {
  const _AccentRow({required this.selected, required this.onPick});

  final Accent selected;
  final ValueChanged<Accent> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Accent color'), style: ts(TypeScale.body, color: c.label)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final a in Accent.values)
                Pressable(
                  scale: .9,
                  onTap: () => onPick(a),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentSwatch[a],
                      shape: BoxShape.circle,
                      // The selected swatch gets a ring set off from it, so the colour itself
                      // is never overlaid by the indicator.
                      border: a == selected
                          ? Border.all(color: c.label, width: 2)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
