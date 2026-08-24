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

## Layout

```
lib/
├── data/models/          AppState and everything in it — the JSON contract with openGym
├── data/repositories/    persistence, and the auth/sync seam
├── domain/               pure logic, ported 1:1 from openGym's lib/
│                         history · progression · effort · onerm · muscles · format
│                         i18n · glyphs · exercises · starter · import_csv · plan_share
├── platform/             notifications, wake lock, backup/share
├── state/                the two stores: persisted state, and ephemeral UI state
└── ui/
    ├── theme/            every token from openGym's index.css
    ├── widgets/          the control set, the icon set, and three CustomPainters
    │                     (line chart, heatmap, body map)
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
Melih Colpan (MIT).
