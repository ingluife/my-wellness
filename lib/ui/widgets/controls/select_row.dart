import 'package:flutter/material.dart';

import '../../sheets/sheet_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';
import 'surfaces.dart';

class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

/// Replaces a native picker.
///
/// A platform select opens a system list that ignores the app's theme entirely — in dark mode
/// it flashes a white sheet — and cannot show more than a bare label per option. This opens
/// the app's own sheet with a checkmark on the current value, which is also how iOS itself
/// handles a long option list.
class SelectRow<T> extends StatelessWidget {
  const SelectRow({
    super.key,
    this.icon,
    this.iconTint,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.sheetTitle,
  });

  final String? icon;
  final Color? iconTint;
  final String title;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? sheetTitle;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == value).firstOrNull;
    return AppRow(
      icon: icon,
      iconTint: iconTint,
      title: title,
      value: current?.label ?? '$value',
      accessory: RowAccessory.chevron,
      onTap: () => showSheet<void>(
        context: context,
        (sheetContext, close) {
          final c = sheetContext.c;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(sheetTitle ?? title),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(R.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Container(height: R.hair, color: c.sep),
                        ),
                      _Option(
                        option: options[i],
                        selected: options[i].value == value,
                        onTap: () {
                          close();
                          onChanged(options[i].value);
                        },
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _Option<T> extends StatelessWidget {
  const _Option({required this.option, required this.selected, required this.onTap});

  final SelectOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(option.label, style: ts(TypeScale.body, color: c.label)),
                  if (option.subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(option.subtitle!, style: ts(TypeScale.foot, color: c.label2)),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              AppIcon('check', size: 17, color: c.acc, stroke: 2.4),
            ],
          ],
        ),
      ),
    );
  }
}
