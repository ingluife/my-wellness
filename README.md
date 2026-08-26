# myOpenGym

A Flutter translation of [openGym](https://github.com/DuarteSantos8/openGym) — the same gym and
body-weight tracker, rebuilt as a native Android and iOS app so it can grow with Firebase behind
it instead of a self-hosted Node backend.

This is a **translation, not a reimagining**: the same screens in the same order, the same design
system down to the hairline insets, the same 1,324-exercise library, the same progression rules,
and — the part that matters most — the same JSON. A backup exported here imports into openGym and
back again with nothing lost.

## What it is

The **mobile flavour** of openGym (`VITE_MOBILE=1`): no account, no server, no telemetry. Your
training log lives on the phone, in the app's private storage, and goes out through the OS share
sheet when you back it up. The self-hosted flavour's passkey sign-in, cross-device sync and admin
dashboard are not part of this build — see *Firebase* below for where that goes.

| | |
|---|---|
| **Screens** | Home · Plan · Routine editor · Workout · Stats · History · Exercises · Settings · Login |
| **Exercises** | 1,324, with an animation and a still for each, plus your own |
| **Languages** | 12 (EN, DE, ES, FR, IT, PT, PL, TR, RU, ZH, KO, HI); instructions localised in 10 |
| **Progression** | Linear · Greyskull LP · double progression · add-time · off, per routine or per exercise |
| **Logging** | Weight × reps, timed holds, cardio; bodyweight and per-side variants; optional RIR/RPE |
| **Analytics** | Muscle map, activity heatmap, estimated 1RM, effort trends, body-weight curve with a goal line |
| **Import** | FitNotes (Android + iOS), Strong, Hevy, and body weight from an Apple Health export |

## Running it

```sh
flutter pub get
./tool/sync_media.sh      # copies the 1,324 stills + animations out of ../openGym
flutter run
```

The exercise media is ~137 MB and is **not** committed. `tool/sync_media.sh` populates
`assets/img` and `assets/gif` from an openGym checkout; CI does the same before it builds.

### Regenerating the assets

Everything derived from openGym is produced by a script rather than transcribed, so it can be
re-run whenever the source moves:

```sh
node tool/gen_exercises.mjs     # assets/data/exercises.json     (1,324 exercises)
node tool/gen_body_paths.mjs    # assets/data/body_paths.json    (male/female x front/back)
node tool/gen_i18n.mjs          # assets/i18n/*.json, assets/instr/*.json
node tool/gen_icons.mjs         # lib/ui/widgets/icon_paths.dart (83 icons)
node tool/gen_tones.mjs         # assets/audio/*.wav             (the timer beeps)
./tool/sync_media.sh            # assets/img, assets/gif
```

The nutrition feature has no upstream in openGym, so its data comes from public sources instead:

```sh
node tool/gen_foods.mjs         # assets/data/foods.json         (226 foods, USDA FoodData Central)
                                #                                 + household portions and fibre
node tool/fetch_food_media.mjs  # tool/food_media.tsv            (resolves a CC0 photo per food)
./tool/sync_food_media.sh       # assets/food                    (downloads and crops them)
node tool/check_i18n_nutrition.mjs   # validates tool/locales_nutrition/*.js before a regen
```

Its **strings** have no upstream either, so they live in `tool/locales_nutrition/<lang>.js` — 562
keys per language, covering the screens and coaching copy, the meal slots, the food categories,
and the food and portion names the catalogue is written in. `gen_i18n.mjs` merges them over
openGym's pack for each language, which is the only reason a re-run does not wipe them; edit the
overlay, never `assets/i18n/*.json`.

`tool/nutrition_keys.json` is the English key list the overlay is checked against — the grouped
set of source strings the feature uses, so a key quietly dropped from all eleven files is still
caught. Add a `t('…')` to the nutrition screens and it belongs there too.
`check_i18n_nutrition.mjs` catches the mistakes review does not — a dropped key, a translation
that lost its `{0}`, a stray character from another alphabet — and `test/i18n_test.dart` asserts
the same invariants against the packs that actually ship.

`tool/foods_seed.tsv` is the curated list — which foods exist, and which USDA record each one's
numbers come from. It is hand-maintained; `gen_foods.mjs` only resolves it. **The `id` column is
permanent**: a logged meal stores it, so renumbering would repoint every meal ever logged.

Household portions come from the same USDA records, with one trap worth knowing about: the bulk
dataset drops the `amount` field the API carries, so `{modifier: "oz", gramWeight: 113}` is
*four* ounces, not one. `gen_foods.mjs` discards bare weight and volume units for that reason and
keeps the count nouns, where the implied amount is reliably one. A test asserts none leak back in.

`fetch_food_media.mjs` is rate-limited by Openverse (20/min, 200/day anonymous) and skips foods
already in the manifest, so it is meant to be run more than once. `lib/ui/widgets/icon_paths_food.dart`
is **not** generated — `gen_icons.mjs` overwrites `icon_paths.dart` wholesale, so the food glyphs
are hand-drawn in a file it does not touch.

## Layout

```
lib/
├── data/models/          AppState and everything in it — the JSON contract with openGym
├── data/repositories/    persistence, and the auth/sync seam
├── domain/               pure logic, ported 1:1 from openGym's lib/
│                         history · progression · effort · onerm · muscles · format
│                         i18n · glyphs · exercises · starter · import_csv · plan_share
│                         ...and, with no upstream: nutrition · met · foods
│                         coaching (what to say next) · day_plan (what a day looks like)
├── platform/             notifications, wake lock, backup/share
├── state/                the two stores: persisted state, and ephemeral UI state
└── ui/
    ├── theme/            every token from openGym's index.css
    ├── widgets/          the control set, the icon set, and four CustomPainters
    │                     (line chart, heatmap, body map, calorie ring)
    ├── screens/          one file per screen
    └── sheets/           the bottom-sheet flows
```

### Why things are the way they are

- **The state is one object.** `AppState` is openGym's `S`, key for key. Every feature is a pure
  function of it, and `update((s) { … })` hands you a deep clone to mutate — the same producer
  pattern the original's store uses.
- **Nothing is a stock Material widget.** A platform switch renders blue on iOS and grey on
  Android and takes neither theme nor accent; a platform picker opens a system list that ignores
  dark mode. Every control is rebuilt, and Material's ink ripple is switched off app-wide in
  favour of the original's press-scale response.
- **The charts are hand-painted.** The geometry — a 12 % vertical margin, nice-number gridlines,
  a gradient that fades to nothing, relative muscle shading — is part of the design, not a
  setting a charting package exposes.
- **A plan is an intention; the log is a record.** Generated day plans are never written into
  `meals` — each meal is logged when it is actually eaten. Anything else would put food nobody
  ate into the comparison below, which is the one number here that can be checked.
- **Nutrition shows its own error bars.** A calorie target is built on a BMR equation fitted to a
  population, a MET table inferred from a body part, and a portion size somebody eyeballed. Stats
  compares what the log *predicted* against what the scale actually did and reports the gap,
  because the only number that generalises to one person is whether these estimates run high or
  low for them. `nutrition` and `meals` are the two keys myOpenGym adds that openGym has no
  default for, and both stay absent from a backup until the feature is used.
- **Progression is derived, never stored.** Fixing a mistyped set from three weeks ago
  immediately produces the right next target, because nothing was cached.

## Tests

```sh
flutter test
```

277 tests. The valuable ones are ports of openGym's own suites — its progression, history,
effort, 1RM and import assertions, running unchanged against the Dart — plus a JSON round-trip
that is the gate on backup compatibility, and a differential check of `weekKey` against the
original's own output across three years of dates.

## Releases

`.github/workflows/android-distribute.yml` builds a signed APK on every push to `main` and hands
it to **Firebase App Distribution**. It needs these repository secrets:

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload.jks` — keep the keystore; updates must be signed with the same key |
| `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` | the rest of the signing config |
| `FIREBASE_APP_ID` | the Android app id from the Firebase console |
| `FIREBASE_SERVICE_ACCOUNT` | a service-account JSON with *Firebase App Distribution Admin* |

Optionally set the `MEDIA_ARCHIVE_URL` repository variable to a tarball of `img/` and `gif/`;
without it CI clones openGym and fetches the media itself.

`versionCode` comes from the workflow run number, so it strictly increases — Android refuses an
update whose code did not go up.

**Size.** The APK is ~156 MB, because the exercise media is bundled for a library that works with
no network at all. Pointing `ExerciseMedia`/`ExerciseThumb` at openGym's jsDelivr CDN instead is a
one-line change that takes it to ~19 MB.

iOS builds unsigned in CI (`ios-build.yml`) to catch breakage early. Signed installs stay a local
Xcode step — Apple does not allow distribution outside the App Store.

## Firebase

This build ships local-only. The seam it goes through is `lib/data/repositories/auth_repository.dart`:

```dart
abstract interface class AuthRepository { … }
abstract interface class RemoteSync    { … }
```

`LocalOnlyAuth` and `NoRemoteSync` are the current implementations. Replacing them with
`firebase_auth` and `cloud_firestore` needs no change to any screen, store or model — the Login
screen already offers the sign-in path whenever `AuthRepository.isAvailable` says it can.

The sync semantics to reproduce are openGym's: push debounced and flushed on background, pull
adopting the remote copy only when `remote._ts >= local._ts` and nothing local is dirty, and a
running workout always preserved across the swap.

## Licence

openGym is AGPL-3.0-or-later, and so is this. Exercise data and media come from
`hasaneyldrm/exercises-dataset` (CC); the body geometry is converted from MuscleMap by
Melih Colpan (MIT); the food catalogue is derived from USDA FoodData Central (public domain)
and the food photography from Openverse (mostly CC BY / CC BY-SA, never NC), credited per image
in `tool/food_media.tsv` and on screen beside each photo. See [NOTICE.md](NOTICE.md).
