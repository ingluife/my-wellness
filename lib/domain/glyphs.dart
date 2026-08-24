import '../ui/widgets/app_icon.dart' show iconNames;

/// Routine glyphs, ported from lib/glyphs.js.
///
/// Routines used to store a literal emoji in `r.emoji` ('💪', '🦵', …). The redesign stores an
/// icon key instead, but the field keeps its name so state synced by either build stays
/// readable by both — no migration, no lost routines.
///
/// [glyphOf] accepts either form: a known icon key passes through, a legacy emoji is mapped,
/// and anything unrecognised falls back to the default.

const defaultGlyph = 'figureStrength';

/// The picker offers glyphs that describe a TRAINING DAY — the split, the kit, or the kind of
/// session. An earlier version offered trophy/medal/crown/flag/star, which say how a workout
/// went rather than what it is; nobody names a routine "crown". Grouped, because 20 loose
/// icons is a wall — you scan the group first.
const glyphGroups = <({String key, List<String> items})>[
  (key: 'Strength', items: ['figureStrength', 'arm', 'abs', 'legs', 'pullup']),
  (key: 'Equipment', items: ['dumbbell', 'barbell', 'kettlebell', 'plate', 'machine']),
  (key: 'Cardio', items: ['figureRun', 'bike', 'swim', 'boxing', 'timer']),
  (key: 'Recovery', items: ['stretch', 'moon', 'heart', 'flame', 'bolt']),
];

final glyphs = [for (final g in glyphGroups) ...g.items];

/// Legacy emoji -> icon key, so routines created before the redesign keep a sensible glyph
/// instead of all collapsing onto the default.
const _legacy = <String, String>{
  '💪': 'arm', '🦾': 'arm', '🫸': 'figureStrength', '🫷': 'pullup',
  '🏋️': 'dumbbell', '🏋': 'dumbbell', '🏋️‍♀️': 'dumbbell',
  '🦵': 'legs', '🍑': 'legs',
  '🔥': 'flame', '⚡': 'bolt', '💥': 'bolt', '🧨': 'bolt', '😤': 'flame',
  '🏃': 'figureRun', '🏃‍♀️': 'figureRun', '🚴': 'bike', '🏊': 'swim',
  '🤸': 'stretch', '🧘': 'stretch', '🧘‍♀️': 'stretch',
  '🥊': 'boxing', '🧗': 'pullup', '⛰️': 'figureRun', '🏔️': 'figureRun', '🚀': 'bolt',
  '🎯': 'target', '🏆': 'trophy', '🥇': 'medal', '⭐': 'star', '🌟': 'star',
  '👑': 'crown', '🛡️': 'shield', '⚔️': 'shield', '❤️‍🔥': 'heart',
  '🦍': 'kettlebell', '🐂': 'barbell', '🐻': 'kettlebell', '🦁': 'boxing',
  '🐺': 'figureRun', '🦈': 'swim', '🤖': 'machine',
};

final _iconNames = iconNames.toSet();

String glyphOf(String? v) {
  if (v == null || v.isEmpty) return defaultGlyph;
  if (_iconNames.contains(v)) return v;
  final direct = _legacy[v];
  if (direct != null) return direct;
  // Strip variation selectors / ZWJ sequences and retry on the base emoji.
  final base = v.runes
      .where((r) => r != 0xFE0F && r != 0x200D)
      .take(1)
      .map(String.fromCharCode)
      .join();
  return _legacy[base] ?? defaultGlyph;
}
