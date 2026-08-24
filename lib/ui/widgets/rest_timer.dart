import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../../state/ui_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'controls/app_button.dart';

/// One bar, two meanings: the rest countdown between sets, and the work countdown during a
/// timed set.
///
/// They are mutually exclusive by construction — starting a hold stops any rest — so the bar
/// never has to show both, and the work variant gets its own outline plus a "Done" that logs
/// the time actually held rather than the target.
class RestTimerBar extends StatelessWidget {
  const RestTimerBar({super.key, required this.ui});

  final UiController ui;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final work = ui.work;
    final rest = ui.rest;
    final on = work ?? rest;
    if (on == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(R.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            // Nearly opaque: at 82% the set rows underneath read through it and made the clock
            // hard to pick out mid-set. The blur stays, so it still sits above the page.
            color: mixT(c.surface, .97),
            borderRadius: BorderRadius.circular(R.lg),
            border: work != null ? Border.all(color: c.acc, width: R.hair) : null,
            boxShadow: const [
              BoxShadow(color: Color(0x8C000000), blurRadius: 34, spreadRadius: -8, offset: Offset(0, 12)),
            ],
          ),
          child: work != null ? _work(context, work) : _rest(context, rest!),
        ),
      ),
    );
  }

  Widget _clock(BuildContext context, CountDown cd, {Color? color}) => Text(
        cd.clock,
        style: ts(TypeScale.title,
            size: 26, color: color ?? context.c.label, weight: FontWeight.w600),
      );

  Widget _bar(BuildContext context, CountDown cd) {
    final c = context.c;
    return Container(
      height: 4,
      decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(99)),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: cd.progress,
          child: AnimatedContainer(
            duration: const Duration(seconds: 1),
            decoration: BoxDecoration(color: c.acc, borderRadius: BorderRadius.circular(99)),
          ),
        ),
      ),
    );
  }

  /// The work variant keeps a single row — it only ever has two buttons.
  Widget _work(BuildContext context, CountDown cd) {
    final c = context.c;
    return Row(
      children: [
        SizedBox(width: 66, child: _clock(context, cd, color: c.acc)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cd.label != null) ...[
                Text(
                  cd.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(TypeScale.cap, color: c.label2),
                ),
                const SizedBox(height: 5),
              ],
              _bar(context, cd),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppButton(t('Cancel'), size: BtnSize.sm, onTap: ui.stopWork),
        const SizedBox(width: 8),
        AppButton(t('Done'),
            size: BtnSize.sm,
            variant: BtnVariant.primary,
            icon: 'check',
            onTap: ui.finishWorkEarly),
      ],
    );
  }

  /// Three controls plus the clock do not fit one line on a phone — at 360px the bar is left
  /// with about 30px and stops saying anything. So the rest variant stacks: clock and bar read
  /// at a glance, controls get their own row. −15 and +15 sit together in number-line order;
  /// Skip is pushed to the far edge, away from the button you tap to buy more time.
  Widget _rest(BuildContext context, CountDown cd) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(width: 66, child: _clock(context, cd)),
            const SizedBox(width: 12),
            Expanded(child: _bar(context, cd)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Sweaty hands, mid-set: these get more vertical padding than a normal small button.
            AppButton('15s', size: BtnSize.sm, icon: 'minus', onTap: () => ui.addRest(-15)),
            const SizedBox(width: 8),
            AppButton('15s', size: BtnSize.sm, icon: 'plus', onTap: () => ui.addRest(15)),
            const Spacer(),
            SizedBox(
              width: 84,
              child: AppButton(t('Skip'),
                  size: BtnSize.sm, variant: BtnVariant.primary, onTap: ui.stopRest),
            ),
          ],
        ),
      ],
    );
  }
}
