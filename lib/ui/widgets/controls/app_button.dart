import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';
import 'pressable.dart';

enum BtnVariant { plain, primary, tinted, danger, ghost }

enum BtnSize { normal, sm, xs }

/// The app's one button.
///
/// Five variants and three sizes cover every call site in the original — a filled accent for
/// the primary action, a tinted one for a secondary, a red wash for anything destructive, and
/// a flat ghost that is accent-coloured text. Full width by default, because that is what a
/// stacked sheet wants; the small sizes shrink to their content for use inside a row.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onTap,
    this.variant = BtnVariant.plain,
    this.size = BtnSize.normal,
    this.icon,
    this.trailingIcon,
    this.color,
    this.enabled = true,
  });

  final String? label;
  final VoidCallback? onTap;
  final BtnVariant variant;
  final BtnSize size;
  final String? icon;
  final String? trailingIcon;

  /// Overrides the label/icon colour, for the call sites that tint a button to signal state —
  /// a body-weight goal that is set turns its button yellow.
  final Color? color;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = enabled && onTap != null;

    final (padH, padV, fontSize, radius, gap, iconSize) = switch (size) {
      BtnSize.normal => (18.0, 14.0, 17.0, R.md, 7.0, 19.0),
      BtnSize.sm => (14.0, 8.0, 15.0, R.sm, 5.0, 16.0),
      BtnSize.xs => (10.0, 5.0, 13.0, 7.0, 4.0, 14.0),
    };

    final fg = color ??
        switch (variant) {
          BtnVariant.primary => c.onAcc,
          BtnVariant.tinted || BtnVariant.ghost => c.acc,
          BtnVariant.danger => c.sys.red,
          BtnVariant.plain => c.label,
        };
    // .btn.ghost drops to regular weight — it is text, not a slab.
    final weight = variant == BtnVariant.ghost ? FontWeight.w400 : FontWeight.w600;

    final parts = <Widget>[
      if (icon != null) AppIcon(icon!, size: iconSize, color: fg),
      if (label != null)
        Flexible(
          child: Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ts(TypeScale.body, color: fg, weight: weight, size: fontSize),
          ),
        ),
      if (trailingIcon != null) AppIcon(trailingIcon!, size: iconSize, color: fg),
    ];

    return Opacity(
      opacity: on ? 1 : .32,
      child: Pressable.builder(
        onTap: on ? onTap : null,
        build: (context, pressed) => AnimatedContainer(
          duration: Motion.fast,
          width: size == BtnSize.normal ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _fill(c, pressed),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                parts[i],
              ]
            ],
          ),
        ),
      ),
    );
  }

  /// The pressed state is a colour change, not an overlay: primary darkens to `--acc-2`, and
  /// the flat variants pick up `--surface-2` under the text.
  Color? _fill(AppColors c, bool pressed) => switch (variant) {
        BtnVariant.primary => pressed ? c.acc2 : c.acc,
        BtnVariant.tinted => c.accSoft,
        BtnVariant.danger => mixT(c.sys.red, .15),
        BtnVariant.ghost => pressed ? c.surface2 : null,
        BtnVariant.plain => pressed ? c.surface3 : c.surface2,
      };
}
