import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';

/// Numeric input accepting "," as a decimal separator.
///
/// iOS decimal keypads in many locales only offer a comma, and a strict numeric field reports
/// nothing for it — the value snaps to 0 as you type. A local string draft is kept while the
/// field has focus so partial input like "33," survives to become "33.5".
///
/// [nullable] is for fields where "nothing entered" and 0 mean different things: a logged RIR 0
/// is a set taken to failure, so clearing the cell has to produce null, not zero.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = true,
    this.nullable = false,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final bool decimal;
  final bool nullable;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _ctl = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  /// What the field last reported, so an external change can be told apart from an echo of
  /// the user's own typing — otherwise every keystroke would rewrite the draft under them.
  double? _committed;

  String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
      } else {
        // Leaving the field re-renders it from the value, dropping any half-typed draft.
        _committed = null;
        _ctl.text = _fmt(widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != _committed && widget.value != old.value) {
      _committed = null;
      _ctl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    var s = raw.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    final i = s.indexOf('.');
    if (i != -1) {
      s = widget.decimal
          ? s.substring(0, i + 1) + s.substring(i + 1).replaceAll('.', '')
          : s.substring(0, i);
    }
    final n = (s.isEmpty || s == '.')
        ? (widget.nullable ? null : 0.0)
        : (double.tryParse(s) ?? 0).clamp(0, double.infinity).toDouble();
    _committed = n;
    if (s != raw) {
      _ctl.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    }
    widget.onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return EditableText(
      controller: _ctl,
      focusNode: _focus,
      onChanged: _commit,
      style: widget.style ?? ts(TypeScale.body, color: c.label, weight: FontWeight.w500),
      cursorColor: c.acc,
      backgroundCursorColor: c.label4,
      textAlign: widget.textAlign,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal, signed: false),
      selectionColor: mixT(c.acc, .30),
      enableSuggestions: false,
      autocorrect: false,
      maxLines: 1,
    );
  }
}

/// The app's text input. A filled surface with an accent focus ring — no underline, no
/// floating label.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.onChanged,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.style,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = FocusNode()..addListener(() => setState(() {}));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final area = widget.maxLines > 1;
    return AnimatedContainer(
      duration: Motion.fast,
      constraints: BoxConstraints(minHeight: area ? 92 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: _focus.hasFocus ? c.acc : c.surface, width: 2),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        autofocus: widget.autofocus,
        textAlign: widget.textAlign,
        textCapitalization: widget.textCapitalization,
        textAlignVertical: area ? TextAlignVertical.top : null,
        style: widget.style ?? ts(TypeScale.body, color: c.label),
        cursorColor: c.acc,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.zero,
          hintText: widget.placeholder,
          hintStyle: ts(TypeScale.body, color: c.label3),
        ),
      ),
    );
  }
}

/// The search field: a recessed pill with a leading magnifier and a clear button that only
/// appears once there is something to clear.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.controller,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // In light mode the search field sits on a translucent grey rather than the surface ramp,
    // which is what keeps it reading as recessed on a white card.
    final fill = c.isDark ? c.surface2 : const Color(0x1F767680);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          AppIcon('magnifier', size: 16, color: c.label3, stroke: 2.1),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: ts(TypeScale.body, color: c.label),
              cursorColor: c.acc,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: ts(TypeScale.body, color: c.label3),
              ),
            ),
          ),
          if (value.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller?.clear();
                onChanged('');
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.label3, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: AppIcon('xmark', size: 11, color: c.bg, stroke: 3),
              ),
            ),
        ],
      ),
    );
  }
}
