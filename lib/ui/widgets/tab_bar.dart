import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

/// The bottom bar: four tabs around a raised Start disc.
///
/// Blurred and translucent so the page scrolls visibly beneath it, with a hairline top edge —
/// the same treatment iOS gives its own bars, which is why it reads as chrome rather than as a
/// row of buttons parked at the bottom.
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: c.isDark ? mixT(c.bgEl, .72) : const Color(0xC7F9F9FB),
            border: Border(top: BorderSide(color: c.sepOp, width: R.hair)),
          ),
          padding: EdgeInsets.only(
            top: 7,
            bottom: 6 + MediaQuery.paddingOf(context).bottom,
            left: 6,
            right: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Tab(icon: 'house', label: t('Home'), on: _isOn('home'), onTap: () => onTap('/home')),
              _Tab(icon: 'calendar', label: t('Plan'), on: _isOn('plan'), onTap: () => onTap('/plan')),
              _StartButton(running: workoutRunning, onTap: onStart),
              _Tab(icon: 'chart', label: t('Stats'), on: _isOn('stats'), onTap: () => onTap('/stats')),
              _Tab(
                  icon: 'list',
                  label: t('Exercises'),
                  on: _isOn('library'),
                  onTap: () => onTap('/library')),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: on ? 1 : .32,
                child: AppIcon(icon, size: 25, color: on ? c.acc : c.label, stroke: on ? 2 : 1.65),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(TypeScale.cap,
                    size: 10,
                    color: on ? c.acc : c.label3,
                    weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The raised disc. Orange with a pulsing ring while a workout is running, so the app says
/// "you are mid-session" from any screen without a banner.
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

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Transform.translate(
          offset: const Offset(0, -24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _down ? .93 : 1,
                duration: Motion.fast,
                curve: Motion.ease,
                child: SizedBox(
                  width: 52,
                  height: 52,
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
                        child: AppIcon(running ? 'play' : 'dumbbell',
                            size: 26, color: glyph, stroke: 2),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                running ? t('Resume') : t('Start'),
                style: ts(TypeScale.cap,
                    size: 10, color: disc, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
