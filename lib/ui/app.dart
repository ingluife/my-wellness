import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/i18n.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostPhoto());
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

    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) => _shell(context, ref, ui, active),
    );
  }

  Widget _shell(BuildContext context, WidgetRef ref, UiController ui, bool active) {
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
              onTap: (route) => appNavigatorKey.currentContext?.go(route),
              onStart: () => _start(context, ref, active),
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
  void _start(BuildContext context, WidgetRef ref, bool running) {
    if (!running) {
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
