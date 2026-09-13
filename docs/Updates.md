# Fluxa Direct updates

## Current release — 2.9.2 (21)

Fluxa Direct uses Sparkle **2.9.4**, pinned in `Package.swift` and `Package.resolved`.
The source and app contain the real public signing key and the production
[HTTPS appcast](https://zehmsy.github.io/fluxa/updates/appcast.xml).

[Release v2.9.2](https://github.com/zEhmsy/fluxa/releases/tag/v2.9.2) uses build **21** and is the
item the production feed advertises. Published 2026-09-13 from `main` at `ccfa1fe`, with the feed
commit `58a0d8d` on `codex/updates-feed`. Signed with the stable **Fluxa Code Signing** certificate.

Before publication the archive signature was verified twice: with the pinned
`sign_update --account fluxa.direct --verify`, and independently with OpenSSL against only the
`SUPublicEDKey` embedded in the app. Both published assets were downloaded back from the release and
matched their local SHA-256 byte for byte:

```
09e1941098b0ae32c7d89d90b1088227b67ca2f7807630f3ce38c272cd53bfaa  Fluxa.zip
f033c6fc5dd3fdf51644924915b401ed5274d4d490895dae1841a3af83f8f429  Fluxa.dmg
```

The feed edit was purely additive — 61 inserted lines, every earlier item byte-identical.

**A near miss worth repeating as a rule.** The first generated appcast was seeded from a stale
`origin/codex/updates-feed`, which predated the 2.9.1 item, and it would have silently dropped 2.9.1
from the feed. Only the non-fast-forward push rejection caught it. **Fetch the publishing branch and
seed the generator from the branch tip, never from a local ref, and diff the item set before
pushing** — the generator reports "removed 0 old updates" against its own input, not against what is
live.

### What 2.9.2 contains

The menu bar icon investigation (ticket 18) and its two real causes, the Customize tab scrolling fix,
two-column agent chips, the Antigravity permissions card, and tickets 16 and 17. Full notes are
embedded in the feed item and in the GitHub release.

Build **19** was prepared but never published, and its release notes claimed the icon bug was fixed
when it was not. Nothing advertises build 19 or 20; the feed goes 18 → 21.

### Earlier: release 2.6.1 (10)

[Release v2.6.1](https://github.com/zEhmsy/fluxa/releases/tag/v2.6.1) uses build **10**.
Its `Fluxa.zip` preserves the exact bytes accepted by the owner; `Fluxa.dmg` packages the same
signed app. The installer name, volume title, artwork and English first-launch guide are preserved.
Versions v2.5.0 and earlier do not include Sparkle: install the new DMG manually once.

### Acceptance record

On 2026-08-28 the owner completed the real **2.6.0 (9) → 2.6.1 (10)** update through an isolated
HTTPS feed and reported success. The installed app's version and signature were verified, then the
temporary `SUFeedURL` preference was removed. The Mac now uses the production feed again.
A fresh release build also matched the accepted archive file-for-file, mode-for-mode and link-for-link.

This establishes the observed owner-run upgrade path, not exhaustive regression or clean-machine
coverage. No assistant-run functional/UI tests or automated test suite were performed. Ad-hoc code
identity changes can still require renewed OS permission or credential-access approval.

The acceptance feed and immutable archive remain under `updates-test/` on Pages as historical test
assets. They are not the production update source. Private rollback files and signing backups stay
outside the repository and release assets.

## App behavior

`AppDelegate` owns `AppSettings` and the app-lifetime `PopoverViewModel`. Its launch callback starts
the model's single `UpdateService`, which owns `SPUStandardUpdaterController`. Nothing waits for
the popover to appear. Sparkle's standard windows handle checking, downloading and installation.
The About action dismisses the popover before showing the update window. Normal termination still
calls `PopoverViewModel.cleanup()` to release keyboard locks, overlays and active assertions.

About exposes readiness and the most recent check/error. Customize observes Sparkle's
`automaticallyChecksForUpdates` and changes it only on user action. There is no duplicate
`AppSettings` preference or custom update timer. `SUEnableAutomaticChecks` is omitted so Sparkle
asks for consent on its normal schedule (normally the second launch). The default interval is
daily. `SUAllowsAutomaticUpdates=false` keeps download/installation behind user confirmation;
system profiling is disabled. These choices follow the
[Sparkle configuration guide](https://sparkle-project.org/documentation/customization/) and
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/).

## Hosted feed and deferred product website

Pages serves the isolated **`codex/updates-feed`** branch at `/`. Application source lives on `main`;
the publishing branch contains the technical root redirect, `.nojekyll`, production appcast and
historical acceptance files. Production appcast updates must preserve all existing archives and
use immutable GitHub Release enclosure URLs. Upload and verify release assets before advertising them.

The owner deferred the product presentation website to a later implementation. A future site can
replace the root redirect, but must retain `/fluxa/updates/appcast.xml` in every complete Pages
deployment. If switching to an Actions-built site, include the feed and preserved acceptance assets
in the deployment artifact. Keep production app downloads on GitHub Releases.

## Trust configuration and verified backup

The key is in the developer's login Keychain, account **`fluxa.direct`**, service
`https://sparkle-project.org`. A backup was exported directly into an AES-256 encrypted disk image
under `~/Library/Application Support/Fluxa/Signing Backups`, outside the checkout. The directory
is 0700 and the image is 0600. The owner chose and confirmed the password in native hidden macOS
dialogs; it was not sent through chat, command arguments or logs. No plaintext private-key file
was written outside the encrypted volume. The backup was detached, mounted read-only, verified by
deriving the public key again, and detached. Recovery instructions accompany the image.

A copy on this Mac does not protect against loss of the computer. Retain an additional encrypted
copy on a separate medium before wider distribution, and keep its password separately accessible.
Losing the sole signing key can strand an ad-hoc installation. See
[Sparkle's signing guidance](https://sparkle-project.org/documentation/).

Sparkle's pinned tools are under `.build/artifacts/sparkle/Sparkle/bin/`. Reuse this Keychain account
for every release; do not generate a replacement key by habit. `generate_keys --account fluxa.direct -p`
reads only the public key into its output. Export with `-x` only to an approved encrypted destination,
never into the repository, logs, chat or release artifacts. Restore with `-f` only from a verified
backup on an authorized Mac, without overwriting an unrelated existing account.

Only these public values belong in `Sources/Fluxa/Resources/Info.plist`:

- `SUFeedURL`: `https://zehmsy.github.io/fluxa/updates/appcast.xml`.
- `SUPublicEDKey`: `CkRk7WevzhjWm8DTQDDI4eqXc2Tvx+aGvmWFPCSfEe0=`.

Keep increasing `CFBundleVersion`: 9 was the local bootstrap, 10 is release 2.6.1, and **21** is the
current release 2.9.2. Use a build greater than 21 for the next changed release or candidate. Builds
19 and 20 were prepared and never published, so the numbers are spent either way — a prepared build
number is never reused, whether or not it shipped. Do not reuse any already published release or
mutate its assets. Rebuild after any plist edit; both the executable
and the bundle contain that plist. Default builds and packagers require both real trust fields.
`--development` permits only an unconfigured local build with both fields absent, never a release.

Updates require an Ed25519 archive signature and HTTPS. `SUVerifyUpdateBeforeExtraction=true`
enforces verification before unpacking. This integration does **not** enable `SURequireSignedFeed`:
an archive signature does not also authenticate feed text or release notes. Feed signing is a
separate possible extension. Developer ID, notarization and CI secrets remain separate work; no verification or Gatekeeper bypass is part of this setup.

## Building and preserving the signed bundle

`build.sh` forces arm64, resolves the pinned package, and relinks even for plist-only changes.
It copies the entire Sparkle framework with `ditto`, preserving symlinks, executable permissions,
vendor architectures and helpers. Fluxa is arm64 only; the upstream framework/helpers retain
their universal slices. The app has `@executable_path/../Frameworks` in its runtime search paths.
The development Xcode toolchain rpath is removed from **Fluxa's executable**, before signing.

Ad-hoc builds preserve all Sparkle signatures byte-for-byte. A certificate identity — which is the
default for releases since 2.9.1 (18) — uses Sparkle's documented inside-out signing order,
preserving Downloader entitlements, then signs the outer app. There is no recursive `--deep`
signing. This is not a notarization workflow. See
[Sparkle helper signing](https://sparkle-project.org/documentation/sandboxing/#code-signing).

`packaging/verify-bundle.py` checks signatures, the app architecture and OS/build metadata,
matching embedded/packaged plists, framework version against the lockfile, helper executability,
runpaths and trust fields. With `--vendor-source`, it also compares every upstream file, mode
and symlink target. These are static artifact checks, not launch or upgrade tests.

`FLUXA_STABLE_LOCAL_REQUIREMENT=1` is for local builds only. Both distribution packagers reject
the weaker identifier-only signing requirement. Never reset TCC, remove quarantine or disable
Gatekeeper to make a build/update work.

Releases before 2.9.1 (18) were ad-hoc signed, so their designated requirement was the binary's own
cdhash and every update presented itself to macOS as a different app — which is why each one asked
users for keychain and Accessibility access again. The release identity is now a stable self-signed
certificate, so those grants carry across updates. The 2.9.1 update is the last that re-asks, since
it is itself the identity change. Gatekeeper is unaffected either way: a self-signed certificate is
not Apple-trusted, so first launch of a download still needs explicit approval.

## Preparing an authorized release

Keep the approved manual installer (`Fluxa.dmg`, volume **Fluxa**, English guide) unchanged.
A separate **Fluxa.zip** is used for Sparkle, from the same signed app. Build once and package
both before rebuilding or installing a different signing identity.

The following recipe was exercised locally for the bootstrap and acceptance ZIP. For a new release, set
`FLUXA_RELEASE_DIR` to a new local release directory and `FLUXA_RELEASE_TAG` to the explicitly
chosen new tag; these commands do not pick a version or publish anything.

```bash
: "${FLUXA_RELEASE_DIR:?Choose a new release directory}"
: "${FLUXA_RELEASE_TAG:?Choose the new immutable release tag}"
mkdir -p "$FLUXA_RELEASE_DIR/update"
./build.sh
./package-dmg.sh --output "$FLUXA_RELEASE_DIR/Fluxa.dmg"
./package-update.sh --output "$FLUXA_RELEASE_DIR/update/Fluxa.zip"
```

Paths should be absolute. Both packagers refuse existing output files. The ZIP packager extracts
a private copy and checks that every signed file, mode and symlink survived; it never runs Fluxa.
It does not access the signing key, and the ZIP is **not yet Ed25519-signed**.

For subsequent releases, copy the current authoritative `appcast.xml` into the new `update/`
directory first. Archive the old feed and every old signed ZIP/DMG separately, preserving their
checksums and signatures. Do not put the DMG beside the ZIP in the generator's input folder:
they contain the same build. With the agreed Keychain account and backup available:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account fluxa.direct \
  --maximum-deltas 0 --maximum-versions 0 \
  --download-url-prefix "https://github.com/zEhmsy/fluxa/releases/download/$FLUXA_RELEASE_TAG/" \
  -o "$FLUXA_RELEASE_DIR/update/appcast.xml" \
  "$FLUXA_RELEASE_DIR/update"
```

The Keychain account and encrypted backup are verified. Generation accesses the private key through
Sparkle. Never pass private key bytes as command-line arguments or add `--disable-nested-code-check`.

Inspect the generated item: correct increasing build, marketing version, macOS 14 minimum,
arm64 requirement, archive length, signature and **tag-specific HTTPS enclosure URL**. Verify
the signature with the pinned `sign_update --account fluxa.direct --verify` command and ensure
the signing account's public key matches the app's `SUPublicEDKey`. The verify tool also accesses
the Keychain; keep that step owner-controlled. Compare previous feed items to ensure their URLs,
lengths and signatures remain unchanged. Both prepared ZIP signatures passed the pinned verification
tool and an independent OpenSSL Ed25519 verification using only the configured public key.

Do not use `/releases/latest/download/Fluxa.zip` (or `Fluxa.dmg`) as a signed enclosure: old items
must always download their original bytes. Only after explicit publication authorization, upload
the assets to the chosen release, check their downloaded hashes, then publish the updated feed.
Keep earlier assets available. See [publishing updates](https://sparkle-project.org/documentation/publishing/).

## Acceptance checklist for future releases

The initial owner-run 9 → 10 upgrade passed as recorded above. Before subsequent releases, arrange
owner checks in proportion to the changed behavior:

1. Check About/Customize and the three appearances without resetting preferences.
2. Perform an upgrade from an older build, including normal cleanup and relaunch.
3. Check manual/automatic consent, offline operation, interruption, skipped versions, rejected
   signatures and unwritable install locations. Installation must require confirmation.
4. Check preferences/history and OS permission behavior, including explicit Claude reconnection
   after a changed ad-hoc identity. Include a clean non-developer Apple-silicon Mac when available.

The installed accepted build 10 has the normal ad-hoc release signature. Any older local-only
identifier-signed rollback app must never be distributed. Keep earlier apps/archives available for
recovery; do not reset TCC or remove quarantine to make an update pass.

Local release artifacts are retained in ignored `.build/releases/`, one directory per release —
`2.9.2-21` is the current one, alongside the earlier `v2.6.1/` — each holding the exact published ZIP
and DMG, the appcast before and after, hashes and release notes. The private signing key is not in
any release folder.

### 2.9.2 (21) — acceptance status

**Not owner-accepted as an upgrade.** The artifacts were verified statically, as recorded above, and
the build was installed and run from `/Applications` on the owner's Mac, where the menu bar item was
confirmed present through the Accessibility API. No Sparkle upgrade from an older build was
exercised for this release, and none of items 2 through 4 of the checklist above were performed.

Two behaviours in this release deserve owner attention at the next opportunity:

- Updating from **2.9.0 or earlier** crosses the ad-hoc → certificate identity change and re-asks for
  Accessibility and keychain access once. 2.9.1 and 2.9.2 both cross it for anyone who skipped 2.9.1.
- A user whose icon is missing because of the Control Center allow-list (ticket 18, defect B) cannot
  be helped by this or any other build. The release notes say so and invite an issue. There is no
  in-app detection for it, which is worth considering as its own ticket.
