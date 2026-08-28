import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';

/// The app's navigator, so a flow started outside the widget tree can still push a screen or
/// a sheet — the same job `lib/nav.js` does in the original.
final appNavigatorKey = GlobalKey<NavigatorState>();

BuildContext get _ctx => appNavigatorKey.currentContext!;

/// The sheet routes this service has opened and not yet seen closed.
///
/// A sheet opened from another sheet gets a back arrow instead of a close cross, because
/// dismissing it returns you to the one underneath rather than to the screen. Picking a food
/// from the list and then following a swap suggestion puts you three deep, and without this
/// there is nothing on screen saying which way is out.
///
/// Routes rather than a counter, and `isActive` rather than the set being trusted: a count
/// only ever decremented on close drifts upward the moment a sheet's route goes away without
/// completing — a navigator replaced underneath it, a hot reload — and every sheet after that
/// would claim to be nested forever. Asking the routes whether they are still on screen cannot
/// drift, because a stale entry answers no.
final _sheetRoutes = <Route<dynamic>>{};

/// The sheet's own gutter. Applied by the shell either way, so a sheet that scrolls its own list
/// is inset exactly like every other one.
const _contentPad = EdgeInsets.fromLTRB(18, 0, 18, 20);

bool get _anySheetOpen => _sheetRoutes.any((r) => r.isActive);

/// A bottom sheet.
///
/// `builder` is handed a `close` callback rather than being expected to pop the navigator
/// itself, which keeps every flow reading the way the original's `openSheet(close => …)` does.
/// [locked] pins the sheet open — the weigh-in before a workout and the finish summary both
/// use it, because dismissing them would skip a step rather than cancel one.
///
/// [scrollable] is what almost every sheet wants: a column of content that the shell scrolls as
/// one. Pass false for a sheet that scrolls a list of its own and keeps something below it — see
/// [_SheetShell], where the difference is spelled out.
Future<T?> showSheet<T>(
  Widget Function(BuildContext context, void Function([T? result]) close) builder, {
  bool locked = false,
  bool scrollable = true,
  BuildContext? context,
}) {
  final ctx = context ?? _ctx;
  // Decided at open time: what matters is whether something was already on screen when this
  // sheet appeared, not what the stack looks like later when something above it closes.
  final nested = _anySheetOpen;
  Route<dynamic>? mine;
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
    builder: (sheetCtx) {
      mine ??= ModalRoute.of(sheetCtx);
      if (mine != null) _sheetRoutes.add(mine!);
      return _SheetShell(
        locked: locked,
        nested: nested,
        scrollable: scrollable,
        onDismiss: () => Navigator.of(sheetCtx).pop(),
        child: Builder(
          builder: (inner) => builder(inner, ([result]) => Navigator.of(sheetCtx).pop(result)),
        ),
      );
    },
  ).whenComplete(() => _sheetRoutes.remove(mine));
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.child,
    required this.locked,
    required this.nested,
    required this.scrollable,
    required this.onDismiss,
  });

  final Widget child;
  final bool locked;

  /// Opened from another sheet, so leaving goes back rather than out.
  final bool nested;

  /// Whether the shell scrolls the sheet's content, or hands it a bounded box and gets out of
  /// the way.
  ///
  /// This is a load-bearing distinction rather than a preference, and getting it wrong is
  /// invisible until the sheet is long. Scrolling here means the child is laid out under an
  /// **unbounded** height, so a `Flexible` inside it has no share of anything to take and a
  /// `shrinkWrap` list expands to its full content — pushing whatever the sheet put below it,
  /// buttons included, past the bottom of the screen where nothing can reach it. Worse, the
  /// nested list wins the drag gesture while having nothing to scroll, so the shell's own scroll
  /// view never moves and the sheet reads as frozen.
  ///
  /// False gives the child the height it actually has. A sheet that scrolls a list of its own
  /// and keeps a footer under it — the food picker, the day copier — needs that; everything
  /// else is a column of content and wants the default.
  final bool scrollable;

  final VoidCallback onDismiss;

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
              // The grab handle, and the way out.
              //
              // The handle is present even when locked: it says "this is a sheet", and its
              // absence would read as a rendering fault rather than as a rule. The button is
              // not — a locked sheet is one where leaving would skip a step rather than
              // cancel one, and giving it a cross would be a lie.
              //
              // Dragging down has always worked; what was missing was anything on screen
              // saying so. A stacked sheet gets a back arrow because it returns to the sheet
              // underneath, which is a different promise from closing.
              SizedBox(
                // Full width on purpose: the Column centres its children, so a box with only a
                // height shrinks to the handle and the positioned button falls outside it.
                width: double.infinity,
                height: 38,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 36,
                        height: 5,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                            color: c.label4, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    if (!locked)
                      Positioned(
                        left: 10,
                        top: 0,
                        child: IconButtonRound(
                          nested ? 'chevronLeft' : 'xmark',
                          size: 30,
                          iconSize: nested ? 16 : 14,
                          onTap: onDismiss,
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: scrollable
                    ? SingleChildScrollView(padding: _contentPad, child: child)
                    : Padding(padding: _contentPad, child: child),
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
