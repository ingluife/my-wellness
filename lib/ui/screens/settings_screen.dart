import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../sheets/effort_help_sheet.dart';
import '../../platform/backup.dart';
import '../../platform/reminders.dart';
import '../sheets/import_sheets.dart';
import '../sheets/nutrition_sheets.dart';
import '../sheets/plan_sheets.dart';
import '../sheets/sheet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/page.dart';

/// Everything the profile can decide about itself.
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

        // ---------- your data ----------
        //
        // Conditional, and it has to be. This row made an unconditional promise for as long as it
        // existed, and it was true: there was no code in the app that could send anything
        // anywhere. Meal photos changed that for the profiles that turn them on, and a claim the
        // app no longer keeps is worse than no claim at all — so the row states which of the two
        // situations the user is actually in.
        Section(title: t('Your data'), children: [
          if (_anyAiOn(s))
            AppRow(
              icon: 'lock',
              iconTint: c.acc,
              title: t('Your training log stays on this phone'),
              subtitle: t('The only exception is a meal photo, which goes to the AI provider you set up.'),
            )
          else
            AppRow(
              icon: 'lock',
              iconTint: c.acc,
              title: t('All data stays on this phone'),
              subtitle: t('No account, no cloud — back it up anytime with Export below.'),
            ),
        ]),

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
          ],
        ),

        // ---------- during a workout ----------
        Section(
          title: t('During a workout'),
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

        // ---------- nutrition ----------
        Section(
          title: t('Nutrition'),
          footer: s.nutrition.profile.isComplete
              ? t('Your target is worked out from these and from the sessions in your plan.')
              : t('Set these once and the app can work out what to eat around your training.'),
          children: [
            AppRow(
              icon: 'person',
              iconTint: c.sys.teal,
              title: t('About you'),
              subtitle: s.nutrition.profile.isComplete
                  ? '${s.nutrition.profile.age!.round()} · '
                      '${s.nutrition.profile.height!.round()} cm'
                  : t('Not set'),
              accessory: RowAccessory.chevron,
              onTap: bodyProfileSheet,
            ),
            AppRow(
              icon: 'target',
              iconTint: c.acc,
              title: t('Goal'),
              subtitle: _goalLine(s),
              accessory: RowAccessory.chevron,
              onTap: nutritionGoalSheet,
            ),
            AppRow(
              icon: 'meal',
              iconTint: c.sys.orange,
              title: t('Food & meals'),
              accessory: RowAccessory.chevron,
              onTap: () => context.go('/nutrition'),
            ),
          ],
        ),

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

        ReminderSection(state: s),

        // ---------- appearance ----------
        Section(title: t('Appearance'), children: [
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

        // ---------- data ----------
        Section(title: t('Data'), children: [
          AppRow(
            icon: 'sparkles',
            iconTint: c.acc,
            title: t('Load starter plan (PPL)'),
            accessory: RowAccessory.chevron,
            onTap: () => loadStarterPlan(ref),
          ),
          AppRow(
            icon: 'shuffle',
            iconTint: c.sys.teal,
            title: t('Import from another app'),
            subtitle: t('FitNotes, Strong, Hevy — or body weight from Apple Health'),
            accessory: RowAccessory.chevron,
            onTap: () => importFromAppFile(ref),
          ),
          AppRow(
            icon: 'upload',
            iconTint: c.sys.blue,
            title: t('Import backup'),
            accessory: RowAccessory.chevron,
            onTap: () => importBackupFile(ref),
          ),
          AppRow(
            icon: 'download',
            iconTint: c.sys.blue,
            title: t('Export backup (JSON)'),
            accessory: RowAccessory.chevron,
            onTap: () => exportBackup(ref),
          ),
          AppRow(
            icon: 'trash',
            iconTint: c.sys.red,
            title: t('Reset everything'),
            danger: true,
            onTap: () => confirmSheet(
              title: t('Reset everything?'),
              message: t('Deletes your plan, workouts and body weight on this device. This cannot be undone.'),
              confirmText: t('Delete everything'),
              danger: true,
              onConfirm: () async {
                await ref.read(stateRepositoryProvider).clear();
                // The keys live outside the state, so clearing the state does not reach them.
                // Without this line a reset leaves the user's API key on the device — the one
                // piece of data here that is genuinely a credential.
                await ref.read(aiKeyStoreProvider).clear();
                // Same reasoning, second store: meal photographs are files beside the state, not
                // in it, so wiping the state leaves every one of them on the disk.
                await ref.read(mealPhotoStoreProvider).clear();
                ref.invalidate(aiConfiguredProvider);
                notifier.replaceState(AppState.defaults());
                if (context.mounted) context.go('/home');
                ref.read(uiProvider).toast(t('All data reset'));
              },
            ),
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

/// The workout-day reminder.
///
/// The schedule itself is resynced by the app whenever the plan or the time changes; this
/// section only owns the OS permission prompt, which belongs to the moment the switch is
/// turned on and nowhere else.
/// Whether any AI feature is switched on — what makes the "stays on this phone" row conditional.
bool _anyAiOn(AppState s) => s.ai.features.values.any((f) => f.isOn);

/// 'Anthropic · Claude Opus 5', or 'Off'.
String _aiLine(AppState s) {
  final cfg = s.ai.features[aiMealPhoto];
  if (cfg == null || !cfg.isOn || cfg.provider == null) return t('Off');
  final name = aiProviderName[cfg.provider] ?? cfg.provider!;
  final model = modelFor(cfg.provider!, cfg.model);
  return model == null ? name : '$name · ${model.label}';
}

/// "Lose 0.5 kg a week", or the mode alone when it has no rate.
String _goalLine(AppState s) {
  final g = s.nutrition.goal;
  final mode = goalMode(g);
  if (mode == 'maintain') return t('Maintain');
  final rate = goalRate(g).abs();
  return mode == 'cut'
      ? t('Lose {0} kg a week', fmtNum(rate))
      : t('Gain {0} kg a week', fmtNum(rate));
}

class ReminderSection extends ConsumerWidget {
  const ReminderSection({super.key, required this.state});

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
      title: t('Notifications'),
      footer: on ? t('Reminds you at this time on days that have a routine planned.') : null,
      children: [
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

/// Hand the whole training log to the OS share sheet.
Future<void> exportBackup(WidgetRef ref) async {
  try {
    await Backup.export(ref.read(appStateProvider));
    ref.read(uiProvider).toast(t('Backup exported'));
  } catch (_) {
    // The share sheet was dismissed — not a failure worth reporting.
  }
}

/// Replace everything with a backup file.
///
/// Wholesale, not merged, and confirmed first: an import is the one action where "just try it"
/// is expensive, because what it overwrites is someone's entire training history.
Future<void> importBackupFile(WidgetRef ref) async {
  final raw = await Backup.pickText(['json']);
  if (raw == null) return;
  final AppState next;
  try {
    next = Backup.parse(raw);
  } catch (e) {
    ref.read(uiProvider).toast(t('Import failed: {0}', 'not an openGym backup'));
    return;
  }
  confirmSheet(
    title: t('Import backup?'),
    message: t('This replaces all current data with the backup file.'),
    confirmText: t('Import'),
    danger: true,
    onConfirm: () {
      ref.read(appStateProvider.notifier).replaceState(next);
      ref.read(uiProvider).toast(t('Backup imported'));
    },
  );
}
