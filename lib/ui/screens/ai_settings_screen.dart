import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../data/repositories/meal_photo_store.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/i18n.dart';
import '../../state/ai_provider.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/page.dart';

/// Where the user points a feature at a provider, and the only screen in the app that accepts a
/// secret.
///
/// Two rules run through everything here. **A stored key is never rendered back** — not in the
/// field, not in a subtitle, not truncated as a "sk-ant-…abc" reassurance, because a shoulder or
/// a screenshot is exactly how a key gets copied. And **the price is stated before the spend**:
/// every other feature in this app is free forever, so a feature that quietly bills the user's
/// own account has to say what it costs where they turn it on, not in a README.
class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final configured = ref.watch(aiConfiguredProvider).value ?? const <String>{};

    final cfg = s.ai.features[aiMealPhoto] ?? AiFeatureConfig();
    // Only a provider that actually holds a key can be chosen. Offering the others would build a
    // setting that looks complete and fails on first use.
    final usable = [for (final p in aiProviders) if (configured.contains(p)) p];
    final chosen = cfg.provider != null && usable.contains(cfg.provider) ? cfg.provider : null;

    return AppPage(
      children: [
        PageHeader(
          title: t('AI features'),
          leading: IconButtonRound('chevronLeft', onTap: () => context.go('/settings')),
        ),

        // ---------- what this actually does ----------
        Section(title: t('How this works'), children: [
          AppRow(
            icon: 'lock',
            iconTint: c.acc,
            title: t('Your key, your account, your bill'),
            subtitle: t(
                'This app runs no server. A meal photo goes straight from your phone to the provider you pick, using the key you enter here, and only when you take one. Nothing else ever leaves.'),
          ),
        ]),

        // ---------- keys ----------
        Section(
          title: t('Providers'),
          footer: [
            t('Keys are kept in the phone keychain — never in your backup file.'),
            // Said here because the button is here, for the same reason the per-photo price is
            // said next to the model picker: this app does not spend the user's money without
            // telling them the moment before it does.
            if (configured.isNotEmpty)
              t('Testing sends one tiny request to the provider and costs a fraction of a cent.'),
          ].join(' '),
          children: [
            for (final id in aiProviders)
              _KeyRow(providerId: id, isSet: configured.contains(id), cfg: cfg),
          ],
        ),

        // ---------- the feature ----------
        Section(
          title: t(aiFeatureName[aiMealPhoto]!),
          footer: [
            t('Photograph a plate and the app drafts what is on it. Portion sizes are estimates — you check every number before anything is logged.'),
            // Said where the switch is, not in a README. The two things a user cannot guess about
            // a photo the app keeps are how long it keeps it and whether it travels with a backup.
            if (cfg.isOn)
              t('Photos stay on this phone for {0} days, then delete themselves. They are never part of your backup.',
                  mealPhotoRetention.inDays),
          ].join(' '),
          children: [
            AppRow(
              icon: 'sparkles',
              iconTint: c.sys.orange,
              title: t('Log a meal from a photo'),
              subtitle: usable.isEmpty ? t('Add a key above first') : null,
              trailing: AppSwitch(
                value: cfg.isOn,
                enabled: usable.isNotEmpty,
                onChanged: (v) => notifier.update((st) {
                  final f = st.ai.feature(aiMealPhoto);
                  // false rather than null when switched off: an explicit "no" has to stay
                  // distinguishable from never having chosen, the same way `effort` does.
                  f.on = v;
                  // Turning on with no provider chosen yet defaults to the one usable provider —
                  // otherwise the Provider row below displays it as already selected (see its own
                  // comment) while `f.provider` stays null, and the feature never actually turns
                  // on: `aiMealPhotoProvider` gates on a real provider id, not on what the row
                  // happens to be showing.
                  if (v && f.provider == null && usable.isNotEmpty) f.provider = usable.first;
                }),
              ),
            ),
            if (usable.isNotEmpty)
              SelectRow<String>(
                icon: 'globe',
                iconTint: c.sys.blue,
                title: t('Provider'),
                value: chosen ?? usable.first,
                options: [
                  for (final p in usable) SelectOption(p, aiProviderName[p] ?? p),
                ],
                // Only which provider runs the feature — the model for each one lives on that
                // provider's own row below now, so switching back and forth here no longer means
                // re-picking it every time.
                onChanged: (v) => notifier.update((st) => st.ai.feature(aiMealPhoto).provider = v),
              ),
            if (cfg.isOn) _keepPhotosRow(context, ref, s, cfg),
          ],
        ),

        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          child: Text(
            t('Prices are the provider\'s and change — treat the per-photo figures as a rough guide.'),
            textAlign: TextAlign.center,
            style: ts(TypeScale.foot, color: c.label3),
          ),
        ),
      ],
    );
  }

  /// Whether the photograph survives the meal being logged.
  ///
  /// The count is read off the log rather than by measuring the directory, so it cannot disagree
  /// with what the user can see on their own days — and switching this off is not a separate
  /// delete-everything button, it is the ordinary sweep with an empty keep set. One code path, so
  /// there is no second one to fall out of step with the first.
  Widget _keepPhotosRow(
      BuildContext context, WidgetRef ref, AppState s, AiFeatureConfig cfg) {
    final stored = s.meals.where((m) => m.photo != null).length;
    return AppRow(
      icon: 'meal',
      iconTint: context.c.sys.green,
      title: t('Keep the photo'),
      subtitle: cfg.keepsPhotos && stored > 0 ? t('{0} on this phone', stored) : null,
      trailing: AppSwitch(
        value: cfg.keepsPhotos,
        onChanged: (v) async {
          final notifier = ref.read(appStateProvider.notifier);
          // Written explicitly either way. A null here would read as "never chosen", which this
          // field takes as yes — so switching off would not stay off.
          notifier.update((st) => st.ai.feature(aiMealPhoto).keepPhotos = v);
          // Off deletes what is already stored, now rather than at the next launch. A setting that
          // only stops *new* photos would leave the ones the user just asked to be rid of sitting
          // on the disk until they happened to restart the app.
          if (!v) await notifier.sweepPhotos();
        },
      ),
    );
  }
}

/// One provider's key: set it, replace it, or clear it — but never read it back. Once it is set,
/// this is also where that provider's own model lives, and where its connection can be tested.
class _KeyRow extends ConsumerStatefulWidget {
  const _KeyRow({required this.providerId, required this.isSet, required this.cfg});

  final String providerId;
  final bool isSet;

  /// The whole feature's config, not just this provider's slice of it — the Model picker below
  /// needs [AiFeatureConfig.models], and `_save` needs to check whether *any* provider has been
  /// chosen yet, not only this one.
  final AiFeatureConfig cfg;

  @override
  ConsumerState<_KeyRow> createState() => _KeyRowState();
}

class _KeyRowState extends ConsumerState<_KeyRow> {
  final _field = TextEditingController();
  bool _editing = false;

  /// Whether a test is in flight, and what the last one said.
  ///
  /// [_tested] distinguishes "not tried" from "tried and it worked", which a nullable
  /// [AiFailureKind] on its own cannot: null is the success value.
  bool _testing = false;
  bool _tested = false;
  AiFailureKind? _result;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final typed = _field.text.trim();
    if (typed.isEmpty) return;
    await ref.read(aiKeyStoreProvider).write(widget.providerId, typed);
    // Cleared immediately, not on the next rebuild: a controller holding the key keeps it in
    // memory and puts it one screenshot away for as long as this screen is alive.
    _field.clear();
    if (!mounted) return;
    // A verdict on the key that was just replaced says nothing about the one that replaced it.
    setState(() {
      _editing = false;
      _tested = false;
      _result = null;
    });
    ref.invalidate(aiConfiguredProvider);
    // The key just added is what makes this row usable at all, so if the feature has never had a
    // provider — nothing chosen yet, or this is the first key ever added — this is the natural
    // moment to default it, rather than leaving the Provider row on screen quietly displaying a
    // choice (see its own comment) that `AppState` was never actually given.
    final notifier = ref.read(appStateProvider.notifier);
    if (widget.cfg.provider == null) {
      notifier.update((st) => st.ai.feature(aiMealPhoto).provider = widget.providerId);
    }
    ref.read(uiProvider).toast(t('Key saved'));
  }

  /// Sends one real request against the key already saved for this provider, and reports whether
  /// it was accepted.
  ///
  /// Deliberately not a toast: the answer is a sentence about this row, it wants to stay on screen
  /// while the user acts on it, and a toast for the failure case would be gone before they had
  /// finished reading which of the three providers it was about.
  Future<void> _test() => _runTest(() => ref.read(aiProbeProvider)(widget.providerId));

  /// The other way in: tests whatever is currently typed in the field, without saving it first.
  /// A no-op on an empty field, the same as [_save].
  Future<void> _testTyped() {
    final typed = _field.text.trim();
    if (typed.isEmpty) return Future.value();
    return _runTest(() => ref.read(aiProbeKeyProvider)(widget.providerId, typed));
  }

  Future<void> _runTest(Future<AiFailureKind?> Function() probe) async {
    setState(() {
      _testing = true;
      _tested = false;
      _result = null;
    });
    final kind = await probe();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _tested = true;
      _result = kind;
    });
  }

  Future<void> _clear() async {
    await ref.read(aiKeyStoreProvider).write(widget.providerId, null);
    if (!mounted) return;
    // Turn the feature off too if this was the provider running it, rather than leaving a switch
    // on that now points at nothing.
    final notifier = ref.read(appStateProvider.notifier);
    notifier.update((st) {
      final f = st.ai.feature(aiMealPhoto);
      // The model chosen for this provider is meaningless once there is no key behind it — left
      // in place it would just be a stale default the next key typed here quietly inherits.
      f.models.remove(widget.providerId);
      if (f.provider == widget.providerId) {
        f.provider = null;
        f.on = false;
      }
    });
    setState(() {
      _editing = false;
      _tested = false;
      _result = null;
    });
    ref.invalidate(aiConfiguredProvider);
    ref.read(uiProvider).toast(t('Key removed'));
  }

  /// What a finished test says, independent of where it is shown.
  String _resultLine(AiFailureKind? kind) {
    if (kind == null) return t('The key works.');
    return switch (kind) {
      AiFailureKind.notConfigured => t('No API key set up yet.'),
      AiFailureKind.badKey => t('That key was refused.'),
      AiFailureKind.offline => t('No connection.'),
      AiFailureKind.rateLimited => t('Too many requests just now. Try again in a minute.'),
      AiFailureKind.providerDown => t('The provider had a problem.'),
      AiFailureKind.rejected =>
        t('The provider would not accept the request — the model may no longer exist.'),
      AiFailureKind.timeout => t('That took too long.'),
      // Neither is reachable from a probe, which reads a status code and never a body — but an
      // exhaustive switch is what makes a future kind a compile error rather than a blank line.
      AiFailureKind.refused || AiFailureKind.unreadable => t('The provider had a problem.'),
      AiFailureKind.cancelled => '',
    };
  }

  /// The line under a set key: what the last test said, or where the key lives.
  ///
  /// The two share a line because they answer the same question — "is this row all right?" — and
  /// stacking them would leave a permanent reassurance sitting under a verdict that contradicts it.
  /// [saved] is false for the row this same state also drives while editing — an untested,
  /// unsaved key has nothing honest to say about the keychain yet, so that idle state renders
  /// nothing rather than a reassurance about a key that was never stored.
  (String, Color) _footnote(AppColors c, {required bool saved}) {
    if (_testing) return (t('Testing…'), c.label3);
    if (!_tested) {
      return saved
          ? (t('Stored in the phone keychain. It is not in your backup.'), c.label3)
          : ('', c.label3);
    }
    final kind = _result;
    return (_resultLine(kind), kind == null ? c.sys.green : c.sys.red);
  }

  /// The model picker for this specific provider, once it holds a key — independent of whether
  /// this is the provider currently running the feature. Moved here from a single shared row so
  /// that switching which provider is active no longer means re-choosing every other one's model
  /// from scratch.
  Widget? _modelRow(BuildContext context) {
    final table = aiModels[widget.providerId];
    if (table == null || table.isEmpty) return null;
    final current = modelFor(widget.providerId, widget.cfg.models[widget.providerId])!;
    return SelectRow<String>(
      icon: 'sparkles',
      iconTint: context.c.sys.purple,
      title: t('Model'),
      value: current.id,
      options: [
        for (final m in table)
          // The cost sits in the subtitle rather than a footnote because this is the moment the
          // choice is made, and it is the only number on this screen that recurs.
          SelectOption(m.id, m.label, subtitle: t('about {0} a photo', _money(m.perPhoto))),
      ],
      onChanged: (v) => ref
          .read(appStateProvider.notifier)
          .update((st) => st.ai.feature(aiMealPhoto).models[widget.providerId] = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = aiProviderName[widget.providerId] ?? widget.providerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppRow(
          title: name,
          // A fixed mask, not a prefix of the real key. "sk-ant-…9f2" is friendlier and is also
          // three characters of a secret rendered on screen for no reason.
          subtitle: widget.isSet ? '••••••••••••' : t('Not set'),
          trailing: AppButton(
            _editing ? t('Cancel') : (widget.isSet ? t('Replace') : t('Add')),
            size: BtnSize.xs,
            variant: BtnVariant.tinted,
            onTap: () => setState(() {
              _editing = !_editing;
              _field.clear();
              // A verdict belongs to whichever key produced it — entering edit mode retires the
              // last saved-key test, and cancelling out retires whatever was just typed, so
              // neither leaks into the other row's reading.
              _tested = false;
              _result = null;
            }),
          ),
        ),
        if (_editing) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _field,
                  placeholder: t('Paste your {0} API key', name),
                  obscureText: true,
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: AppButton(t('Save'),
                        size: BtnSize.sm, variant: BtnVariant.primary, onTap: _save),
                  ),
                  if (widget.isSet) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(t('Remove'),
                          size: BtnSize.sm, variant: BtnVariant.danger, onTap: _clear),
                    ),
                  ],
                ]),
                // Testing a key that has not been saved yet — the whole reason to try it before
                // committing to it. Goes through the same seam as every other request (rule 1 and
                // rule 3 in vision_adapter.dart still hold: nothing thrown, no body surfaced) but
                // with a throwaway in-memory store standing in for the keychain, so a failed
                // attempt never touches it.
                Builder(builder: (context) {
                  final (line, tint) = _footnote(context.c, saved: false);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(line, style: ts(TypeScale.foot, color: tint))),
                        const SizedBox(width: 10),
                        AppButton(
                          t('Test'),
                          size: BtnSize.xs,
                          variant: BtnVariant.tinted,
                          enabled: !_testing,
                          onTap: _testTyped,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        if (!_editing && widget.isSet) ...[
          if (_modelRow(context) case final row?)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
              child: row,
            ),
          Builder(builder: (context) {
            final (line, tint) = _footnote(context.c, saved: true);
            return Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
              child: Row(
                children: [
                  Expanded(child: Text(line, style: ts(TypeScale.foot, color: tint))),
                  const SizedBox(width: 10),
                  // Beside the verdict rather than under it: this is the button that produced the
                  // sentence to its left, and pressing it again is how the sentence changes.
                  AppButton(
                    t('Test'),
                    size: BtnSize.xs,
                    variant: BtnVariant.tinted,
                    enabled: !_testing,
                    onTap: _test,
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// '$0.02', or '<$0.01' for anything that would round to nothing.
///
/// Not localised. A currency figure that guessed at the user's locale would be worse than an
/// honest dollar sign: the providers bill in USD whatever the phone's language is.
String _money(double dollars) =>
    dollars < 0.01 ? '<\$0.01' : '\$${dollars.toStringAsFixed(2)}';
