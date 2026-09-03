import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/page.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => const LocalOnlyAuth());

/// The way in.
///
/// This build keeps its data on the phone, so the honest primary action is "continue without
/// account" — the same thing openGym's mobile flavour does by skipping this screen entirely.
/// The sign-in path is present but only offered where an [AuthRepository] can actually serve
/// it, so the screen never shows a button that cannot work.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final auth = ref.watch(authRepositoryProvider);

    return AppPage(
      maxWidth: 420,
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * .18),
        Center(child: AppIcon('dumbbell', size: 54, color: c.acc)),
        const SizedBox(height: 10),
        Text('My Wellness',
            textAlign: TextAlign.center, style: ts(TypeScale.large, color: c.label)),
        const SizedBox(height: 4),
        Text(t('Your workouts. Your weights. Your profile.'),
            textAlign: TextAlign.center, style: ts(TypeScale.body, color: c.label2)),
        const SizedBox(height: 34),
        if (auth.isAvailable) ...[
          AppButton(t('Sign in with passkey'),
              variant: BtnVariant.primary, icon: 'person', onTap: () => auth.signIn()),
          const SizedBox(height: 10),
          AppButton(t('Create new profile'), icon: 'sparkles', onTap: () {}),
          const SizedBox(height: 10),
        ] else
          AppCard(
            child: Text(
              t('All data stays on this phone'),
              style: ts(TypeScale.foot, color: c.label2),
            ),
          ),
        AppButton(t('Continue without account'),
            variant: auth.isAvailable ? BtnVariant.ghost : BtnVariant.primary,
            color: auth.isAvailable ? c.label3 : null,
            onTap: () => context.go('/home')),
        const SizedBox(height: 26),
        Text(t('Each profile keeps its own plan, workouts & body weight.'),
            textAlign: TextAlign.center, style: ts(TypeScale.foot, color: c.label3)),
      ],
    );
  }
}
