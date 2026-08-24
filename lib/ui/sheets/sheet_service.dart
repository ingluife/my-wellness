import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';

/// The app's navigator, so a flow started outside the widget tree can still push a screen or
/// a sheet — the same job `lib/nav.js` does in the original.
final appNavigatorKey = GlobalKey<NavigatorState>();

BuildContext get _ctx => appNavigatorKey.currentContext!;

/// A bottom sheet.
///
/// `builder` is handed a `close` callback rather than being expected to pop the navigator
/// itself, which keeps every flow reading the way the original's `openSheet(close => …)` does.
/// [locked] pins the sheet open — the weigh-in before a workout and the finish summary both
/// use it, because dismissing them would skip a step rather than cancel one.
Future<T?> showSheet<T>(
  Widget Function(BuildContext context, void Function([T? result]) close) builder, {
  bool locked = false,
  BuildContext? context,
}) {
  final ctx = context ?? _ctx;
  return showModalBottomSheet<T>(
    context: ctx,
    isScrollControlled: true,
    isDismissible: !locked,
    enableDrag: !locked,
    useSafeArea: true,
    // The sheet is the app's own surface, not Material's.
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    transitionAnimationController: null,
    builder: (sheetCtx) => _SheetShell(
      locked: locked,
      child: Builder(
        builder: (inner) => builder(inner, ([result]) => Navigator.of(sheetCtx).pop(result)),
      ),
    ),
  );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child, required this.locked});

  final Widget child;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
      decoration: BoxDecoration(
        // Light mode drops to the page background, so a sheet still reads as a layer above
        // white cards rather than merging into them.
        color: c.isDark ? c.bgEl : c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The grab handle. Present even when locked: it says "this is a sheet", and its
              // absence would read as a rendering fault rather than as a rule.
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 6, bottom: 14),
                decoration:
                    BoxDecoration(color: c.label4, borderRadius: BorderRadius.circular(99)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centred dialog — the `kind: 'center'` sheets: confirmations, "that's the whole workout",
/// the finish summary. Short, and about a decision rather than a form.
Future<T?> showCenterSheet<T>(
  Widget Function(BuildContext context, void Function([T? result]) close) builder, {
  bool locked = false,
  BuildContext? context,
}) {
  final ctx = context ?? _ctx;
  final c = ctx.c;
  return showDialog<T>(
    context: ctx,
    barrierDismissible: !locked,
    barrierColor: const Color(0x66000000),
    builder: (dialogCtx) => Center(
      child: Container(
        width: 300,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.isDark ? c.bgEl : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(R.lg),
          boxShadow: const [
            BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 20)),
          ],
        ),
        child: SingleChildScrollView(
          child: Builder(
            builder: (inner) => builder(inner, ([result]) => Navigator.of(dialogCtx).pop(result)),
          ),
        ),
      ),
    ),
  );
}

/// The sheet title — 20px semibold, the first thing in almost every sheet.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, this.capitalize = false, this.leading});

  final String text;
  final bool capitalize;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final title = Text(
      text,
      style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: leading == null
          ? title
          : Row(children: [leading!, const SizedBox(width: 8), Flexible(child: title)]),
    );
  }
}

/// A themed replacement for a platform confirm dialog. Callback-based, never blocking.
Future<void> confirmSheet({
  String? title,
  required String message,
  required String confirmText,
  String? cancelText,
  bool danger = false,
  required VoidCallback onConfirm,
  BuildContext? context,
}) async {
  final ok = await showCenterSheet<bool>(
    context: context,
    (ctx, close) {
      final c = ctx.c;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Text(
              title,
              textAlign: TextAlign.center,
              style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: ts(TypeScale.body, color: c.label2)),
          const SizedBox(height: 18),
          AppButton(
            confirmText,
            variant: danger ? BtnVariant.danger : BtnVariant.primary,
            onTap: () => close(true),
          ),
          const SizedBox(height: 8),
          AppButton(
            cancelText ?? t('Cancel'),
            variant: BtnVariant.ghost,
            color: c.label3,
            onTap: () => close(false),
          ),
        ],
      );
    },
  );
  if (ok == true) onConfirm();
}
