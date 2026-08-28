import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/ai_settings_screen.dart';
import 'screens/appearance_settings_screen.dart';
import 'screens/data_settings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/nutrition_screen.dart';
import 'screens/food_library_screen.dart';
import 'screens/library_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/routine_edit_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/workout_screen.dart';
import 'screens/workout_settings_screen.dart';
import 'sheets/sheet_service.dart';
import 'theme/tokens.dart';
import 'app.dart';

/// The same routes the original's hash router serves, so a deep link, a back gesture and the
/// tab bar all land in the same places they do there.
GoRouter buildRouter() => GoRouter(
      navigatorKey: appNavigatorKey,
      initialLocation: '/home',
      routes: [
        // Everything lives inside the shell, and the shell lives inside the router.
        //
        // It used to wrap the router from `MaterialApp.router`'s `builder` instead, which put it
        // *above* the `InheritedGoRouter` the router provides to its own subtree: the shell's
        // `GoRouter.maybeOf(context)` returned null on every route, so the tab bar was told it
        // was on '/home' for the whole life of the app and no tab but Home ever lit up. A
        // ShellRoute hands it the location as an argument, from inside, on every navigation.
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            _page('/login', (_, _) => const LoginScreen()),
            _page('/home', (_, _) => const HomeScreen()),
            _page('/plan', (_, _) => const PlanScreen()),
            _page('/plan/r/:id', (_, s) => RoutineEditScreen(id: s.pathParameters['id']!)),
            _page('/workout', (_, _) => const WorkoutScreen()),
            _page('/nutrition', (_, _) => const NutritionScreen()),
            _page('/nutrition/foods', (_, _) => const FoodLibraryScreen()),
            _page('/nutrition/recipes', (_, _) => const RecipesScreen()),
            _page('/stats', (_, _) => const StatsScreen()),
            _page('/history', (_, _) => const HistoryScreen()),
            _page('/library', (_, _) => const LibraryScreen()),
            _page('/settings', (_, _) => const SettingsScreen()),
            _page('/settings/ai', (_, _) => const AiSettingsScreen()),
            _page('/settings/workout', (_, _) => const WorkoutSettingsScreen()),
            _page('/settings/appearance', (_, _) => const AppearanceSettingsScreen()),
            _page('/settings/data', (_, _) => const DataSettingsScreen()),
          ],
        ),
      ],
      // Anything unrecognised goes home rather than showing an error page. It is outside the
      // shell, so it wraps itself in one — an unrecognised route is still a screen you have to
      // be able to leave.
      errorBuilder: (context, state) =>
          const AppShell(location: '/home', child: HomeScreen()),
    );

/// Every route fades in from 4px below, matching the original's `viewfade` — the one piece of
/// motion the app spends on navigation, and the reason a tab change feels like a change of
/// content rather than a page load.
GoRoute _page(String path, Widget Function(BuildContext, GoRouterState) build) => GoRoute(
      path: path,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: build(context, state),
        transitionDuration: Motion.med,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(parent: animation, curve: Motion.ease);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .012), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
