import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// The press response every control in the app shares.
///
/// Rule 4 of the design system: motion acknowledges, it does not animate. A press scales the
/// control by ~2% over 140ms on an ease-out curve — no ripple, no bounce, nothing that slides
/// for decoration. Wrapping it once here is what keeps a button, a chip, a swatch and a
/// calendar day all feeling like parts of the same object.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = .975,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    this.onPressedChange,
  });

  /// Either a plain child, or — via [Pressable.builder] — one that repaints while held.
  final Widget child;
  final VoidCallback? onTap;

  /// How far the control shrinks while held. The CSS uses .975 for buttons, .92 for round
  /// icon buttons and swatches, .9 for a checkbox.
  final double scale;

  final bool enabled;
  final HitTestBehavior behavior;

  /// For controls that also change colour while held — the caller paints, this reports.
  final ValueChanged<bool>? onPressedChange;

  /// Builds a child that depends on whether the control is currently held, for the many
  /// controls whose `:active` rule is a fill change and not just a scale.
  static Widget builder({
    Key? key,
    VoidCallback? onTap,
    double scale = .975,
    bool enabled = true,
    HitTestBehavior behavior = HitTestBehavior.opaque,
    required Widget Function(BuildContext, bool pressed) build,
  }) =>
      _PressableBuilder(
          key: key, onTap: onTap, scale: scale, enabled: enabled, behavior: behavior, build: build);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _live => widget.enabled && widget.onTap != null;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onPressedChange?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _live ? (_) => _set(true) : null,
      onTapUp: _live ? (_) => _set(false) : null,
      onTapCancel: _live ? () => _set(false) : null,
      onTap: _live ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.fast,
        curve: Motion.ease,
        child: widget.child,
      ),
    );
  }
}


class _PressableBuilder extends StatefulWidget {
  const _PressableBuilder({
    super.key,
    this.onTap,
    required this.scale,
    required this.enabled,
    required this.behavior,
    required this.build,
  });

  final VoidCallback? onTap;
  final double scale;
  final bool enabled;
  final HitTestBehavior behavior;
  final Widget Function(BuildContext, bool) build;

  @override
  State<_PressableBuilder> createState() => _PressableBuilderState();
}

class _PressableBuilderState extends State<_PressableBuilder> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: widget.onTap,
        scale: widget.scale,
        enabled: widget.enabled,
        behavior: widget.behavior,
        onPressedChange: (v) => setState(() => _down = v),
        child: widget.build(context, _down && widget.enabled && widget.onTap != null),
      );
}
