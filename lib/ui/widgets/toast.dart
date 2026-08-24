import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A brief message above the tab bar. Never blocks, never asks anything — it reports what just
/// happened and gets out of the way.
class AppToast extends StatelessWidget {
  const AppToast({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final showing = message.isNotEmpty;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: showing ? 1 : 0,
        duration: Motion.med,
        child: AnimatedSlide(
          offset: showing ? Offset.zero : const Offset(0, .2),
          duration: Motion.med,
          curve: Motion.ease,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints:
                      BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    color: mixT(c.surface2, .88),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: const [
                      BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10)),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: ts(TypeScale.sub, color: c.label, weight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
