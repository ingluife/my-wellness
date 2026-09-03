# Firebase App Distribution — one-time setup

[`.github/workflows/distribute.yml`](../.github/workflows/distribute.yml) builds a
signed release APK and uploads it to Firebase App Distribution. It is a
`workflow_dispatch` job — run it from the **Actions** tab.

The app itself does **not** link the Firebase SDK. App Distribution only needs an
APK, a Firebase **App ID**, and a **service account** that is allowed to publish
releases. There is no `google-services.json`, no `firebase_options.dart`, and no
`com.google.gms.google-services` Gradle plugin.

## 1. Firebase project + Android app

1. <https://console.firebase.google.com> → **Add project** (or reuse one).
2. **Project overview → Add app → Android**.
   - **Android package name:** `com.mywellness.app` (must match
     `applicationId` in [`android/app/build.gradle.kts`](../android/app/build.gradle.kts)).
   - Nickname / debug SHA-1: optional, skip.
   - Skip the "Download google-services.json" and SDK steps — not used here.
3. **Project settings → General → Your apps → Android app** → copy the
   **App ID**. It looks like `1:918273645000:android:abcd1234ef567890`.
   → GitHub secret **`FIREBASE_ANDROID_APP_ID`**.

## 2. Enable App Distribution + tester group

1. Firebase console → **Release & Monitor → App Distribution** → **Get started**.
2. **Testers & Groups → Add group.**
   - Name it anything; set the **group alias** to `testers` (the workflow's
     "Upload to Firebase App Distribution" step hard-codes `groups: testers` —
     change both if you want another alias).
3. Add tester emails to the group. Each tester accepts the invite email once.

## 3. Service account for CI

1. <https://console.cloud.google.com> → same project → **IAM & Admin → Service
   Accounts → Create service account**.
   - Name: `github-app-distribution`.
2. Grant it the role **Firebase App Distribution Admin**
   (`roles/firebaseappdistro.admin`). Nothing else is required.
3. Open the account → **Keys → Add key → Create new key → JSON** → download.
4. Paste the **entire JSON file contents** (not base64, not a path) into GitHub
   secret **`FIREBASE_SERVICE_ACCOUNT_JSON`**.

If the upload step later fails with a permissions error, also enable the
**Firebase App Distribution API** for the project under
**APIs & Services → Enable APIs and services**.

## 4. Release keystore

The Gradle config
([`android/app/build.gradle.kts`](../android/app/build.gradle.kts)) reads
`android/key.properties`; when it is absent the release build falls back to the
debug key, so a fresh clone still builds locally. CI writes both files from
secrets.

Create a keystore once (keep the generated `.jks` somewhere safe and out of git —
losing it means you can never ship an update to the same listing):

```bash
keytool -genkey -v -keystore release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mywellness
```

Then:

```bash
base64 -w0 release.jks    # -> FIREBASE ... paste into ANDROID_KEYSTORE_BASE64
```

| GitHub secret                | Value                                            |
| ---------------------------- | ------------------------------------------------ |
| `ANDROID_KEYSTORE_BASE64`    | `base64 -w0 release.jks`                         |
| `ANDROID_KEYSTORE_PASSWORD`  | the store password you entered                   |
| `ANDROID_KEY_PASSWORD`       | the key password (often the same)                |
| `ANDROID_KEY_ALIAS`          | `mywellness`                                     |

The workflow decodes the keystore to `android/app/release.keystore` and writes
`storeFile=release.keystore` into `key.properties`.

## 5. Exercise media (`media.tar.gz` release asset)

`assets/img/` and `assets/gif/` (1,324 files each, ~121 MB packed) are git-ignored
and are **not** re-fetchable from the original openGym mirror — that repo is gone.
Instead they are attached as a `media.tar.gz` asset to a release on this repo, and
the workflow's **Fetch the exercise media** step pulls it with `gh release
download` (authenticated by the built-in `GITHUB_TOKEN`, which is why this works on
a private repo with no extra secret).

The archive must contain `img/` and `gif/` at its root, so that
`tar -xzf media.tar.gz -C assets` produces `assets/img/…` and `assets/gif/…`. Build
it from a populated checkout with:

```bash
tar -czf media.tar.gz -C assets img gif
```

Publish it once:

```bash
gh release create media-v1 media.tar.gz \
  --repo <owner>/<repo> \
  --title "Exercise media (img + gif)" \
  --notes "1,324 stills + 1,324 animations for tool/sync_media.sh and this workflow."
```

The workflow looks for tag `media-v1` by default. To use a different tag, set the
repository **variable** `MEDIA_RELEASE_TAG` (Settings → Secrets and variables →
Actions → **Variables**). To publish an updated set of media, either replace the
asset on the `media-v1` release (`gh release upload media-v1 media.tar.gz
--clobber`) or cut a new tag and point `MEDIA_RELEASE_TAG` at it.

The step asserts exactly 1,324 files in each of `assets/img` and `assets/gif` and
fails the build otherwise.

> Licensing: this media is under the upstream
> [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)
> terms, not this project's AGPL — see [NOTICE.md](../NOTICE.md). Keeping it in a
> private-repo release asset (not committed, not public) is why that stays
> uncomplicated.

## 6. GitHub environment

The job declares `environment: Production`. Create it under
**Settings → Environments → New environment → `Production`** so you can attach
protection rules / required reviewers. Repository-level secrets are visible to
the job either way; only add **environment** secrets if you want them scoped to
`Production`.

## 7. Secret checklist

Settings → Secrets and variables → Actions → **Secrets**:

- [ ] `FIREBASE_ANDROID_APP_ID`
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON`
- [ ] `ANDROID_KEYSTORE_BASE64`
- [ ] `ANDROID_KEYSTORE_PASSWORD`
- [ ] `ANDROID_KEY_PASSWORD`
- [ ] `ANDROID_KEY_ALIAS`

**Variables** (optional):

- [ ] `MEDIA_RELEASE_TAG` — only if the media asset lives on a tag other than
  `media-v1`

## 8. Run it

1. Merge `distribute.yml` to the default branch (workflows only appear in the
   Actions tab from the default branch).
2. **Actions → Build & Distribute (Firebase App Distribution) → Run workflow**,
   optionally typing release notes.
3. On success the release shows up in Firebase console → App Distribution, and
   testers in the `testers` group get an email.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `unable to find directory entry in pubspec.yaml: assets/img/` | media step didn't populate assets — `media.tar.gz` missing from the `media-v1` release, or wrong `MEDIA_RELEASE_TAG` |
| `release not found` in the fetch step | the `media-v1` release / `MEDIA_RELEASE_TAG` tag doesn't exist on this repo |
| `Requested entity was not found` on upload | wrong `FIREBASE_ANDROID_APP_ID`, or service account is in a different project |
| `PERMISSION_DENIED` on upload | service account missing `roles/firebaseappdistro.admin`, or App Distribution API not enabled |
| APK installs but won't update later | `versionCode` didn't increase — `flutter build apk --release` uses `pubspec.yaml` version; bump it or pass `--build-number` |
| Build signed with debug key | `key.properties` not written — a keystore secret is missing/empty |
