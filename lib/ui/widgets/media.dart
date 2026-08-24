import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/exercises.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

/// The exercise animation.
///
/// Tapping toggles between the animation and its still frame — the same control the original
/// offers, and the one you actually want mid-set when the loop is distracting. On a white
/// plate, because that is what the dataset's artwork is drawn on.
///
/// Custom exercises have no media; the block simply is not there rather than showing a hole.
class ExerciseMedia extends ConsumerStatefulWidget {
  const ExerciseMedia({super.key, required this.ex, this.compact = false, this.minimizable = false});

  final Exercise ex;

  /// Superset cards put two exercises on screen together, so the animations have to give way —
  /// at full height you had to scroll a whole screen between two exercises done back-to-back.
  final bool compact;

  /// The workout view adds a persistent minimize control so the animation stops eating the
  /// screen. The choice is saved to the profile and carries across exercises and sessions.
  final bool minimizable;

  @override
  ConsumerState<ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends ConsumerState<ExerciseMedia> {
  bool _playing = true;

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    if (ex.gif == null) return const SizedBox.shrink();
    final gifSize = ref.watch(appStateProvider.select((s) => s.gifSize));
    final mini = widget.minimizable && gifSize == 'mini';
    final height = mini ? 84.0 : (widget.compact ? 120.0 : 320.0);

    return GestureDetector(
      onTap: () => setState(() => _playing = !_playing),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(R.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: height,
              child: Image.asset(
                _playing ? 'assets/gif/${ex.gif}' : 'assets/img/${ex.img}',
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (widget.minimizable)
              Positioned(
                left: 9,
                bottom: 9,
                child: _Pill(
                  icon: mini ? 'expand' : 'minimize',
                  label: mini ? t('Expand') : t('Minimize'),
                  onTap: () => ref
                      .read(appStateProvider.notifier)
                      .update((s) => s.gifSize = mini ? 'full' : 'mini'),
                ),
              ),
            if (!mini)
              Positioned(
                right: 9,
                bottom: 9,
                child: _Pill(
                  icon: _playing ? 'pause' : 'play',
                  label: _playing ? t('tap to pause') : t('tap to play'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A caption pill floating over the artwork. Dark and blurred so it stays readable against a
/// white plate without dimming the drawing underneath it.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.onTap});

  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0x73000000),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 13, color: const Color(0xFFFFFFFF)),
              const SizedBox(width: 4),
              Text(label,
                  style: ts(TypeScale.cap,
                      color: const Color(0xFFFFFFFF), weight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// The 50px still used in every list. Custom exercises fall back to a dumbbell glyph.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, required this.ex, this.size = 50});

  final Exercise ex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (ex.img == null) {
      return Container(
        width: size,
        height: size,
        decoration:
            BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: AppIcon('dumbbell', size: size * .42, color: c.label2),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(
        'assets/img/${ex.img}',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(width: size, height: size, color: c.surface2),
      ),
    );
  }
}

/// The rounded square that stands in for a routine: its glyph on an accent tile.
class GlyphTile extends StatelessWidget {
  const GlyphTile(this.glyph,
      {super.key, this.size = 29, this.radius = 7, this.background, this.color});

  final String glyph;
  final double size;
  final double radius;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? c.acc,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: AppIcon(glyph, size: size * .62, color: color ?? const Color(0xFFFFFFFF)),
    );
  }
}
