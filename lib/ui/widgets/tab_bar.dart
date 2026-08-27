import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

/// Bar metrics, named because two different columns have to agree on them.
///
/// The tabs and the docked disc are laid out by different widgets — one inside the bar's row, one
/// positioned over it — so nothing makes their labels line up automatically. [_lift] is derived
/// from the rest rather than eyeballed, which is what keeps that true if any of them is changed.
const _barPadTop = 7.0;
const _tabPadTop = 3.0;
const _iconSize = 25.0;
const _labelGap = 3.0;
const _discSize = 52.0;

/// The gap left in the row for the disc to dock into. Wider than the disc so it does not crowd
/// the tabs either side, and the width the Start label is allowed — a longer word in another
/// language ellipsises rather than growing into a neighbouring tab's tap target.
const _dockWidth = 66.0;

/// How far the disc rises above the bar's top edge.
///
/// Not a look chosen by eye: it is exactly the distance that puts the disc's label on the same
/// line as the tab labels. The disc and its gap have to clear the bar's top padding, a tab's own
/// top padding, its icon, and its label gap; whatever is left over is the overhang.
const _lift = _discSize + _labelGap - (_barPadTop + _tabPadTop + _iconSize + _labelGap);

/// The bottom bar: four tabs around a Start disc docked in the middle.
///
/// Blurred and translucent so the page scrolls visibly beneath it, with a hairline top edge —
/// the same treatment iOS gives its own bars, which is why it reads as chrome rather than as a
/// row of buttons parked at the bottom.
///
/// **The disc is a sibling of the bar, not a child of it**, and that is the whole reason this is a
/// Stack. A `BackdropFilter` has to be clipped or it blurs the entire screen, so the bar carries a
/// `ClipRect` — and anything raised out of the bar from inside it gets cut by that clip on the way
/// out, and stops receiving taps at the same edge, because hit testing is bounded by the box a
/// widget was laid out in. Lifting the disc with a `Transform` inside the row did both: a third of
/// the button was invisible and dead to touch. Docking it over the bar instead keeps the blur
/// clipped to the bar, and keeps the button whole.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.current,
    required this.onTap,
    required this.onStart,
    required this.workoutRunning,
  });

  /// The first path segment: 'home' | 'plan' | 'workout' | 'stats' | 'library' | …
  final String current;

  final void Function(String route) onTap;
  final VoidCallback onStart;

  /// A running workout turns the disc orange and gives it a pulsing ring.
  final bool workoutRunning;

  /// History is reached from Stats, and Settings and Nutrition from Home, so each keeps its
  /// parent lit rather than leaving no tab selected at all.
  bool _isOn(String key) =>
      current == key ||
      (current == 'history' && key == 'stats') ||
      (current == 'settings' && key == 'home') ||
      (current == 'nutrition' && key == 'home');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      // The disc overhangs the top of this stack while a workout is running, because its ring
      // pulses outwards past the button. Decoration only, and the shell stack it sits in covers
      // the whole screen, so there is nothing above to collide with.
      clipBehavior: Clip.none,
      // Centres the disc horizontally: it is positioned on the vertical axis only, and a stack
      // falls back to its alignment for whichever axis a child leaves unspecified.
      alignment: Alignment.topCenter,
      children: [
        // The bar, held down by the overhang so there is real, hit-testable room above it.
        Padding(
          padding: const EdgeInsets.only(top: _lift),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: c.isDark ? mixT(c.bgEl, .72) : const Color(0xC7F9F9FB),
                  border: Border(
                    top: BorderSide(color: c.sepOp, width: R.hair),
                  ),
                ),
                padding: EdgeInsets.only(
                  top: _barPadTop,
                  bottom: 6 + MediaQuery.paddingOf(context).bottom,
                  left: 6,
                  right: 6,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Tab(
                      icon: 'house',
                      label: t('Home'),
                      on: _isOn('home'),
                      onTap: () => onTap('/home'),
                    ),
                    _Tab(
                      icon: 'calendar',
                      label: t('Plan'),
                      on: _isOn('plan'),
                      onTap: () => onTap('/plan'),
                    ),
                    // The berth the disc docks into. Two equal tabs either side of it, so the
                    // middle of this gap is the middle of the bar.
                    const SizedBox(width: _dockWidth),
                    _Tab(
                      icon: 'chart',
                      label: t('Stats'),
                      on: _isOn('stats'),
                      onTap: () => onTap('/stats'),
                    ),
                    _Tab(
                      icon: 'list',
                      label: t('Exercises'),
                      on: _isOn('library'),
                      onTap: () => onTap('/library'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Docked over the bar, and laid out entirely within this stack — which is what makes the
        // whole disc both visible and tappable, the two things the old Transform gave up.
        Positioned(
          top: 0,
          child: _StartButton(running: workoutRunning, onTap: onStart),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.on, required this.onTap});

  final String icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The inactive tint is carried as opacity on the whole glyph rather than in the stroke
    // colour: a semi-transparent stroke doubles up wherever two strokes cross inside an icon
    // (the calendar's hangers over its frame), and the icon reads as loose layers.
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: _tabPadTop),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: on ? 1 : .32,
                child: AppIcon(
                  icon,
                  size: _iconSize,
                  color: on ? c.acc : c.label,
                  stroke: on ? 2 : 1.65,
                ),
              ),
              const SizedBox(height: _labelGap),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(
                  TypeScale.cap,
                  size: 10,
                  color: on ? c.acc : c.label3,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The docked disc. Orange with a pulsing ring while a workout is running, so the app says
/// "you are mid-session" from any screen without a banner.
///
/// Sizes itself rather than taking a share of the row: it is no longer *in* the row, it is
/// positioned over the berth the row leaves for it. See [AppTabBar].
class _StartButton extends StatefulWidget {
  const _StartButton({required this.running, required this.onTap});

  final bool running;
  final VoidCallback onTap;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  // Built here rather than as a lazy field: a `late final` controller that is only touched
  // when a workout is running would be *constructed* by dispose() on the way out, and
  // creating a ticker against a deactivated element is an error.
  late final AnimationController _ping;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _ping = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
    if (widget.running) _ping.repeat();
  }

  @override
  void didUpdateWidget(_StartButton old) {
    super.didUpdateWidget(old);
    if (widget.running && !_ping.isAnimating) {
      _ping.repeat();
    } else if (!widget.running) {
      _ping.stop();
    }
  }

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final running = widget.running;
    // The disc is orange in either theme, so its glyph is black rather than `--on-acc`.
    final disc = running ? c.sys.orange : c.acc;
    final glyph = running ? const Color(0xFF000000) : c.onAcc;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: SizedBox(
        // Exactly the berth the row left. Bounding it here is what stops a long word in another
        // language — 'Fortsetzen', 'Retomar' — from widening the column into a neighbouring tab's
        // tap target, where it would silently steal presses meant for Plan or Stats.
        width: _dockWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _down ? .93 : 1,
              duration: Motion.fast,
              curve: Motion.ease,
              child: SizedBox(
                width: _discSize,
                height: _discSize,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (running)
                      AnimatedBuilder(
                        animation: _ping,
                        builder: (context, _) {
                          final v = Motion.ease.transform(_ping.value);
                          return Transform.scale(
                            scale: 1 + v * .45,
                            child: Opacity(
                              opacity: (1 - v) * .7,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.sys.orange, width: 2),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: disc,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: mixT(disc, .55),
                            blurRadius: 18,
                            spreadRadius: -4,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        running ? 'play' : 'dumbbell',
                        size: 26,
                        color: glyph,
                        stroke: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: _labelGap),
            Text(
              running ? t('Resume') : t('Start'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ts(TypeScale.cap, size: 10, color: disc, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
