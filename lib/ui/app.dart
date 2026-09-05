import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/i18n.dart';
import '../platform/workout_notification.dart';
import '../state/active_session.dart';
import '../state/ai_provider.dart';
import '../state/app_state_provider.dart';
import '../state/ui_provider.dart';
import 'router.dart';
import 'theme/app_colors.dart';
import 'sheets/meal_photo_sheet.dart';
import 'sheets/sheet_service.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/rest_timer.dart';
import 'widgets/tab_bar.dart';
import 'sheets/workout_flow.dart';
import 'widgets/toast.dart';

/// The UI controller is a plain [ChangeNotifier] behind a Riverpod [Provider]: it is
/// imperative by nature (start a timer, show a toast) and nothing about it belongs in the
/// persisted state. Widgets that need to repaint on it listen with a [ListenableBuilder].
final uiProvider = Provider<UiController>((ref) {
  final ui = UiController();
  ref.onDispose(ui.dispose);
  return ui;
});

/// The active-session mutator, wired to the same two stores every widget already reads and
/// writes through. Lives beside [uiProvider] because it needs both: [appStateProvider] for the
/// mutation and [uiProvider] for the rest-timer and sound side effects `toggle` triggers.
final activeSessionProvider = Provider<ActiveSession>((ref) => ActiveSession(
      read: () => ref.read(appStateProvider),
      update: ref.read(appStateProvider.notifier).update,
      ui: ref.read(uiProvider),
    ));

/// The app.
///
/// Theme and language are read straight out of the profile, so switching either repaints
/// everything without a restart — the same thing the original does by re-rendering the whole
/// shell when `data-theme`, `data-accent` or the language pack changes.
class MyWellnessApp extends ConsumerStatefulWidget {
  const MyWellnessApp({super.key});

  @override
  ConsumerState<MyWellnessApp> createState() => _MyWellnessAppState();
}

class _MyWellnessAppState extends ConsumerState<MyWellnessApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    I18n.instance.addListener(_onLanguageChanged);
    // Covers a cold start after the OS killed the app mid-picker: the first `resumed` callback
    // is not guaranteed to fire, but the first frame always does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverLostPhoto();
      _checkDeferredWorkoutSheets();
    });

    // Wires the quick-action notification to the one ActiveSession and UiController the rest of
    // the app already reads and writes through, then draws it once for a session that was
    // already running when the app (re)opened — the service does not survive the OS killing the
    // app, the state does.
    WorkoutNotification.instance
        .bind(ref.read(activeSessionProvider), ref.read(uiProvider), () => ref.read(appStateProvider));
    unawaited(WorkoutNotification.instance.sync(ref.read(appStateProvider)));
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLanguageChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Strings are read through `t()` at build time rather than held in widgets, so a language
  /// change is a repaint of the whole tree and nothing else.
  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Often the last thing before the OS kills the app: get the file mirror written.
      ref.read(appStateProvider.notifier).flush();
    }
    if (state == AppLifecycleState.resumed) {
      ref.read(uiProvider).resync(soundOn: ref.read(appStateProvider).sound);
      _recoverLostPhoto();
      _checkDeferredWorkoutSheets();
    }
  }

  /// The id of the active workout the finish prompt was already offered for, so resuming with
  /// nothing new to report does not put it back up. Kept here rather than on [ActiveWorkout]
  /// because it means nothing once this run of the app ends — the next launch checks fresh.
  String? _completeOfferedFor;

  /// The quick-action notification can finish a set — even a whole exercise — with nobody
  /// around to show the sheet that follows: `ActiveSession.toggle` reports `askTopWeight` and
  /// `workoutDone` the same way it does for an in-app tap, but there is no `_SetRow` on screen
  /// to act on them. This is where that catches up, on cold start and on every resume.
  ///
  /// Mirrors `_SetRow._toggle`'s own dispatch: the top-weight sheet first, since confirming it
  /// chains into the finish prompt itself when it closes the last unit — see `_TopWeightState`.
  void _checkDeferredWorkoutSheets() {
    final s = ref.read(appStateProvider);
    final a = s.active;
    if (a == null) {
      _completeOfferedFor = null;
      return;
    }

    for (var i = 0; i < a.entries.length; i++) {
      final e = a.entries[i];
      if (e.sets.isEmpty || !e.sets.every((x) => x.done)) continue;
      final loaded = modeOf(e.cfg) == 'reps' && !(isBw(e.cfg) && !e.sets.any((x) => (x.w ?? 0) > 0));
      if (loaded && !e.asked) {
        ref.read(appStateProvider.notifier).update((st) => st.active!.entries[i].asked = true);
        topWeightSheet(ref, i);
        return;
      }
    }

    final allDone = a.entries.isNotEmpty && a.entries.every((e) => e.sets.every((x) => x.done));
    if (allDone && _completeOfferedFor != a.id) {
      _completeOfferedFor = a.id;
      workoutCompleteSheet(ref);
    }
  }

  /// A meal photo taken right as Android reclaims memory can outlive the process that was
  /// waiting for it: the camera still has the picture, but the pending `pickImage` future — and
  /// the review sheet that was going to show it — died with the app. Every resume checks for
  /// one, so the photo is not silently lost. It lands on today, unslotted: the sheet that knew
  /// which day and slot it was headed for did not survive to say.
  void _recoverLostPhoto() {
    unawaited(ref.read(photoCaptureProvider).recoverLost().then((bytes) {
      if (bytes != null && mounted) {
        mealPhotoSheet(ref, iso: todayISO(), initialBytes: bytes);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appStateProvider.select((s) => s.theme));
    final accent = ref.watch(appStateProvider.select((s) => s.accent));
    final lang = ref.watch(appStateProvider.select((s) => s.lang));

    // Applying it here rather than in a listener keeps the language and the frame that uses
    // it in step; setLang no-ops when nothing changed.
    if (I18n.instance.lang != lang) I18n.instance.setLang(lang);

    return MaterialApp.router(
      title: 'My Wellness',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        theme == 'light' ? Brightness.light : Brightness.dark,
        accentFrom(accent),
      ),
      routerConfig: _router,
    );
  }
}

/// Everything that sits above the current screen: the tab bar, the timer bar and the toast.
///
/// They live outside the router so they survive navigation — checking Stats mid-rest must not
/// stop the countdown, and the tab bar is always the way out of a screen that went wrong.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;

  /// The current path, handed down by the app rather than looked up here. See the comment on
  /// the builder that supplies it.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiProvider);
    final active = ref.watch(appStateProvider.select((s) => s.active != null));
    // Today already trained, nothing running: the Start disc becomes a "Done" marker rather
    // than a button that would quietly start a second session.
    final doneToday = ref.watch(appStateProvider
        .select((s) => s.active == null && s.workouts.any((w) => w.d == todayISO())));

    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) => _shell(context, ref, ui, active, doneToday),
    );
  }

  Widget _shell(
      BuildContext context, WidgetRef ref, UiController ui, bool active, bool doneToday) {
    final timerShowing = ui.timer != null;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // A Material ancestor, and the page's own background in one: text fields and anything else
    // that expects to be "printed on material" needs it, and the app paints its own ground
    // rather than inheriting Material's default surface.
    return Material(
      color: context.c.bg,
      child: Stack(
        children: [
          // The page scrolls clear of the bar, and further while a timer floats above it.
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.paddingOf(context)
                  .copyWith(bottom: (timerShowing ? 250 : 128) + bottomInset),
            ),
            child: child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppTabBar(
              current: _tabKey,
              workoutRunning: active,
              todayComplete: doneToday,
              onTap: (route) => appNavigatorKey.currentContext?.go(route),
              onStart: () => _start(context, ref, active, doneToday),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 88 + bottomInset,
            child: RestTimerBar(ui: ui),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 96 + bottomInset,
            child: AppToast(message: ui.toastMessage),
          ),
        ],
      ),
    );
  }

  /// The Start button starts today's session directly when there is one to start, and only
  /// falls back to the chooser when there is not — the fewest taps between opening the app and
  /// logging a set.
  void _start(BuildContext context, WidgetRef ref, bool running, bool complete) {
    // Once today is done, tapping the disc goes to the workout screen rather than auto-starting
    // a fresh session — a second workout is still possible, just not on a single stray tap.
    if (!running && !complete) {
      final s = ref.read(appStateProvider);
      final r = effectiveRoutine(s, todayISO());
      if (r != null && r.ex.isNotEmpty) {
        startFlow(ref, r.id);
        return;
      }
    }
    appNavigatorKey.currentContext?.go('/workout');
  }

  /// The first path segment — 'nutrition' for `/nutrition/foods` as well as for `/nutrition`,
  /// which is what lets a tab stay lit across its own child screens.
  String get _tabKey {
    final seg = location.split('/').where((s) => s.isNotEmpty);
    return seg.isEmpty ? 'home' : seg.first;
  }
}
