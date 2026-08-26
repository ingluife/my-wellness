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

/// A number you type, styled like the app's text input and sized to sit in a list row.
///
/// [NumberField] is the raw primitive underneath [AppStepper]: a bare `EditableText` with no
/// background, no padding and no tap handling of its own. Inside a stepper that is exactly
/// right — the ± buttons do the work and the field is only ever a readout. Standing alone in a
/// row it is invisible and untappable, which is the gap this fills.
///
/// Use it wherever a number has to be typed rather than nudged: a calorie count, a height, a
/// macro off a label. Where a value is being *adjusted* rather than entered, [AppStepper] is
/// still the better control.
class NumberBox extends StatefulWidget {
  const NumberBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = true,
    this.nullable = false,
    this.placeholder,
    this.suffix,
    this.textAlign = TextAlign.end,
    this.invalid = false,
    this.max,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final bool decimal;

  /// Outlines the field in red. The message belongs beside the field, not in here — a red box
  /// with no words is a scolding rather than an explanation.
  final bool invalid;

  /// A ceiling the field will not go above.
  ///
  /// Enforced as you type rather than checked afterwards: typing a fourth digit into an age
  /// leaves it at the ceiling instead of accepting 999 and objecting later. There is
  /// deliberately no matching floor — clamping upward would rewrite "1" to "13" while someone
  /// was still on their way to typing "18", and a low value is better caught with a message.
  final double? max;

  /// An empty field reports null rather than zero — "not said" and "zero" are different
  /// answers, and a profile with no age is not a newborn.
  final bool nullable;

  final String? placeholder;

  /// A unit rendered inside the box, after the number: 'cm', 'g', 'kcal'.
  final String? suffix;

  final TextAlign textAlign;

  @override
  State<NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<NumberBox> {
  late final TextEditingController _ctl = TextEditingController(text: _fmt(widget.value));
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  /// What this field last reported, so a value coming back down can be told apart from an echo
  /// of the user's own typing. Without it every keystroke would rewrite the draft underneath
  /// them — the same guard [NumberField] carries.
  double? _committed;

  String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      // Selecting the whole value on focus means typing replaces it, which is what you want
      // when correcting a number rather than appending to one.
      _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
    } else {
      _committed = null;
      _ctl.text = _fmt(widget.value);
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(NumberBox old) {
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
    var n = (s.isEmpty || s == '.')
        ? (widget.nullable ? null : 0.0)
        : (double.tryParse(s) ?? 0).clamp(0, double.infinity).toDouble();

    final ceiling = widget.max;
    if (n != null && ceiling != null && n > ceiling) {
      n = ceiling;
      s = _fmt(n);
    }

    _committed = n;
    if (s != raw) {
      _ctl.value =
          TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    }
    widget.onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
          // Focus wins over the error colour while you are actually typing: a field turning
          // red under the cursor mid-number, before you have finished saying it, is noise.
          color: _focus.hasFocus
              ? c.acc
              : widget.invalid
                  ? c.sys.red
                  : c.surface2,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              onChanged: _commit,
              textAlign: widget.textAlign,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: widget.decimal, signed: false),
              style: ts(TypeScale.body, color: c.label, weight: FontWeight.w500),
              cursorColor: c.acc,
              enableSuggestions: false,
              autocorrect: false,
              maxLines: 1,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.placeholder,
                hintStyle: ts(TypeScale.body, color: c.label3),
              ),
            ),
          ),
          if (widget.suffix != null) ...[
            const SizedBox(width: 4),
            Text(widget.suffix!, style: ts(TypeScale.cap, color: c.label3)),
          ],
        ],
      ),
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
