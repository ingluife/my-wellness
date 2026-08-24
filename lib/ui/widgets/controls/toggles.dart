import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';
import 'pressable.dart';

/// The switch.
///
/// Rebuilt rather than themed: a platform switch renders blue on iOS and grey on Android, and
/// neither takes the profile's accent. The knob widens by 4px while held, which is the detail
/// that makes it feel like a physical toggle rather than a checkbox in a coat.
class AppSwitch extends StatefulWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.enabled = true});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = widget.value;
    final live = widget.enabled && widget.onChanged != null;
    final knobW = _down ? 31.0 : 27.0;
    return Opacity(
      opacity: live ? 1 : .4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: live ? (_) => setState(() => _down = true) : null,
        onTapUp: live ? (_) => setState(() => _down = false) : null,
        onTapCancel: live ? () => setState(() => _down = false) : null,
        onTap: live ? () => widget.onChanged!(!on) : null,
        child: AnimatedContainer(
          duration: Motion.med,
          curve: Motion.ease,
          width: 51,
          height: 31,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: on ? c.acc : c.surface3,
            borderRadius: BorderRadius.circular(99),
          ),
          child: AnimatedAlign(
            duration: Motion.med,
            curve: Motion.ease,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              width: knobW,
              height: 27,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(99),
                boxShadow: const [
                  BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 3)),
                  BoxShadow(color: Color(0x29000000), blurRadius: 1, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The checkbox that marks a set done: a hairline ring that fills with the accent.
class AppCheck extends StatelessWidget {
  const AppCheck({super.key, required this.value, required this.onChanged, this.size = 30});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      scale: .9,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: Motion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? c.acc : null,
          shape: BoxShape.circle,
          border: value ? null : Border.all(color: c.label4, width: 1.8),
        ),
        alignment: Alignment.center,
        child: value
            ? AppIcon('check', size: size * .53, color: c.onAcc, stroke: 2.6)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class SegOption<T> {
  const SegOption(this.value, {this.label, this.icon});

  final T value;
  final String? label;
  final String? icon;
}

/// The segmented control: a recessed track with a selected pill that slides between cells.
///
/// The pill is a positioned child rather than a per-cell background, which is what makes the
/// selection move rather than blink — the same reason the CSS animates a `translateX` on one
/// element instead of toggling a class on several.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.inline = false,
  });

  final List<SegOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// `.seg-inline` — shrinks to content for sitting inside a list row, instead of filling it.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var i = options.indexWhere((o) => o.value == value);
    if (i < 0) i = 0;
    final track = c.isDark ? c.surface3 : const Color(0x1F767680);
    final fontSize = inline ? 13.0 : 14.0;
    final minHeight = inline ? 28.0 : 30.0;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 0.0;
      final cellW = (w - 4) / options.length;
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(9)),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: Motion.med,
              curve: Motion.ease,
              left: cellW * i,
              top: 0,
              bottom: 0,
              width: cellW,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.isDark ? c.surface : const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 3)),
                    BoxShadow(color: Color(0x0F000000), blurRadius: 1, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (final o in options)
                  Expanded(
                    child: Pressable.builder(
                      scale: 1,
                      onTap: () => onChanged(o.value),
                      build: (context, pressed) => Opacity(
                        opacity: pressed ? .5 : 1,
                        child: Container(
                          constraints: BoxConstraints(minHeight: minHeight),
                          padding: EdgeInsets.symmetric(horizontal: inline ? 10 : 8, vertical: 5),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (o.icon != null) ...[
                                AppIcon(o.icon!,
                                    size: inline ? 14 : 16,
                                    color: o.value == value ? c.label : c.label2),
                                if (o.label != null) const SizedBox(width: 5),
                              ],
                              if (o.label != null)
                                Flexible(
                                  child: Text(
                                    o.label!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(TypeScale.sub,
                                        size: fontSize,
                                        color: o.value == value ? c.label : c.label2,
                                        weight: o.value == value
                                            ? FontWeight.w500
                                            : FontWeight.w400),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
