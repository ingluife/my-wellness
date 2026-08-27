import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'domain/dishes.dart';
import 'domain/exercises.dart';
import 'domain/foods.dart';
import 'state/app_state_provider.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date and number formats for all twelve UI languages.
  await initializeDateFormatting();

  final container = ProviderContainer();
  // The catalogue and the profile both have to be in hand before the first frame: the app
  // opens on Home, which reads today's routine and therefore an exercise the plan names.
  await Exercises.instance.load();
  await Foods.instance.load();
  // The dish catalogue is what a profile with no recipes of its own gets planned from. It
  // degrades to empty rather than throwing, so a failure here costs the cold-start
  // suggestions and nothing else.
  await Dishes.instance.load();
  await container.read(appStateProvider.notifier).boot();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyOpenGymApp(),
    ),
  );
}
