import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/i18n.dart';
import '../../platform/backup.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../sheets/import_sheets.dart';
import '../sheets/plan_sheets.dart';
import '../sheets/sheet_service.dart';
import '../theme/app_colors.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/page.dart';

/// Where the training log lives, and every way of moving it.
///
/// Three groups rather than one list, because the last of them deletes everything: a destructive
/// row one hairline below "Export backup" is a row you can hit on the way past.
class DataSettingsScreen extends ConsumerWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    return AppPage(
      children: [
        PageHeader(
          title: t('Your data'),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/settings')),
        ),

        // ---------- your data ----------
        //
        // Conditional, and it has to be. This row made an unconditional promise for as long as it
        // existed, and it was true: there was no code in the app that could send anything
        // anywhere. Meal photos changed that for the profiles that turn them on, and a claim the
        // app no longer keeps is worse than no claim at all — so the row states which of the two
        // situations the user is actually in.
        Section(children: [
          if (anyAiOn(s))
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

        // ---------- plan ----------
        Section(title: t('Plan'), children: [
          AppRow(
            icon: 'sparkles',
            iconTint: c.acc,
            title: t('Load starter plan (PPL)'),
            accessory: RowAccessory.chevron,
            onTap: () => loadStarterPlan(ref),
          ),
        ]),

        // ---------- backup ----------
        //
        // Untitled: three rows that each name themselves, and a heading over them would only
        // repeat the word every one of them already carries.
        Section(children: [
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
        ]),

        // ---------- the end of everything ----------
        Section(children: [
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
      ],
    );
  }
}

/// Whether any AI feature is switched on — what makes the "stays on this phone" claim
/// conditional, both on this screen and in the row on Settings that summarises it.
bool anyAiOn(AppState s) => s.ai.features.values.any((f) => f.isOn);

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
