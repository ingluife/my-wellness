import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../../platform/reminders.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/page.dart';
import 'data_settings_screen.dart';

/// Everything the profile can decide about itself — as an index, not as a list.
///
/// This screen used to hold all twenty-three of them in one scroll, which put the accent
/// swatches at the same weight as "Reset everything" and left no way to see its shape at a
/// glance. What stays here is what you change often (language, units) or need to *read* often;
/// everything dense or set-once sits behind a row that shows its current value, so drilling in
/// is for changing a setting, never for finding out what it is.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    return AppPage(
      children: [
        PageHeader(
          title: t('Settings'),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/home')),
        ),

        // ---------- general ----------
        Section(
          title: t('General'),
          footer: t('Note: switching units only changes the label — logged numbers are not converted.'),
          children: [
            SelectRow<String>(
              icon: 'globe',
              iconTint: c.sys.blue,
              title: t('Language'),
              value: s.lang,
              onChanged: (v) => notifier.update((st) => st.lang = v),
              options: [
                for (final e in langs.entries)
                  SelectOption(
                    e.key,
                    e.value,
                    subtitle: instrLangs.contains(e.key)
                        ? null
                        : t("Exercise instructions aren't available in this language yet — they stay in English."),
                  ),
              ],
            ),
            AppRow(
              icon: 'scale',
              iconTint: c.sys.teal,
              title: t('Weight unit'),
              trailing: SizedBox(
                width: 132,
                child: Segmented<String>(
                  inline: true,
                  value: s.unit,
                  onChanged: (v) => notifier.update((st) => st.unit = v),
                  options: const [SegOption('kg', label: 'kg'), SegOption('lb', label: 'lb')],
                ),
              ),
            ),
            AppRow(
              icon: 'moon',
              iconTint: c.sys.indigo,
              title: t('Appearance'),
              value: _appearanceLine(s),
              accessory: RowAccessory.chevron,
              onTap: () => context.go('/settings/appearance'),
            ),
          ],
        ),

        // ---------- workouts ----------
        //
        // The reminder rows stay in place rather than following the rest behind a chevron: a
        // single switch is not worth a screen, and the time it fires at is the kind of thing you
        // want to confirm without a round trip.
        WorkoutsSection(state: s),

        // ---------- ai ----------
        Section(
          title: t('AI features'),
          footer: t('Off unless you set it up, and it runs on your own provider account.'),
          children: [
            AppRow(
              icon: 'sparkles',
              iconTint: c.sys.purple,
              title: t('AI providers'),
              subtitle: _aiLine(s),
              accessory: RowAccessory.chevron,
              onTap: () => context.go('/settings/ai'),
            ),
          ],
        ),

        // ---------- data ----------
        //
        // One row doing two jobs. The promise this app makes about where your training log lives
        // is the first thing the old screen said, and it still is — carried as the subtitle of
        // the row that leads to everything that could move that log off the device.
        Section(title: t('Data'), children: [
          AppRow(
            icon: 'lock',
            iconTint: c.acc,
            title: t('Your data'),
            subtitle: anyAiOn(s)
                ? t('Your training log stays on this phone')
                : t('All data stays on this phone'),
            accessory: RowAccessory.chevron,
            onTap: () => context.go('/settings/data'),
          ),
        ]),

        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          child: Text(
            'myOpenGym · ${t('free & open source (AGPL v3)')}\n'
            'a Flutter translation of openGym · exercise data: hasaneyldrm/exercises-dataset (CC)',
            textAlign: TextAlign.center,
            style: ts(TypeScale.foot, color: c.label3),
          ),
        ),
      ],
    );
  }
}

/// 'Anthropic · Claude Opus 5', or 'Off'.
String _aiLine(AppState s) {
  final cfg = s.ai.features[aiMealPhoto];
  if (cfg == null || !cfg.isOn || cfg.provider == null) return t('Off');
  final name = aiProviderName[cfg.provider] ?? cfg.provider!;
  final model = modelFor(cfg.provider!, cfg.model);
  return model == null ? name : '$name · ${model.label}';
}

/// 'Dark' or 'Light' — the one thing about the look you can tell from a word.
String _appearanceLine(AppState s) => s.theme == 'light' ? t('Light') : t('Dark');

/// '90s · RIR', or the rest alone when the effort column is off.
///
/// The summary a row has to earn its chevron with: both halves are things you set once and then
/// want to check, not change.
String _workoutLine(AppState s) {
  final rest = '${s.restSec.toInt()}s';
  final effort = effortOf(s);
  return effort == 'none' ? rest : '$rest · ${t(effort.toUpperCase())}';
}

/// How a session behaves, and when the app asks you to have one.
///
/// The schedule itself is resynced by the app whenever the plan or the time changes; this
/// section only owns the OS permission prompt, which belongs to the moment the switch is
/// turned on and nowhere else.
class WorkoutsSection extends ConsumerWidget {
  const WorkoutsSection({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final on = state.reminder.on;

    Future<void> toggle(bool next) async {
      if (next) {
        final probe = state.copy()..reminder.on = true;
        final ok = await Reminders.instance.sync(probe, interactive: true);
        if (!ok) {
          ref.read(uiProvider).toast(t('Could not change notification settings'));
          return;
        }
      }
      ref.read(appStateProvider.notifier).update((st) {
        st.reminder
          ..on = next
          ..tz = localTZ();
      });
    }

    return Section(
      title: t('Workouts'),
      footer: on ? t('Reminds you at this time on days that have a routine planned.') : null,
      children: [
        AppRow(
          icon: 'timer',
          iconTint: c.sys.orange,
          title: t('During a workout'),
          value: _workoutLine(state),
          accessory: RowAccessory.chevron,
          onTap: () => context.go('/settings/workout'),
        ),
        AppRow(
          icon: 'calendar',
          iconTint: c.sys.orange,
          title: t('Workout day reminder'),
          trailing: AppSwitch(value: on, onChanged: toggle),
        ),
        if (on)
          AppRow(
            icon: 'clock',
            iconTint: c.sys.purple,
            title: t('Reminder time'),
            value: state.reminder.time,
            accessory: RowAccessory.chevron,
            onTap: () async {
              final parts = state.reminder.time.split(':');
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: int.tryParse(parts.first) ?? 8,
                  minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
                ),
              );
              if (picked == null) return;
              ref.read(appStateProvider.notifier).update((st) {
                st.reminder
                  ..time = '${picked.hour.toString().padLeft(2, '0')}:'
                      '${picked.minute.toString().padLeft(2, '0')}'
                  ..tz = localTZ();
              });
            },
          ),
      ],
    );
  }
}
