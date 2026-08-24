import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';
import 'pressable.dart';

/// A card: a rounded fill with the app's standard padding. The most common container there is.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  /// A card that outlines itself in the accent — used where the card *is* the call to action
  /// ("today's plan", "training now").
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: child,
    );
    if (onTap != null) {
      body = Pressable(scale: 1, onTap: onTap, child: body);
    }
    return Padding(padding: margin, child: body);
  }
}

/// A section header — 13px, regular weight, `--label-2`. Deliberately not uppercase and not
/// bold: it names the group without competing with the rows inside it.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.margin});

  final String text;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin ?? const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: Text(text, style: ts(TypeScale.foot, color: context.c.label2)),
      );
}

/// The inset-grouped list — the app's main structural primitive.
///
/// A titled section holding rows separated by hairlines that stop short of the leading edge,
/// so the icon column reads as one continuous rail rather than a stack of outlined boxes.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.footer, required this.children});

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Text(title!, style: ts(TypeScale.foot, color: c.label2)),
            ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(R.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  // `.lrow + .lrow::before` — a hairline between rows, inset past the icon
                  // rail only when both neighbours actually have one, exactly as the CSS
                  // `:has(.lrow-i) + :has(.lrow-i)` rule does.
                  if (i > 0)
                    Padding(
                      padding: EdgeInsets.only(left: _inset(children[i - 1], children[i])),
                      child: Container(height: R.hair, color: c.sep),
                    ),
                  children[i],
                ]
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
              child: Text(footer!, style: ts(TypeScale.foot, color: c.label2)),
            ),
        ],
      ),
    );
  }
}

/// How far a separator is inset: past the 29px icon rail when the rows on both sides of it
/// carry an icon, otherwise just past the row padding.
double _inset(Widget above, Widget below) =>
    (above is AppRow && above.icon != null && below is AppRow && below.icon != null) ? 55 : 14;

enum RowAccessory { none, chevron, check }

/// One row of a grouped list.
///
/// The hairline belongs to the row *below*, inset past the icon rail — which is why it is
/// drawn here as a top border rather than as a separator widget between children.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    this.icon,
    this.iconTint,
    required this.title,
    this.subtitle,
    this.value,
    this.accessory = RowAccessory.none,
    this.onTap,
    this.danger = false,
    this.trailing,
  });

  final String? icon;
  final Color? iconTint;
  final String title;
  final String? subtitle;
  final String? value;
  final RowAccessory accessory;
  final VoidCallback? onTap;
  final bool danger;

  /// A control living in the row — a switch, an inline segmented control, a time field.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = danger ? c.sys.red : c.label;

    final body = Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: iconTint ?? c.acc,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: AppIcon(icon!, size: 18, color: const Color(0xFFFFFFFF)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: ts(TypeScale.body, color: fg)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: ts(TypeScale.foot, color: c.label2)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (value != null) ...[
            const SizedBox(width: 12),
            // Shrinkable and ellipsised: a long value ("Follow the routine (Linear
            // progression)") would otherwise run straight through the title beside it.
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: ts(TypeScale.body, color: c.label2),
              ),
            ),
          ],
          if (accessory == RowAccessory.chevron) ...[
            const SizedBox(width: 8),
            AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4),
          ],
          if (accessory == RowAccessory.check) ...[
            const SizedBox(width: 8),
            AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    // `body` is captured by value here. Reassigning a `content` variable and referring to it
    // from the builder would capture the *variable*, and the row would end up rendering
    // itself inside itself — a layout that never terminates.
    return Pressable.builder(
      scale: 1,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        color: pressed ? c.surface2 : null,
        child: body,
      ),
    );
  }
}

/// A standalone list row — the card-per-item list used for routines, exercises and workouts.
class ListItem extends StatelessWidget {
  const ListItem({
    super.key,
    required this.child,
    this.onTap,
    this.leading,
    this.trailing,
    this.accentEdge = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Widget? leading;
  final List<Widget>? trailing;

  /// `.item.in-ss` — a 3px accent edge marking membership of a superset.
  final bool accentEdge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable.builder(
      scale: 1,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: pressed ? c.surface2 : c.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: accentEdge ? Border(left: BorderSide(color: c.acc, width: 3)) : null,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(child: child),
            for (final t in trailing ?? const <Widget>[]) ...[const SizedBox(width: 12), t],
          ],
        ),
      ),
    );
  }
}

/// The two lines inside a [ListItem]: a title and a quieter detail line.
class ItemText extends StatelessWidget {
  const ItemText(this.title, {super.key, this.subtitle, this.capitalize = false});

  final String title;
  final String? subtitle;

  /// Exercise names arrive lowercase from the dataset, so the places that show one capitalise
  /// it. Anything that is a unit or a sentence opts back out.
  final bool capitalize;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          capitalize ? capitalized(title) : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ts(TypeScale.callout, color: c.label, size: 16, weight: FontWeight.w400),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(TypeScale.foot, color: c.label2)),
        ],
      ],
    );
  }
}

/// CSS `text-transform: capitalize` — every word, not just the first.
String capitalized(String s) => s.isEmpty
    ? s
    : s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// A small pill of metadata: a body part, an equipment name, a best weight, a status.
class Tag extends StatelessWidget {
  const Tag(this.label,
      {super.key, this.icon, this.accent = false, this.color, this.background, this.capitalize = true});

  final String? label;
  final String? icon;
  final bool accent;
  final Color? color;
  final Color? background;
  final bool capitalize;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = color ?? (accent ? c.acc : c.label2);
    final bg = background ?? (accent ? c.accSoft : c.surface2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 12, color: fg), const SizedBox(width: 3)],
          if (label != null)
            Text(capitalize ? capitalized(label!) : label!,
                style: ts(TypeScale.cap, color: fg, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// A filter chip. Rounded fully, and filled with the accent when it is the active filter.
class AppChip extends StatelessWidget {
  const AppChip(this.label,
      {super.key, required this.selected, required this.onTap, this.icon, this.capitalize = true});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? icon;
  final bool capitalize;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected ? c.onAcc : c.label;
    return Pressable.builder(
      scale: 1,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.acc : (pressed ? c.surface2 : c.surface),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[AppIcon(icon!, size: 12, color: fg), const SizedBox(width: 4)],
            Text(
              capitalize ? capitalized(label) : label,
              style: ts(TypeScale.sub,
                  size: 14,
                  color: fg,
                  weight: selected ? FontWeight.w500 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state: a large dim glyph over a sentence saying what would be here.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon, required this.message, this.detail});

  final String? icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
      child: Column(
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 34, color: c.label2),
            const SizedBox(height: 12),
          ],
          Text(message, textAlign: TextAlign.center, style: ts(TypeScale.sub, color: c.label2)),
          if (detail != null)
            Text(detail!, textAlign: TextAlign.center, style: ts(TypeScale.sub, color: c.label2)),
        ],
      ),
    );
  }
}

/// The round icon button in a header — back, settings, details, discard.
class IconButtonRound extends StatelessWidget {
  const IconButtonRound(
    this.icon, {
    super.key,
    required this.onTap,
    this.size = 36,
    this.iconSize,
    this.color,
    this.active = false,
    this.radius,
  });

  final String icon;
  final VoidCallback? onTap;
  final double size;
  final double? iconSize;
  final Color? color;

  /// `.iconbtn.on-ss` — the tinted state used by the superset link toggle.
  final bool active;

  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable.builder(
      scale: .92,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? c.accSoft : (pressed ? c.surface2 : c.surface),
          borderRadius: BorderRadius.circular(radius ?? size / 2),
        ),
        alignment: Alignment.center,
        child: AppIcon(icon,
            size: iconSize ?? size / 2, color: color ?? (active ? c.acc : c.label)),
      ),
    );
  }
}
