import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'tokens.dart';

typedef TypeToken = ({double size, double height, FontWeight weight, double spacing});

/// One step of the type scale as a [TextStyle].
///
/// CSS letter-spacing is in `em`, Flutter's is in logical pixels, so the token's value is
/// multiplied by its own size here — otherwise the tight tracking that holds the large titles
/// together would be applied at the same absolute amount to 12px captions.
TextStyle ts(TypeToken t, {Color? color, FontWeight? weight, double? size}) {
  final s = size ?? t.size;
  return TextStyle(
    fontSize: s,
    height: t.height,
    fontWeight: weight ?? t.weight,
    letterSpacing: t.spacing * s,
    color: color,
    // `font-variant-numeric: tabular-nums` on body — every weight, clock and set count in the
    // app is a number that must not jitter as it changes.
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildTheme(Brightness brightness, Accent accent) {
  final c = AppColors.of(brightness, accent);
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: c.acc,
      onPrimary: c.onAcc,
      surface: c.surface,
      onSurface: c.label,
      error: c.sys.red,
    ),
    // Rule 4 of the design system: motion acknowledges, it does not animate. Presses scale
    // ~2% and tint; an expanding Material ink ripple is exactly the "assembled" tell the
    // original control set was rebuilt to avoid, so it is switched off app-wide.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    // No fontFamily: the platform's own face is what `-apple-system … Roboto, system-ui` asks
    // for, and Flutter resolves that by default on each platform.
    textTheme: base.textTheme.apply(bodyColor: c.label, displayColor: c.label),
    iconTheme: IconThemeData(color: c.label, size: 24),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.acc,
      selectionColor: mixT(c.acc, .30),
      selectionHandleColor: c.acc,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
