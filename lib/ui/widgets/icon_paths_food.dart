// Food glyphs for the nutrition feature. Hand-drawn, and deliberately NOT generated.
//
// This file exists separately from icon_paths.dart for one reason: that file is rewritten
// wholesale by tool/gen_icons.mjs from openGym's components/Icon.jsx, so a glyph added there
// survives exactly until the next time anyone regenerates the icon set. openGym has no food
// icons and no nutrition feature to motivate them, so there is no upstream to extract these
// from — they are authored here and this is their source of truth.
//
// Same conventions as the generated set, so a food glyph never looks foreign beside a stock one:
//   - 24x24 viewBox, live area 3..21 - 3px of optical padding all round
//   - strokes only, except where a shape reads better solid (the fish's eye)
//   - round caps + round joins, stroke width from IconStroke (1.7 default)
//   - geometry snapped to .5 where it can be, so it lands on pixel edges at 24px
//
// There is no drumstick. Three attempts at one all read as a tennis racket at icon size, and a
// glyph nobody recognises is worse than a slightly less canonical one that they do — `fish`
// carries the protein category instead.
part of 'app_icon.dart';

const _foodIcons = <String, List<IconShape>>{
  // A whole apple with its stem and one leaf.
  'apple': [
    IconPath('M12 8.2c-1.1-1.4-3.1-1.8-4.6-.6C5.7 8.9 5.4 11.3 6.1 13.6c.7 2.3 2.1 4.9 3.7 '
        '4.9.8 0 1.4-.5 2.2-.5s1.4.5 2.2.5c1.6 0 3-2.6 3.7-4.9.7-2.3.4-4.7-1.3-6-1.5-1.2-3.5-.8'
        '-4.6.6Z'),
    IconPath('M12 8.2V5.2'),
    IconPath('M12 6.4c.7-1.4 2.1-2.1 3.6-1.9-.1 1.5-1.1 2.6-2.6 2.9'),
  ],
  // Facing right, so it reads as a fish rather than a leaf. The eye is what settles it.
  'fish': [
    IconPath('M19.5 12c-1.9 3.2-4.4 4.8-7.2 4.8S7 15.2 5.1 12c1.9-3.2 4.4-4.8 7.2-4.8s5.3 1.6 '
        '7.2 4.8Z'),
    IconPath('M5.1 12 3.2 9.2v5.6L5.1 12Z'),
    IconCircle(15.6, 10.8, 0.95, filled: true),
  ],
  // Narrower at the top, or it is just an ellipse.
  'egg': [
    IconPath('M12 19c-3 0-5.2-2.2-5.2-5.2C6.8 9.6 9.4 5 12 5s5.2 4.6 5.2 8.8c0 3-2.2 5.2-5.2 '
        '5.2Z'),
  ],
  // An ear of wheat: a stalk with two opposed pairs of grains.
  'grain': [
    IconPath('M12 20V8.5'),
    IconPath('M12 9.5c0-2.2 1.1-3.9 2.9-4.9.6 2-.5 4.2-2.9 4.9Z'),
    IconPath('M12 9.5c0-2.2-1.1-3.9-2.9-4.9-.6 2 .5 4.2 2.9 4.9Z'),
    IconPath('M12 15c0-2.2 1.1-3.9 2.9-4.9.6 2-.5 4.2-2.9 4.9Z'),
    IconPath('M12 15c0-2.2-1.1-3.9-2.9-4.9-.6 2 .5 4.2 2.9 4.9Z'),
  ],
  // Halved, because a whole avocado is a pear. The stone is what names it.
  'avocado': [
    IconPath('M12 4.5c-3 0-5.5 3-5.5 7 0 4.5 2.5 8 5.5 8s5.5-3.5 5.5-8c0-4-2.5-7-5.5-7Z'),
    IconCircle(12, 13.5, 2.6),
  ],
  // A gable-top carton. The shoulder line is what stops it reading as a bottle.
  'milk': [
    IconPath('M8.5 9.5v9.5a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1V9.5L13 4.5h-2L8.5 9.5Z'),
    IconPath('M8.5 9.5h7'),
  ],
  'leaf': [
    IconPath('M19 5c0 7-4.5 12-9.5 12-1.5 0-2.8-.5-3.8-1.4C4.5 9.5 10 5 19 5Z'),
    IconPath('M6 19.5C8.5 14 12 9.8 16 7.8'),
  ],
  'cup': [
    IconPath('M5.5 8h11v6.5a4 4 0 0 1-4 4h-3a4 4 0 0 1-4-4V8Z'),
    IconPath('M16.5 9.5h1.2a2.4 2.4 0 0 1 0 4.8h-1.2'),
  ],
  // A plate with something on it. Two bare concentric circles would be the `target` glyph.
  'meal': [
    IconCircle(12, 12, 7.4),
    IconPath('M8.2 13.6a3.8 3.8 0 0 1 7.6 0Z'),
    IconPath('M6.6 15.6h10.8'),
  ],
};
