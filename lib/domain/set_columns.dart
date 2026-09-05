import '../data/models/app_state.dart';
import 'history.dart';
import 'i18n.dart';

/// One column of a set row.
typedef SetColumn = ({
  String field,
  double step,
  bool decimal,
  String heading,
  bool optional,
  String? effortScale,
});

/// The up to three columns a set row shows for one running entry.
///
/// Shared by the workout screen's steppers and the quick-action notification, so a tap in
/// either place moves the same field by the same step — there is exactly one place that decides
/// what "+1" or "+2.5 kg" means for a given exercise.
({SetColumn col1, SetColumn? col2, SetColumn? col3}) setColumnsFor(
    AppState s, WorkoutEntry entry) {
  final cfg = entry.cfg;
  final mode = modeOf(cfg);
  final cardio = mode == 'cardio';
  final timed = mode == 'time';

  // A bodyweight set has no weight to type, so the column is not there — one stepper instead
  // of two, which is the whole point of the flag. Adding a belt weight in the config brings
  // it back, now labelled as the addition it is.
  final bw = !cardio && isBw(cfg);
  final added = bw && entry.sets.any((x) => (x.w ?? 0) > 0);

  final loadCol = (
    field: 'w',
    step: 2.5,
    decimal: true,
    heading: bw ? t('Added ({0})', s.unit) : t('Weight ({0})', s.unit),
    optional: false,
    effortScale: null,
  );
  // The reps column is the total in every mode, unilateral included — the stepper walks in
  // twos there so the number you land on is one you can actually split evenly.
  final repCol = (
    field: 'r',
    step: repStep(cfg),
    decimal: false,
    heading: t('Reps'),
    optional: false,
    effortScale: null,
  );

  final SetColumn col1 = cardio
      ? (
          field: 'min',
          step: 1,
          decimal: false,
          heading: t('Duration (min)'),
          optional: false,
          effortScale: null,
        )
      : timed
          ? (
              field: 'sec',
              step: 5,
              decimal: false,
              heading: t('Seconds'),
              optional: false,
              effortScale: null,
            )
          : (bw && !added ? repCol : loadCol);

  final SetColumn? col2 = cardio
      ? (
          field: 'speed',
          step: 0.5,
          decimal: true,
          heading: t('Speed (km/h)'),
          optional: false,
          effortScale: null,
        )
      : timed
          ? ((bw && !added) ? null : loadCol)
          : ((bw && !added) ? null : repCol);

  // Effort only makes sense for weighted rep sets, not cardio or timed holds, and is opt-in
  // since it adds a third stepper to every row. Optional, because an unlogged effort is not
  // the same as 0 — RIR 0 says the set went to failure.
  final kind = effortOf(s);
  final eff = effortScales[kind];
  final SetColumn? col3 = mode == 'reps' && eff != null
      ? (
          field: eff.f,
          step: eff.step,
          decimal: true,
          heading: t(eff.hd),
          optional: true,
          effortScale: kind,
        )
      : null;

  return (col1: col1, col2: col2, col3: col3);
}
