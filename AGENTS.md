# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What is Nagram-iOS

A third-party enhancement fork of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), targeting Chinese users. Enhances the base app with additional features aligned with Android [Nagram](https://github.com/NextAlone/Nagram).

## Nagram Fork Conventions

- **All Nagram additions go in `Nagram/`** (following upstream `SG*` naming convention). This directory contains `Settings/` (data layer, `NagramSettings`) and `SettingsUI/` (UI layer, `NagramSettingsController`).
- **Upstream code changes must be annotated** with `// MARK: NAGRAM` at the modification site. This makes it possible to track and rebase onto upstream releases.
- **Settings entry point:** the Nagram settings page appears as an independent group below "我的资料" (My Profile) in the PeerInfo screen. Implementation: `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` (the `SettingsSection.nagram` enum case + item at id 50). The PeerInfoScreen BUILD file depends on `//Nagram/SettingsUI:NagramSettingsUI`.
- **App icon:** Icon Composer `.icon` directory at `Telegram/Telegram-iOS/Nagram.icon`; set via `composer_icon_folders = ["Nagram"]` in `Telegram/BUILD` (line ~317).
- **App name:** `CFBundleDisplayName` / `CFBundleName` set to "Nagram" in the main app's `TelegramInfoPlist` section of `Telegram/BUILD` (lines ~1553–1558). Extension plist targets (AppNameInfoPlist) are left as "Telegram".

## Build

The app uses Bazel via the `build-system/Make/Make.py` wrapper. There is no per-module build — the only supported invocation builds the full `Telegram/Telegram` target.

`--continueOnError` (forwards to bazel `--keep_going`) lets all errors surface in one pass. Prefix build commands with `source ~/.zshrc 2>/dev/null;` if they need `TELEGRAM_CODESIGNING_GIT_PASSWORD`.

### local.bazelrc (gitignored, not committed)

The repo `.bazelrc` ends with `try-import %workspace%/local.bazelrc`. This file controls whether extensions and provisioning are built. Pick exactly one signing mode first.

Full/formal device signing with app + extension profiles:

```
# Do not set disableExtensions.
# Do not set disableProvisioningProfiles.
```

Free Apple ID device signing:

```
build --//Telegram:disableExtensions
```

Simulator-only, codesigning-free:

```
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
```

`disableExtensions` skips the 6 app extensions (`Share`, `NotificationContent`, `NotificationService`, `Intents`, `Widget`, `BroadcastUpload`). It is allowed for free Apple IDs and simulator-only builds, but **must not be used when full/formal provisioning profiles are present**. Full signing needs profiles for `Telegram` plus all 6 extensions.

`disableProvisioningProfiles` is simulator-only. Never use it for device builds; it makes provisioning resolve to `None` and fails.

`Make.py build` does not accept `--disableExtensions` or `--disableProvisioningProfiles` as command-line arguments. Put Bazel build settings in `local.bazelrc`, or use direct Bazel.

**Warning:** `bazel clean --expunge` (which `Make.py clean` runs) deletes `local.bazelrc`. Recreate it after cleaning.

Full/formal local signing should use the gitignored codesigning directory:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

### Simulator build (codesigning-free, fastest)

Set simulator-only flags in `local.bazelrc` first:

```
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
```

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

Output: `bazel-bin/Telegram/Telegram.ipa`.

Install to booted simulator (**must uninstall first** — `simctl install` does not replace existing Frameworks dylibs):

```sh
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim
xcrun simctl uninstall booted ph.telegra.Telegraph 2>/dev/null
xcrun simctl install booted /tmp/tg-sim/Payload/Telegram.app
```

### Device build (free Apple ID, self-signed)

Requires `build-input/local-configuration.json` (gitignored via `build-input/*`). Fields match `build-system/template_minimal_development_configuration.json`:

```json
{
  "bundle_id": "com.example.nagram",
  "api_id": "<your_api_id>",
  "api_hash": "<your_api_hash>",
  "team_id": "<certificate OU field, NOT the CN serial>",
  "app_center_id": "0",
  "is_internal_build": "true",
  "is_appstore_build": "false",
  "appstore_id": "0",
  "app_specific_url_scheme": "na",
  "premium_iap_product_id": "",
  "enable_siri": false,
  "enable_icloud": false
}
```

**team_id** is the `OU` field from the certificate subject (not the serial in parentheses):
```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

Free Apple ID provisioning must be generated by Xcode: create an empty project with Bundle Identifier exactly matching `bundle_id`, run to device once. Then copy the `.mobileprovision` to where Bazel looks:

```sh
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
   ~/Library/MobileDevice/Provisioning\ Profiles/
```

For free Apple IDs only, `local.bazelrc` may disable extensions:

```
build --//Telegram:disableExtensions
```

Build and install:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError

xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <UDID> /tmp/tg-device/Payload/Telegram.app
```

First launch: trust the developer certificate in Settings → General → VPN & Device Management. Free certificates expire every 7 days.

**Known limitation:** Xcode 26.5 + rules_xcodeproj "Build with Bazel" mode is incompatible (Permission denied writing framework Info.plist). Use command-line build + `devicectl` instead.

## Project Structure

- **`Telegram/`** — main app target, app extensions, Info.plist (including Nagram's `.icon` and display name)
- **`Nagram/`** — all Nagram enhancement code (`Settings/`, `SettingsUI/`)
- **`submodules/`** — library modules (TelegramCore, TelegramUI, Display, SwiftSignalKit, Postbox, etc.)
- **`third-party/`** — vendored external code
- **`build-system/`** — Bazel build rules, Make.py wrapper, configuration templates
- **No tests exist** in this project. Verification is full-project build + manual testing.

## Code Style

Standard Swift conventions: PascalCase types, camelCase variables/methods, sorted imports. Annotation for Nagram-specific changes uses `// MARK: NAGRAM`.

## Postbox → TelegramEngine Refactor

A gradual upstream migration to eliminate direct `import Postbox` from consumer submodules. Full history in [`docs/superpowers/postbox-refactor-log.md`](docs/superpowers/postbox-refactor-log.md).

### Rules

1. `TelegramCore` does **not** `@_exported import Postbox`. Every Postbox-type reference in a migrated module must use an engine typealias.
2. **Never typealias `Postbox`, `Account`, or `MediaBox`.** Narrow utility typealiases (`MemoryBuffer`, `PostboxDecoder`, `PostboxEncoder`, etc.) are allowed.
3. No new engine wrapper structs unless the wave spec allows — only typealiases and thin forwarding methods.
4. **Discovery first:** grep `submodules/TelegramCore/Sources/TelegramEngine/` for existing equivalents before adding any new wrapper.
5. **TelegramCore never imports UIKit/Display.** UIKit-needing helpers stay in consumer-side submodules.

### Engine Typealias Cheat Sheet

```
PeerId              → EnginePeer.Id          MessageId           → EngineMessage.Id
MessageIndex        → EngineMessage.Index    MessageTags         → EngineMessage.Tags
MessageAttribute    → EngineMessage.Attribute MessageFlags       → EngineMessage.Flags
MessageForwardInfo  → EngineMessage.ForwardInfo MediaId           → EngineMedia.Id
PreferencesEntry    → EnginePreferencesEntry    TempBox           → EngineTempBox
PinnedItemId        → EngineChatList.PinnedItem.Id
MemoryBuffer        → EngineMemoryBuffer       PostboxDecoder    → EnginePostboxDecoder
PostboxEncoder      → EnginePostboxEncoder     AdaptedPostboxDecoder → EngineAdaptedPostboxDecoder
ItemCollectionId    → EngineItemCollectionId   FetchResourceSourceType → EngineFetchResourceSourceType
FetchResourceError  → EngineFetchResourceError
```

`EngineMediaResource` is a **wrapper class** (not a typealias) — it wraps/unwraps via `EngineMediaResource(rawResource)` / `._asResource()`. Use it where a pure type reference suffices; fall back to raw `MediaResource` for protocol conformance or `isEqual(to:)`.

### TelegramEngine.Resources Facade (as of wave 32)

All mediaBox methods with clean signatures live in `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`. Consumers use `EngineMediaResource.Id` / `EngineMediaResource` parameters (never raw `MediaResourceId` / `MediaResource`).
