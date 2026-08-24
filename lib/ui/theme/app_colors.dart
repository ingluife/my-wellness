import 'package:flutter/material.dart';
import 'tokens.dart';

/// Every colour token from `index.css`, resolved for one (theme, accent) pair.
///
/// Reached through `context.c` (see the extension at the bottom), which is the Dart spelling
/// of writing `var(--surface)` in the original stylesheet.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.accentKey,
    required this.bg,
    required this.bgEl,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.label,
    required this.label2,
    required this.label3,
    required this.label4,
    required this.sep,
    required this.sepOp,
    required this.sys,
    required this.acc,
    required this.acc2,
    required this.onAcc,
  });

  final Brightness brightness;
  final Accent accentKey;

  /// surfaces — dark is the default appearance
  final Color bg;      // --bg
  final Color bgEl;    // --bg-el       elevated backdrop (sheets, bars)
  final Color surface; // --surface     card / grouped-list fill
  final Color surface2;// --surface-2   pressed + nested fill
  final Color surface3;// --surface-3   controls (segmented track, switch off)

  /// text
  final Color label;   // --label
  final Color label2;  // --label-2
  final Color label3;  // --label-3
  final Color label4;  // --label-4

  /// lines
  final Color sep;     // --sep
  final Color sepOp;   // --sep-op      for edges sitting over blur

  /// the iOS system palette for this appearance
  final SystemColors sys;

  /// accent (per-profile, persisted in S.accent)
  final Color acc;     // --acc
  final Color acc2;    // --acc-2       pressed
  final Color onAcc;   // --on-acc      label on a filled accent

  Color get accSoft => mixT(acc, .16); // --acc-soft
  Color get accLine => mixT(acc, .38); // --acc-line

  bool get isDark => brightness == Brightness.dark;

  factory AppColors.of(Brightness brightness, Accent accent) {
    final dark = brightness == Brightness.dark;
    final sys = dark ? systemDark : systemLight;
    final spec = accentSpec[accent]!;
    return AppColors(
      brightness: brightness,
      accentKey: accent,
      bg: dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      bgEl: dark ? const Color(0xFF0E0E10) : const Color(0xFFF7F7FA),
      surface: dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
      surface2: dark ? const Color(0xFF2C2C2E) : const Color(0xFFECECEF),
      surface3: dark ? const Color(0xFF3A3A3C) : const Color(0xFFE3E3E8),
      label: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      label2: dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43),
      label3: dark ? const Color(0x52EBEBF5) : const Color(0x4D3C3C43),
      label4: dark ? const Color(0x2EEBEBF5) : const Color(0x293C3C43),
      sep: dark ? const Color(0x99545458) : const Color(0x4A3C3C43),
      sepOp: dark ? const Color(0x57545458) : const Color(0x333C3C43),
      sys: sys,
      acc: spec.base(sys),
      acc2: spec.pressed,
      onAcc: spec.on,
    );
  }

  @override
  AppColors copyWith({Brightness? brightness, Accent? accentKey}) =>
      AppColors.of(brightness ?? this.brightness, accentKey ?? this.accentKey);

  /// Themes are switched, never tweened — the app repaints into the new appearance the way
  /// the CSS did when `data-theme` flipped. Lerping surfaces would put the list hairlines and
  /// the accent ramp briefly out of step with each other.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < .5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  /// `context.c.surface` reads the way `var(--surface)` did.
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}
