import 'package:flutter/widgets.dart';

/// Design tokens, ported 1:1 from `openGym/frontend/src/index.css`.
///
/// The original sheet is built on four rules, and they only survive the move to Flutter if
/// the numbers do: one type scale mostly at regular weight, a neutral surface ramp, hairlines
/// instead of borders, and motion that acknowledges rather than animates. Everything below is
/// the literal value from the CSS custom properties — no rounding, no "close enough".

/// `color-mix(in srgb, <color> <p>%, transparent)` — the CSS spelling for "this colour at p%".
Color mixT(Color c, double pct) => c.withValues(alpha: c.a * pct);

/// `color-mix(in srgb, <a> <p>%, <b>)` — p% of `a` blended into `b`.
Color mix(Color a, double pct, Color b) => Color.lerp(b, a, pct)!;

/// --r-sm --r --r-lg --r-xl --r-card, --pad
abstract final class R {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const card = 14.0;
  static const pad = 16.0;

  /// --hair: a sub-pixel separator. Kept as a physical 0.5 rather than 1/devicePixelRatio so
  /// a list reads as one object at any density, which is the point of rule 3.
  static const hair = 0.5;

  /// --icon-stroke
  static const iconStroke = 1.7;
}

/// --ease --fast --med
abstract final class Motion {
  static const ease = Cubic(.32, .72, 0, 1);
  static const fast = Duration(milliseconds: 140);
  static const med = Duration(milliseconds: 220);

  /// Sheet and dialog entries run longer than --med; see .sheet / .center in the CSS.
  static const sheet = Duration(milliseconds: 340);
  static const dialog = Duration(milliseconds: 280);
}

/// The type scale. Weight carries meaning here — 600 for a title, 400 for its content — and
/// size does the rest, so these are the only nine steps the app uses.
abstract final class TypeScale {
  static const large = (size: 34.0, height: 1.06, weight: FontWeight.w700, spacing: -.028);
  static const title = (size: 28.0, height: 1.12, weight: FontWeight.w700, spacing: -.024);
  static const title2 = (size: 22.0, height: 1.18, weight: FontWeight.w700, spacing: -.021);
  static const head = (size: 17.0, height: 1.29, weight: FontWeight.w600, spacing: -.012);
  static const body = (size: 17.0, height: 1.29, weight: FontWeight.w400, spacing: -.012);
  static const callout = (size: 16.0, height: 1.31, weight: FontWeight.w400, spacing: -.009);
  static const sub = (size: 15.0, height: 1.33, weight: FontWeight.w400, spacing: -.006);
  static const foot = (size: 13.0, height: 1.38, weight: FontWeight.w400, spacing: -.001);
  static const cap = (size: 12.0, height: 1.33, weight: FontWeight.w400, spacing: 0.0);
}

/// The eight accents, in the order the Settings swatch row draws them.
enum Accent { lime, sky, orange, violet, pink, red, teal, gold }

/// `ACCENTS` from lib/format.js — the literal hexes the settings swatches are painted with.
/// Deliberately the dark-theme values in both themes, exactly as the original: the swatch is
/// an identity for the accent, not a preview of how it renders in the current theme.
const accentSwatch = <Accent, Color>{
  Accent.lime: Color(0xFF30D158),
  Accent.sky: Color(0xFF0A84FF),
  Accent.orange: Color(0xFFFF9F0A),
  Accent.violet: Color(0xFFBF5AF2),
  Accent.pink: Color(0xFFFF375F),
  Accent.red: Color(0xFFFF453A),
  Accent.teal: Color(0xFF40C8E0),
  Accent.gold: Color(0xFFFFD60A),
};

Accent accentFrom(String? key) =>
    Accent.values.firstWhere((a) => a.name == key, orElse: () => Accent.lime);

/// Apple's system palette, at the values iOS uses for each appearance. `--acc` is an alias
/// onto one of these, which is why an accent shifts slightly between themes and never looks
/// off-system in either.
typedef SystemColors = ({
  Color blue, Color green, Color red, Color orange, Color yellow, Color teal,
  Color indigo, Color pink, Color purple, Color mint, Color brown, Color grey,
});

const systemDark = (
  blue: Color(0xFF0A84FF), green: Color(0xFF30D158), red: Color(0xFFFF453A),
  orange: Color(0xFFFF9F0A), yellow: Color(0xFFFFD60A), teal: Color(0xFF40C8E0),
  indigo: Color(0xFF5E5CE6), pink: Color(0xFFFF375F), purple: Color(0xFFBF5AF2),
  mint: Color(0xFF63E6E2), brown: Color(0xFFAC8E68), grey: Color(0xFF8E8E93),
);

const systemLight = (
  blue: Color(0xFF007AFF), green: Color(0xFF34C759), red: Color(0xFFFF3B30),
  orange: Color(0xFFFF9500), yellow: Color(0xFFFFCC00), teal: Color(0xFF30B0C7),
  indigo: Color(0xFF5856D6), pink: Color(0xFFFF2D55), purple: Color(0xFFAF52DE),
  mint: Color(0xFF00C7BE), brown: Color(0xFFA2845E), grey: Color(0xFF8E8E93),
);

/// Which system colour each accent aliases, its pressed shade, and the label colour that
/// sits on top of it.
///
/// `onAccent` is picked by measured contrast, not by taste: button text is 17px/600, so the
/// AA bar is 3:1. White on the light-theme green scores 2.22:1 and on teal 2.57:1 — both fail,
/// and green is the DEFAULT accent, so every primary button in light mode was failing. Black
/// scores 9.46 / 8.16 there. Blue, purple, pink and red keep white (3.5–4.1:1), which both
/// passes and matches the platform convention. The values hold across both themes.
typedef AccentSpec = ({Color Function(SystemColors) base, Color pressed, Color on});

const accentSpec = <Accent, AccentSpec>{
  Accent.lime: (base: _green, pressed: Color(0xFF248A3D), on: Color(0xFF000000)),
  Accent.sky: (base: _blue, pressed: Color(0xFF0060DF), on: Color(0xFFFFFFFF)),
  Accent.orange: (base: _orange, pressed: Color(0xFFC76B00), on: Color(0xFF000000)),
  Accent.violet: (base: _purple, pressed: Color(0xFF8944AB), on: Color(0xFFFFFFFF)),
  Accent.pink: (base: _pink, pressed: Color(0xFFD70036), on: Color(0xFFFFFFFF)),
  Accent.red: (base: _red, pressed: Color(0xFFD70015), on: Color(0xFFFFFFFF)),
  Accent.teal: (base: _teal, pressed: Color(0xFF0071A4), on: Color(0xFF000000)),
  Accent.gold: (base: _yellow, pressed: Color(0xFFB25000), on: Color(0xFF000000)),
};

Color _green(SystemColors s) => s.green;
Color _blue(SystemColors s) => s.blue;
Color _orange(SystemColors s) => s.orange;
Color _purple(SystemColors s) => s.purple;
Color _pink(SystemColors s) => s.pink;
Color _red(SystemColors s) => s.red;
Color _teal(SystemColors s) => s.teal;
Color _yellow(SystemColors s) => s.yellow;
