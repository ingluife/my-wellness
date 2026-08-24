import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/import_csv.dart';
import '../../platform/backup.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../screens/routine_edit_screen.dart' show MuscleChip;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/page.dart';
import 'sheet_service.dart';
import 'workout_flow.dart' show StatTiles;

/// Read a CSV or XML export and show what it would do.
///
/// An import is the one action where "just try it" is expensive — it is someone's entire
/// training history — so the numbers, the unit conversion and the exercises we could not
/// recognise are all on screen before anything is written.
Future<void> importFromAppFile(WidgetRef ref) async {
  final raw = await Backup.pickText(['csv', 'xml', 'txt']);
  if (raw == null) return;

  final ui = ref.read(uiProvider);
  final ImportResult parsed;
  try {
    parsed = parseImport(raw, unit: ref.read(appStateProvider).unit);
  } catch (_) {
    ui.toast(t('Could not read that file'));
    return;
  }

  if (parsed.error == 'empty') return ui.toast(t('That file is empty'));
  if (parsed.error != null) {
    return ui.toast(t("That file's columns aren't recognised — see the docs for supported apps."));
  }
  if (parsed.isBodyweight ? parsed.bodyweight.isEmpty : parsed.workouts.isEmpty) {
    return ui.toast(t('Nothing to import from that file'));
  }

  await showSheet<void>((context, close) => _ImportSummary(parsed: parsed, close: close));
}

class _ImportSummary extends ConsumerWidget {
  const _ImportSummary({required this.parsed, required this.close});

  final ImportResult parsed;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final isBw = parsed.isBodyweight;

    final have = isBw
        ? parsed.bodyweight.where((b) => s.bodyweight.any((x) => x.d == b.d)).length
        : parsed.workouts.where((w) => s.workouts.any((x) => x.d == w.d)).length;
    final total = isBw ? parsed.bodyweight.length : parsed.workouts.length;
    final fresh = total - have;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(parsed.source != null
            ? t('Import from {0}', parsed.source)
            : t('Import history')),
        Text(
          parsed.from == parsed.to
              ? fmtDate(parsed.from ?? todayISO(), true)
              : '${fmtDate(parsed.from ?? todayISO(), true)} – ${fmtDate(parsed.to ?? todayISO(), true)}',
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 12),
        StatTiles(tiles: [
          if (isBw) ...[
            (label: t('Weigh-ins'), value: '${parsed.bodyweight.length}', color: null),
            (label: t('New'), value: '$fresh', color: null),
          ] else ...[
            (label: t('Workouts'), value: '${parsed.workouts.length}', color: null),
            (label: t('Sets'), value: '${parsed.sets}', color: null),
            (label: t('Exercises matched'), value: '${parsed.matched}', color: null),
            (label: t('Added as your own'), value: '${parsed.created}', color: null),
          ],
        ]),
        if (parsed.mixedUnits)
          _Note(t('The file mixes kg and lb — each set is converted to {0}.', s.unit),
              color: c.sys.yellow)
        else if (parsed.converted)
          _Note(
              t('The file is in {0} and your profile is in {1} — weights will be converted.',
                  parsed.fileUnit, s.unit),
              color: c.sys.yellow),
        if (!isBw && parsed.fileUnit.isEmpty && !parsed.mixedUnits)
          _Note(t('The file does not say which unit it uses — numbers are imported as they are.'),
              color: c.label3),
        if (have > 0)
          _Note(t('{0} days already have data here and will be left alone.', have),
              color: c.label3),
        // The file rated its sets. Say so: the column is off by default, so the ratings would
        // otherwise arrive invisibly and look like they had been dropped.
        if (!isBw && parsed.rirSets + parsed.rpeSets > 0)
          _Note(
            t(
              effortOf(s) == 'none'
                  ? '{0} sets bring an {1} with them — switch on Effort per set in Settings to see it.'
                  : '{0} sets bring an {1} with them.',
              parsed.rirSets > 0 ? parsed.rirSets : parsed.rpeSets,
              parsed.rirSets > 0 ? 'RIR' : 'RPE',
            ),
            color: c.label3,
          ),
        if (!isBw && parsed.unmatchedNames.isNotEmpty) ...[
          SecHeading(t('Not in the library — added as your own exercises'),
              margin: const EdgeInsets.fromLTRB(4, 8, 4, 8)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in parsed.unmatchedNames.take(12)) MuscleChip(capitalizedName(n)),
            if (parsed.unmatchedNames.length > 12)
              MuscleChip('+${parsed.unmatchedNames.length - 12}'),
          ]),
          const SizedBox(height: 12),
        ],
        AppButton(
          fresh > 0 ? t('Import') : t('Nothing new to import'),
          variant: BtnVariant.primary,
          enabled: fresh > 0,
          onTap: () {
            late final ({int added, int skipped}) res;
            ref.read(appStateProvider.notifier).update((st) => res = mergeImport(st, parsed));
            close();
            ref.read(uiProvider).toast(isBw
                ? t('{0} weigh-ins imported', res.added)
                : t('{0} workouts imported', res.added));
          },
        ),
        const SizedBox(height: 8),
        AppButton(t('Cancel'), variant: BtnVariant.ghost, color: c.label3, onTap: close),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Exercise names arrive lowercase from an export, like they do from the dataset.
String capitalizedName(String s) => s.isEmpty
    ? s
    : s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: ts(TypeScale.foot, color: color)),
      );
}
