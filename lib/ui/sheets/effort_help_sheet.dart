import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'sheet_service.dart';

/// The two effort scales are one judgement counted from opposite ends, and a paragraph is a
/// bad way to say that — the conversion table shows it in one look. Reading down a column is
/// the answer to "what do I put here", so the numbers get their own aligned columns.
const _rows = [
  ('0', '10', 'Nothing left — went to failure'),
  ('1', '9', 'One more rep in the tank'),
  ('2', '8', 'Two more reps'),
  ('3', '7', 'Three more reps'),
  ('4+', '≤6', 'Easy — warm-up territory'),
];

/// RIR 2 / RPE 8: the row a working set usually lands on — the anchor the others are read
/// against. Not where the stepper starts; + walks up from the bottom of the scale.
const _typical = 2;

Future<void> effortHelpSheet() => showSheet<void>((context, close) {
      final c = context.c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(t('Effort per set')),
          Text(
            t('How hard a set was, logged next to weight and reps. Two scales for the same judgement, counted from opposite ends.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(0, 14, 0, 12),
            decoration:
                BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(R.lg)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              // The header names the columns without competing with them.
              Container(
                color: c.surface2,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  _num(context, t('RIR'), header: true),
                  _num(context, t('RPE'), header: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t('How it felt').toUpperCase(),
                        style: ts(TypeScale.cap,
                            size: 11, color: c.label3, weight: FontWeight.w600)),
                  ),
                ]),
              ),
              for (var i = 0; i < _rows.length; i++)
                Container(
                  decoration: BoxDecoration(
                    color: i == _typical ? c.accSoft : null,
                    border: Border(top: BorderSide(color: c.sep, width: R.hair)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    _num(context, _rows[i].$1, accent: i == _typical),
                    _num(context, _rows[i].$2, accent: i == _typical),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(t(_rows[i].$3),
                          style: ts(TypeScale.sub,
                              color: i == _typical ? c.label : c.label2)),
                    ),
                  ]),
                ),
            ]),
          ),
          Text(
            t('RIR counts the reps you left; RPE reads the same effort off a 10-point scale — so RPE ≈ 10 − RIR. Pick the one you already think in.'),
            style: ts(TypeScale.foot, color: c.label3),
          ),
          const SizedBox(height: 8),
          Text(
            t('The highlighted row is where most working sets land. Sets you have already logged keep their own scale, and nothing else reads the value — progression and estimated 1RM are unaffected.'),
            style: ts(TypeScale.foot, color: c.label3),
          ),
          const SizedBox(height: 8),
        ],
      );
    });

Widget _num(BuildContext context, String s, {bool header = false, bool accent = false}) {
  final c = context.c;
  return SizedBox(
    width: 36,
    child: Text(
      header ? s.toUpperCase() : s,
      textAlign: TextAlign.center,
      style: header
          ? ts(TypeScale.cap, size: 11, color: c.label3, weight: FontWeight.w600)
          : ts(TypeScale.body, color: accent ? c.acc : c.label, weight: FontWeight.w600),
    ),
  );
}
