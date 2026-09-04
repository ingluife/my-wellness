import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/plan_draft.dart';
import '../../domain/ai/plan_prompt.dart';
import '../../domain/ai/plan_sanitize.dart';
import '../../domain/ai/plan_scope.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
import 'sheet_service.dart';

/// Ask the model for a routine, check what it drafted, then save it.
///
/// **Nothing is written before Save.** The answer becomes a [PlanDraft] that lives in this
/// widget's state until the user agrees to it, and Save then mints routines through the ordinary
/// [Routine] / [ExerciseConfig] path — so a drafted routine and a hand-built one are the same
/// thing by the time they reach the plan, with the same progression, the same animations and the
/// same editor.
///
/// The draft is deliberately reviewable rather than one-tap. A model choosing from 1,300
/// exercises will occasionally produce a session that is technically valid and wrong for the
/// person — too much volume, a movement their shoulder will not tolerate, six variations of one
/// lift. Read first, then keep.
Future<void> aiPlanSheet(WidgetRef ref) =>
    showSheet<void>((context, close) => _AiPlanSheet(close: close));

enum _Phase { brief, thinking, review, failed }

class _AiPlanSheet extends ConsumerStatefulWidget {
  const _AiPlanSheet({required this.close});

  final void Function([void]) close;

  @override
  ConsumerState<_AiPlanSheet> createState() => _AiPlanSheetState();
}

class _AiPlanSheetState extends ConsumerState<_AiPlanSheet> {
  _Phase _phase = _Phase.brief;

  PlanScope _scope = const PlanScope.fullBody();
  int _days = 3;
  int _minutes = 60;
  String _experience = 'training for a while';
  final _note = TextEditingController();

  PlanDraft? _draft;
  AiFailureKind? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  // ---------- the ask ----------

  Future<void> _draftPlan() async {
    setState(() => _phase = _Phase.thinking);

    final s = ref.read(appStateProvider);
    final brief = _brief(s);
    // Filtered here, before a single token is paid for: the scope is a catalogue filter rather
    // than an instruction, which is what keeps a targeted request an order of magnitude cheaper
    // than a full-body one. See the note at the top of plan_prompt.dart.
    final catalogue = exercisesInScope(brief.scope, equipment: _equipmentFilter(brief));

    if (catalogue.isEmpty) {
      // Only reachable if the equipment filter empties the scope — which it can, for somebody who
      // has only ever logged bodyweight work and asks for a barbell-only muscle.
      setState(() {
        _draft = PlanDraft.empty(PlanProblem.noRoutines);
        _phase = _Phase.review;
      });
      return;
    }

    final result = await ref.read(aiWorkoutPlanProvider).run(planRequest(
          brief: brief,
          catalogue: catalogue,
          languageName: langs[s.lang] ?? 'English',
        ));

    if (!mounted) return;

    if (result is AiFailure) {
      setState(() {
        _failure = result.kind;
        _phase = _Phase.failed;
      });
      return;
    }

    final draft = sanitizePlanDraft(
      (result as AiDraft).raw,
      lookup: (id) => exdb[id],
      scope: brief.scope,
    );
    setState(() {
      _draft = draft;
      _phase = _Phase.review;
    });
  }

  /// What the app already knows, plus the three things it cannot.
  PlanBrief _brief(AppState s) {
    final goal = switch (goalMode(s.nutrition.goal)) {
      'cut' => 'lose weight',
      'bulk' => 'build muscle',
      _ => 'maintain',
    };
    return PlanBrief(
      scope: _scope,
      daysPerWeek: _days,
      sessionMinutes: _minutes,
      experience: _experience,
      goal: goal,
      age: s.nutrition.profile.age,
      sex: s.nutrition.profile.sex,
      equipment: _equipmentUsed(s),
      note: _note.text,
    );
  }

  /// The equipment this person has actually trained with, read off the log.
  ///
  /// More accurate than asking, and shorter: somebody who has logged two hundred workouts has
  /// already answered the question. Below a handful of distinct kinds it is treated as not enough
  /// evidence — a new profile has logged nothing, and inferring "bodyweight only" from that would
  /// hand back press-ups to somebody standing in a gym.
  Set<String> _equipmentUsed(AppState s) {
    final seen = <String>{};
    for (final w in s.workouts) {
      for (final e in w.entries) {
        final ex = exdb[e.id];
        if (ex != null) seen.add(ex.eq);
      }
    }
    return seen.length >= 3 ? seen : const {};
  }

  /// The equipment set to filter the catalogue by, or null for no filter.
  ///
  /// Only applied for a full-body plan. Narrowing a single muscle group by inferred equipment is
  /// how somebody asking for a biceps day ends up with four cable curls because that is what the
  /// log happens to hold.
  Set<String>? _equipmentFilter(PlanBrief brief) =>
      brief.scope is FullBodyScope && brief.equipment.isNotEmpty ? brief.equipment : null;

  // ---------- saving ----------

  void _save() {
    final draft = _draft!;
    final routines = [for (final r in draft.routines) r.toRoutine()];

    ref.read(appStateProvider.notifier).update((st) {
      // Appended, never replacing: the same choice loadStarterPlan makes, and for the same
      // reason — nobody asked for their existing routines to be deleted.
      st.routines.addAll(routines);
      draft.week.forEach((day, idx) => st.week[day] = routines[idx].id);
    });

    widget.close();
    ref.read(uiProvider).toast(routines.length == 1
        ? t('Routine saved')
        : t('{0} routines saved', routines.length));
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) => switch (_phase) {
        _Phase.brief => _briefForm(context),
        _Phase.thinking => _thinking(context),
        _Phase.review => _review(context),
        _Phase.failed => _failed(context),
      };

  Widget _briefForm(BuildContext context) {
    final c = context.c;
    final label = ref.read(aiWorkoutPlanProvider).label;
    final fullBody = _scope is FullBodyScope;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Draft a routine')),
          // The consent moment, in the flow rather than buried in settings: this is the point at
          // which something leaves the phone. Nothing personal goes with it — the request carries
          // the exercise catalogue and the answers below, not the training log.
          Text(
            t('Your goals go to {0} using your own key, with a list of exercises to choose from. Your training log stays on this phone.',
                label),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 14),
          Section(children: [
            SelectRow<String>(
              icon: 'target',
              iconTint: c.acc,
              title: t('Focus'),
              value: _scopeKey,
              options: _scopeOptions,
              onChanged: (v) => setState(() => _scope = _scopeFor(v)),
            ),
            if (fullBody)
              SelectRow<int>(
                icon: 'calendar',
                iconTint: c.sys.orange,
                title: t('Days a week'),
                value: _days,
                options: [
                  for (var d = 2; d <= 6; d++) SelectOption(d, '$d'),
                ],
                onChanged: (v) => setState(() => _days = v),
              ),
            SelectRow<int>(
              icon: 'timer',
              iconTint: c.sys.purple,
              title: t('Time per session'),
              value: _minutes,
              options: [
                for (final m in [30, 45, 60, 75, 90])
                  SelectOption(m, t('{0} min', m)),
              ],
              onChanged: (v) => setState(() => _minutes = v),
            ),
            SelectRow<String>(
              icon: 'figureStrength',
              iconTint: c.sys.teal,
              title: t('Experience'),
              value: _experience,
              options: [
                SelectOption('new to training', t('New to training')),
                SelectOption('training for a while', t('Training for a while')),
                SelectOption('experienced', t('Experienced')),
              ],
              onChanged: (v) => setState(() => _experience = v),
            ),
          ]),
          Text(t('Anything else? (optional)'), style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 6),
          AppTextField(
            controller: _note,
            placeholder: t('No overhead pressing — sore shoulder'),
            maxLength: 200,
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          AppButton(t('Draft it'),
              icon: 'sparkles', variant: BtnVariant.primary, onTap: _draftPlan),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _thinking(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Drafting')),
        const SizedBox(height: 8),
        // Not a CircularProgressIndicator: nothing in this app is a stock Material widget.
        MacroSplit(macros: (kcal: 1, p: 1, c: 1, f: 1), height: 4),
        const SizedBox(height: 10),
        Text(ref.read(aiWorkoutPlanProvider).label,
            textAlign: TextAlign.center, style: ts(TypeScale.foot, color: c.label3)),
        const SizedBox(height: 14),
        AppButton(t('Cancel'), onTap: widget.close),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final c = context.c;
    final draft = _draft!;

    if (draft.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Nothing usable came back')),
          Text(
            t('Try again, or narrow what you asked for.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 14),
          AppButton(t('Try again'),
              variant: BtnVariant.primary, onTap: () => setState(() => _phase = _Phase.brief)),
          const SizedBox(height: 8),
          AppButton(t('Not now'), onTap: widget.close),
          const SizedBox(height: 8),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(draft.routines.length == 1
              ? t('Your routine')
              : t('Your plan')),
          if (draft.rationale != null) ...[
            Text(draft.rationale!, style: ts(TypeScale.foot, color: c.label2)),
            const SizedBox(height: 12),
          ],
          for (final r in draft.routines) _routineCard(context, draft, r),
          for (final p in draft.problems) ...[
            const SizedBox(height: 2),
            Row(children: [
              AppIcon('info', size: 13, color: c.label3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_problemLine(p), style: ts(TypeScale.cap, color: c.label3)),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          AppButton(
            draft.routines.length == 1 ? t('Save routine') : t('Save plan'),
            icon: 'check',
            variant: BtnVariant.primary,
            onTap: _save,
          ),
          const SizedBox(height: 8),
          AppButton(t('Start over'), onTap: () => setState(() => _phase = _Phase.brief)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _routineCard(BuildContext context, PlanDraft draft, DraftRoutine r) {
    final c = context.c;
    final idx = draft.routines.indexOf(r);
    final days = [
      for (final e in draft.week.entries)
        if (e.value == idx) t(dayn[int.parse(e.key)]),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            GlyphTile(glyphOf(r.emoji)),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.name,
                      style: ts(TypeScale.head, color: c.label, weight: FontWeight.w600)),
                  Text(
                    days.isEmpty
                        ? exCount(r.exercises.length)
                        : '${exCount(r.exercises.length)} · ${days.join(', ')}',
                    style: ts(TypeScale.foot, color: c.label2),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          for (final e in r.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(
                  child: Text(capitalized(e.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(TypeScale.foot, color: c.label)),
                ),
                const SizedBox(width: 8),
                Text('${fmtNum(e.sets)} × ${fmtNum(e.reps)}',
                    style: ts(TypeScale.foot, color: c.label2)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('That did not work')),
        Text(_failureLine(_failure!), style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 14),
        AppButton(t('Try again'),
            variant: BtnVariant.primary, onTap: () => setState(() => _phase = _Phase.brief)),
        const SizedBox(height: 8),
        AppButton(t('Not now'), onTap: widget.close),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------- scope options ----------

  /// The focus picker's value, as a string so one [SelectRow] can carry all three scope kinds.
  String get _scopeKey => switch (_scope) {
        FullBodyScope() => '*',
        BodyPartScope(:final bp) => 'bp:$bp',
        TargetScope(:final tg) => 'tg:$tg',
      };

  PlanScope _scopeFor(String key) {
    if (key == '*') return const PlanScope.fullBody();
    final value = key.substring(3);
    return key.startsWith('bp:') ? PlanScope.bodyPart(value) : PlanScope.target(value);
  }

  /// Whole body, then each body part, then the individual muscles.
  ///
  /// Both levels are offered because people ask at both: "legs" and "hamstrings only" are
  /// different requests, and the dataset carries `bp` and `tg` precisely so it can answer either.
  List<SelectOption<String>> get _scopeOptions => [
        SelectOption('*', t('Whole body'), subtitle: t('A weekly split')),
        for (final bp in exdb.bodyParts)
          if (bp != 'cardio' && bp != 'neck') SelectOption('bp:$bp', capitalized(t(bp))),
        for (final tg in _targets) SelectOption('tg:$tg', capitalized(t(tg))),
      ];

  /// The target muscles worth offering: those with enough exercises behind them to build a
  /// session from. Computed from the dataset rather than listed, so it cannot drift from it.
  static final _targets = () {
    final counts = <String, int>{};
    for (final e in exdb.db) {
      counts[e.tg] = (counts[e.tg] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        if (e.value >= 20 && e.key != 'cardiovascular system') e.key,
    ]..sort();
  }();
}

String _problemLine(PlanProblem p) => switch (p) {
      PlanProblem.unknownExercise =>
        t('Something it suggested is not in the exercise library, and was left out.'),
      PlanProblem.outOfScope => t('Something outside what you asked for was left out.'),
      PlanProblem.duplicate => t('A repeated exercise was kept once.'),
      PlanProblem.clamped => t('Some sets or reps were adjusted to sensible numbers.'),
      PlanProblem.tooMany => t('Only the first exercises were kept.'),
      PlanProblem.badWeek => t('A day could not be scheduled and was left empty.'),
      // Not reached in practice — an empty draft gets its own screen rather than a footnote —
      // but the switch is exhaustive and these two must still say something.
      PlanProblem.noRoutines => t('Nothing usable came back'),
      PlanProblem.unreadable => t('The answer could not be read.'),
    };

String _failureLine(AiFailureKind kind) => switch (kind) {
      AiFailureKind.notConfigured => t('No API key set up yet.'),
      AiFailureKind.offline => t('No connection.'),
      AiFailureKind.badKey => t('That key was refused. Check it in Settings.'),
      AiFailureKind.rateLimited => t('Too many requests just now. Try again in a minute.'),
      AiFailureKind.noCredit => t('The account has no credit. Check billing with the provider.'),
      AiFailureKind.providerDown => t('The provider had a problem.'),
      AiFailureKind.rejected =>
        t('The provider would not accept the request — the model may no longer exist.'),
      AiFailureKind.timeout => t('That took too long.'),
      AiFailureKind.refused => t('The provider would not answer that.'),
      AiFailureKind.cancelled => '',
      AiFailureKind.unreadable => t('The answer could not be read.'),
    };
