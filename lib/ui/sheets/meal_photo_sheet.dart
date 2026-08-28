import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../data/repositories/meal_photo_store.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/meal_photo_draft.dart';
import '../../domain/ai/meal_photo_prompt.dart';
import '../../domain/ai/meal_photo_sanitize.dart';
import '../../domain/foods.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';
import 'nutrition_sheets.dart';
import 'sheet_service.dart';

/// Photograph a meal, check what the app made of it, then log it.
///
/// **Nothing is written before Confirm.** No meal, no state mutation, no file. The photograph
/// produces a draft that lives entirely in this widget's state until the user agrees to it, and
/// Confirm then goes through the ordinary [addMealItem] so a photographed food and a hand-logged
/// one land in the day by exactly the same path.
///
/// That is worth stating plainly, because the obvious future improvement here is a one-tap
/// "just log it" button that skips the review — and the reason not to build it is not obvious
/// from the code. A portion estimated from a single photograph is a guess with a wide error bar:
/// there is no scale reference, the depth of a bowl is invisible, and the fat a thing was cooked
/// in usually is too. As a draft the user corrects, that is genuinely useful. Written straight
/// into the log it would be a fabricated number that every downstream reading — the day's totals,
/// the weekly evolution, the target adjustment — would treat as a record of what was eaten.
/// A plan is an intention; the log is a record.
Future<void> mealPhotoSheet(WidgetRef ref, {required String iso, double? slot}) =>
    showSheet<void>((context, close) =>
        _MealPhotoSheet(iso: iso, slot: slot, close: close));

enum _Phase { intro, thinking, review, failed }

class _MealPhotoSheet extends ConsumerStatefulWidget {
  const _MealPhotoSheet({required this.iso, required this.close, this.slot});

  final String iso;
  final double? slot;
  final void Function([void]) close;

  @override
  ConsumerState<_MealPhotoSheet> createState() => _MealPhotoSheetState();
}

class _MealPhotoSheetState extends ConsumerState<_MealPhotoSheet> {
  _Phase _phase = _Phase.intro;
  Uint8List? _photo;
  MealDraft? _draft;
  List<DraftItem> _items = [];
  AiFailureKind? _failure;

  Future<void> _capture({required bool fromCamera}) async {
    final bytes = await ref.read(photoCaptureProvider).pick(fromCamera: fromCamera);
    // Backing out of the picker is not a failure and must not be reported as one.
    if (bytes == null || !mounted) return;

    setState(() {
      _photo = bytes;
      _phase = _Phase.thinking;
    });

    final s = ref.read(appStateProvider);
    final result = await ref.read(aiMealPhotoProvider).run(mealPhotoRequest(
          jpeg: bytes,
          vocabulary: _vocabulary(),
          customFoods: buildCustomFoods(s.nutrition.foods),
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

    final draft = sanitizeMealGuess((result as AiDraft).raw, lookup: (id) => foods[id]);
    setState(() {
      _draft = draft;
      _items = draft.items;
      // An empty draft is a failure of a different kind, and _failed reads it off the draft
      // itself: "that is not a meal" and "nothing in it matched a food" are different things to
      // be told, and neither is an error the provider caused.
      _phase = draft.isEmpty ? _Phase.failed : _Phase.review;
    });
  }

  /// The photograph, or nothing at all if it will not decode.
  ///
  /// The `errorBuilder` is not defensive padding: `Image.memory` throws asynchronously on bytes it
  /// cannot read, and an uncaught throw out of the image service takes the sheet down — losing a
  /// draft the user has already started correcting, over a *thumbnail*. Absent art collapsing
  /// quietly is the convention `FoodImage` already sets.
  Widget _preview(Uint8List bytes, double height) => ClipRRect(
        borderRadius: BorderRadius.circular(R.md),
        child: Image.memory(
          bytes,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );

  /// Built once per run. Rebuilding four kilobytes of catalogue per photograph is pointless, and
  /// it must be the bundled list in file order — see [buildVocabulary].
  static String? _cachedVocabulary;
  String _vocabulary() => _cachedVocabulary ??= buildVocabulary(foods.db);

  Macros get _totals => (
        kcal: _items.fold<double>(0, (a, i) => a + i.toMealItem().kcal),
        p: _items.fold<double>(0, (a, i) => a + i.toMealItem().p),
        c: _items.fold<double>(0, (a, i) => a + i.toMealItem().c),
        f: _items.fold<double>(0, (a, i) => a + i.toMealItem().f),
      );

  void _confirm() {
    for (final item in _items) {
      // Through addMealItem, never st.meals.add — that is what makes slot merging behave exactly
      // as it does for a food added by hand. logTemplate sets the same precedent and says why.
      addMealItem(ref, iso: widget.iso, slot: widget.slot, item: item.toMealItem());
    }

    // The log is written and the sheet closes on this frame whatever happens to the picture. The
    // file is saved afterwards and attached if it lands: a slow or full disk must not stall a
    // confirm, and a photo that fails to store is a missing thumbnail, not a missing meal.
    final bytes = _photo;
    // `features[…]` rather than `feature(…)`: the latter creates the config on demand, which here
    // would mutate the live state object outside an update() — invisible, unpersisted, and exactly
    // the kind of write this sheet's whole design is about not doing.
    final keep = ref.read(appStateProvider).ai.features[aiMealPhoto]?.keepsPhotos ?? true;
    if (bytes != null && keep) {
      // Read out of the widget's ref *before* closing: these objects live in the container and
      // outlive this sheet, but `ref` itself does not survive the dispose that close() triggers.
      unawaited(_keep(
        bytes,
        ref.read(mealPhotoStoreProvider),
        ref.read(appStateProvider.notifier),
      ));
    }
    widget.close();
  }

  /// Stores the photograph and hangs it on the meal this sheet just wrote into.
  Future<void> _keep(
    Uint8List bytes,
    MealPhotoStore store,
    AppStateController notifier,
  ) async {
    final name = await store.save(bytes);
    if (name == null) return;

    String? superseded;
    notifier.update((st) {
      // The same (day, slot) addMealItem just merged into, found the same way it finds it.
      final meal = st.meals.where((m) => m.d == widget.iso && m.slot == widget.slot).firstOrNull;
      if (meal == null) return;
      // A slot photographed twice keeps the *latest* picture: it is the one the user was looking
      // at while they confirmed, and showing them a different, older plate on the meal they just
      // logged would read as a bug. The one it replaces is deleted rather than left for the boot
      // sweep to find.
      superseded = meal.photo;
      meal.photo = name;
    });

    if (superseded != null) await store.delete(superseded!);
  }

  @override
  Widget build(BuildContext context) => switch (_phase) {
        _Phase.intro => _intro(context),
        _Phase.thinking => _thinking(context),
        _Phase.review => _review(context),
        _Phase.failed => _failed(context),
      };

  // ---------- intro ----------

  Widget _intro(BuildContext context) {
    final c = context.c;
    final label = ref.read(aiMealPhotoProvider).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Log from a photo')),
        // The consent moment, and it belongs in the flow rather than buried in settings: this is
        // the point at which something is about to leave the phone.
        Text(
          t('The photo goes to {0} using your own key. Nothing else leaves the phone, and you check every number before anything is logged.',
              label),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 14),
        AppButton(t('Take a photo'),
            icon: 'sparkles',
            variant: BtnVariant.primary,
            onTap: () => _capture(fromCamera: true)),
        const SizedBox(height: 8),
        AppButton(t('Choose from library'), onTap: () => _capture(fromCamera: false)),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------- thinking ----------

  Widget _thinking(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Reading the photo')),
        if (_photo != null) _preview(_photo!, 160),
        const SizedBox(height: 14),
        // Not a CircularProgressIndicator: nothing in this app is a stock Material widget.
        const _ThinkingBar(),
        const SizedBox(height: 10),
        Text(t('Analyzing your photo…'),
            textAlign: TextAlign.center, style: ts(TypeScale.head, color: c.label)),
        const SizedBox(height: 2),
        Text(ref.read(aiMealPhotoProvider).label,
            textAlign: TextAlign.center, style: ts(TypeScale.foot, color: c.label3)),
        const SizedBox(height: 14),
        AppButton(t('Cancel'), onTap: widget.close),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------- review ----------

  Widget _review(BuildContext context) {
    final c = context.c;
    final draft = _draft!;
    final totals = _totals;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Check what you ate')),
          if (_photo != null) _preview(_photo!, 130),
          const SizedBox(height: 12),

          // The headline is a band, not a figure. A single number would imply a measurement, and
          // a photograph is not one.
          Text('${totals.kcal.round()} ${t('kcal')}',
              style: ts(TypeScale.title2, color: c.label, size: 26, weight: FontWeight.w700)),
          Text(
            t('somewhere between {0} and {1}',
                draft.kcalLow.round().toString(), draft.kcalHigh.round().toString()),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 10),
          MacroSplit(macros: totals),
          const SizedBox(height: 6),
          MacroLegend(macros: totals),

          if (draft.problems.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final p in draft.problems)
              Text('· ${_problemLine(p)}', style: ts(TypeScale.foot, color: c.label3)),
          ],

          const SizedBox(height: 12),
          for (var i = 0; i < _items.length; i++) _row(context, i),

          const SizedBox(height: 6),
          AppButton(t('Add something it missed'), icon: 'plus', onTap: () {
            logMealSheet(ref, onPicked: (item) {
              // Arrives as a MealItem from the ordinary picker; wrap it so the review list stays
              // one kind of thing.
              setState(() => _items = [..._items, _fromPicked(item)]);
            });
          }),
          const SizedBox(height: 8),
          AppButton(
            t('Log this meal'),
            variant: BtnVariant.primary,
            enabled: _items.isNotEmpty,
            onTap: _confirm,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final c = context.c;
    final item = _items[index];
    final macros = item.toMealItem();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoodThumb(food: item.food ?? foods.or(''), size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The catalogue name leads, because that is where the macros actually come from.
                Text(item.food == null ? item.name : t(item.food!.n),
                    style: ts(TypeScale.body, color: c.label)),
                // ...and the model's own name is kept when it differs, which is the only way to
                // catch a plausible-but-wrong match. "Salmon" resolved against a sardine record
                // looks perfectly fine if you only ever show one of the two.
                if (_saidDifferently(item))
                  Text(t('seen as {0}', item.name),
                      style: ts(TypeScale.foot, color: c.label3)),
                Text('${macros.kcal.round()} ${t('kcal')}',
                    style: ts(TypeScale.foot, color: c.label2)),
                // Three taps for the whole range. The cheapest honest expression of uncertainty:
                // the spread is visible rather than hidden behind one number, and correcting it
                // costs one tap. Same shape foodDetailSheet uses for household portions.
                if (item.gramsLow < item.gramsHigh) ...[
                  const SizedBox(height: 4),
                  ChipRow(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final g in {item.gramsLow, item.grams, item.gramsHigh})
                        AppChip(
                          '${g.round()} ${t('g')}',
                          selected: (g - item.grams).abs() < 0.5,
                          capitalize: false,
                          onTap: () => setState(() => _items[index] = item.copyWith(grams: g)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: NumberBox(
              value: item.grams,
              decimal: false,
              suffix: t('g'),
              max: 2000,
              onChanged: (v) =>
                  setState(() => _items[index] = item.copyWith(grams: v ?? item.grams)),
            ),
          ),
          Pressable(
            onTap: () => setState(() => _items = [..._items]..removeAt(index)),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: AppIcon('xmark', size: 15, color: c.label3),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- failed ----------

  Widget _failed(BuildContext context) {
    final c = context.c;
    final draft = _draft;
    final message = draft != null && draft.has(DraftProblem.notFood)
        ? t('That does not look like a meal.')
        : draft != null && draft.isEmpty
            ? t('Nothing in that photo matched a food.')
            : _failureLine(_failure ?? AiFailureKind.unreadable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('That did not work')),
        Text(message, style: ts(TypeScale.body, color: c.label2)),
        const SizedBox(height: 14),
        AppButton(t('Try again'), onTap: () => setState(() {
              _phase = _Phase.intro;
              _draft = null;
              _failure = null;
              _photo = null;
            })),
        const SizedBox(height: 8),
        // There is deliberately no dead end anywhere in this sheet. Whatever went wrong, the food
        // still got eaten and the day still has to add up.
        AppButton(t('Log it by hand'), variant: BtnVariant.primary, onTap: () {
          widget.close();
          logMealSheet(ref, iso: widget.iso, slot: widget.slot);
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A bar of light sweeping across a track, in place of a spinner.
///
/// The request has no progress to report — one HTTP round trip, done or not — so this promises
/// motion, not a percentage. Same track shape as [MacroSplit] since it sits in that widget's
/// spot, but this one has to drive its own animation rather than read one from data.
class _ThinkingBar extends StatefulWidget {
  const _ThinkingBar();

  @override
  State<_ThinkingBar> createState() => _ThinkingBarState();
}

class _ThinkingBarState extends State<_ThinkingBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const sweep = .32;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: ColoredBox(
          color: c.surface3,
          child: LayoutBuilder(
            builder: (context, box) => AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = Motion.ease.transform(_c.value);
                final w = box.maxWidth * sweep;
                final x = (box.maxWidth + w) * v - w;
                return Transform.translate(
                  offset: Offset(x, 0),
                  child: SizedBox(width: w, child: ColoredBox(color: c.acc)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the model's own name for a catalogue hit is worth showing beside the catalogue's.
///
/// Only for a resolved food — a free-form item's name is already the only one there is. The
/// containment check keeps the common, uninteresting case quiet: "Chicken" against "Chicken
/// breast" is the same food described more loosely, and repeating it on every row would turn the
/// signal into noise.
bool _saidDifferently(DraftItem item) {
  final food = item.food;
  if (food == null || item.name.isEmpty) return false;
  final said = item.name.toLowerCase();
  final known = food.n.toLowerCase();
  return !known.contains(said) && !said.contains(known);
}

/// A food chosen through the ordinary picker, as something the review list can hold.
DraftItem _fromPicked(MealItem item) {
  final food = foods[item.fid];
  // 100 g when the picker handed back a quick-add, which carries no weight at all.
  final g = item.g > 0 ? item.g : 100.0;
  return DraftItem(
    name: item.n ?? food?.n ?? '',
    grams: g,
    // No range: the user picked this one and said how much. Inventing an error bar around a
    // number somebody typed would be the app manufacturing doubt it does not have.
    gramsLow: g,
    gramsHigh: g,
    food: food,
    per100: food != null
        ? null
        : (
            kcal: item.g > 0 ? item.kcal / item.g * 100 : item.kcal.toDouble(),
            p: item.g > 0 ? item.p / item.g * 100 : item.p.toDouble(),
            c: item.g > 0 ? item.c / item.g * 100 : item.c.toDouble(),
            f: item.g > 0 ? item.f / item.g * 100 : item.f.toDouble(),
          ),
  );
}

String _problemLine(DraftProblem p) => switch (p) {
      DraftProblem.unknownFid => t('Some foods were not in the catalogue.'),
      DraftProblem.gramsClamped => t('A portion looked implausible and was capped.'),
      DraftProblem.kcalRecomputed => t('Calories were recalculated from the macros.'),
      DraftProblem.noMacros => t('Something could not be identified and was left out.'),
      DraftProblem.tooManyItems => t('Only the largest items were kept.'),
      DraftProblem.notFood => t('That does not look like a meal.'),
      DraftProblem.noItems => t('Nothing in that photo matched a food.'),
      DraftProblem.unreadable => t('The answer could not be read.'),
    };

String _failureLine(AiFailureKind kind) => switch (kind) {
      AiFailureKind.notConfigured => t('No API key set up yet.'),
      AiFailureKind.offline => t('No connection. Log it by hand — the numbers are the same.'),
      AiFailureKind.badKey => t('That key was refused. Check it in Settings.'),
      AiFailureKind.rateLimited => t('Too many requests just now. Try again in a minute.'),
      AiFailureKind.providerDown => t('The provider had a problem.'),
      AiFailureKind.rejected =>
        t('The provider would not accept the request — the model may no longer exist.'),
      AiFailureKind.timeout => t('That took too long.'),
      AiFailureKind.refused => t('The provider would not read that photo.'),
      AiFailureKind.cancelled => '',
      AiFailureKind.unreadable => t('The answer could not be read.'),
    };
