import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'controls/surfaces.dart';

/// The scrolling body every screen sits in.
///
/// Holds the app's horizontal padding and a max width, so the layout stays a phone-shaped
/// column on a tablet instead of stretching a list of set rows across 900px.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.maxWidth = 560});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(R.pad, pad.top + 8, R.pad, pad.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// A large title, the way a navigation bar does it: 34px, tight tracking, with an optional
/// subtitle underneath and a control on the trailing edge.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.titleWidget,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// A back button, where the screen is a detail rather than a tab.
  final Widget? leading;

  /// Replaces the title text — the routine editor puts an editable field here.
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: titleWidget ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: ts(TypeScale.large, color: c.label)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: ts(TypeScale.sub, color: c.label2)),
                    ],
                  ],
                ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// A vertical list with the app's 8px gap — the routine list, the exercise list, the history.
class AppList extends StatelessWidget {
  const AppList({super.key, required this.children, this.gap = 8});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ]
        ],
      );
}

/// A horizontally scrolling chip row — the library's body-part and equipment filters.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              children[i],
            ]
          ],
        ),
      );
}

/// The small caption under a section heading — `h4.sec` in the original.
class SecHeading extends StatelessWidget {
  const SecHeading(this.text, {super.key, this.trailing, this.margin});

  final String text;
  final Widget? trailing;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final label = SectionTitle(text, margin: margin ?? const EdgeInsets.fromLTRB(4, 22, 4, 8));
    if (trailing == null) return label;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [Expanded(child: label), trailing!],
    );
  }
}
