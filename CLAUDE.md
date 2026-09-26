# CLAUDE.md

This file provides guidance to AI assistants when working with code in this repository.

## Nagram fork conventions

Nagram-iOS is a Chinese-user-focused enhancement fork of Telegram-iOS, aligned where appropriate with Android Nagram.

- New Nagram-only code belongs under `Nagram/`.
- Every necessary upstream-file modification must have a nearby `// MARK: NAGRAM`.
- The Nagram settings entry is maintained in `PeerInfoSettingsItems.swift`.
- The main app name and Nagram icon integration are maintained in `Telegram/BUILD`; extension names remain Telegram unless explicitly changed.

## Build

The app uses Bazel via `build-system/Make/Make.py`. There is no supported per-module app build; validation builds the full `Telegram/Telegram` target. Use `--continueOnError` to forward Bazel's `--keep_going`.

Signing flags belong in the gitignored `local.bazelrc`:

```
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
```

These two flags are for simulator builds. Device builds must never disable provisioning profiles; full/formal signing with all seven profiles must also keep all six extensions enabled. Free Apple ID signing may disable extensions only. `Make.py clean` runs `bazel clean --expunge` and can remove `local.bazelrc`.

Simulator build:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

Full/formal device build:

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

For physical-device work, first follow the signing-mode and preflight requirements in `docs/build.md`; success requires producing the IPA, installing it with `devicectl`, and verifying the install.

`Make.py test` defaults to `Tests/AllTests` and accepts `--target <label>`. App-side unit tests are minimal; `//submodules/TextFormat:TextFormatTests` covers the mention/date link codecs, and `//Tests/NagramSessionMigrationTests` covers the session-import datacenter-migration error parsing. Note that `Tests/AllTests` does **not** currently list `TextFormatTests` — run that one with `--target`. The RichTextEditor SwiftPM package has its own `swift test` / `Scripts/iostest.sh` suite.

## Code Style Guidelines

- **Naming**: PascalCase for types, camelCase for variables/methods
- **Imports**: Group and sort imports at the top of files
- **Error Handling**: Properly handle errors with appropriate redaction of sensitive data
- **Formatting**: Use standard Swift/Objective-C formatting and spacing
- **Types**: Prefer strong typing and explicit type annotations where needed
- **Documentation**: Document public APIs with comments

## Project Structure

- Nagram-only code belongs in `Nagram/`; reactive settings use `Nagram/SettingsSignal`, and UI belongs in `Nagram/SettingsUI`.
- Main app and extension targets are in `Telegram/`.
- Most upstream libraries are in `submodules/`; modifications there require a nearby `// MARK: NAGRAM`.
- Vendored external code is in `third-party/`.
- Build rules, wrapper, and configuration templates are in `build-system/`.
- App-side unit tests are minimal: the first `ios_unit_test` (`//submodules/TextFormat:TextFormatTests`) was added 2026-06-19 (run via `Make.py test --target` — see Build); `//Tests/NagramSessionMigrationTests` is the second. Nagram's session-backup codec tests (`Tests/NagramSessionBackupTests`) are **not** a Bazel target — they are compiled with plain `swiftc` by `scripts/test-session-backup-interop.sh`, which also cross-checks the format against a Python Pyrogram reference and Mithka's own Dart decoder. The RichTextEditor SwiftPM package keeps its own suite (`swift test` / `Scripts/iostest.sh`). Most modules still have no tests.

## RichTextEditor editor & the `ChatInputContent` composer

A from-scratch WYSIWYG rich-text editor (`submodules/TelegramUI/Components/RichTextEditor`) is the native chat-composer backend — by default a **dual-field switch** (the composer uses the legacy input and latches to the native editor only when content becomes legacy-non-representable); the `forceNewTextInput` experimental flag (Debug Settings ▸ "Force Text Field v2") forces always-native. (This inverted the earlier default+`forceLegacyTextInput`-opt-out scheme.) `ChatInputContent` (a TelegramCore-native value model) replaced `NSAttributedString` as the composer currency. The app-side integration — the model and its load-bearing invariants, composer ↔ editor wiring, the formatting-menu / custom-emoji-mention-date / code-block / inline-media round-trips, rich-message send / edit / pending-display, the long-press-Send send-options preview, and draft persistence (local, cross-device media sync, re-login restore) — lives in [`docs/richtext-composer.md`](docs/richtext-composer.md). Editor internals (the TextKit seam, layout) are the editor's own `submodules/TelegramUI/Components/RichTextEditor/CLAUDE.md`; message **rendering** is [`docs/instantpage-richtext.md`](docs/instantpage-richtext.md).

## Embedded watch app (`Telegram/WatchApp`)

A standalone watchOS Telegram client (developed in the separate `~/build/tgwatch` repo) is vendored into this repo at `Telegram/WatchApp/` and can be embedded into the **device** IPA under `Telegram.app/Watch/`. It is built by `xcodebuild` (not Bazel) and codesigned by the Bazel build.

**Build it:** add `--embedWatchApp` to a Make.py **device** build (`--configuration=debug_arm64` or `release_arm64`) together with `--watchApiId`, `--watchApiHash`, `--watchSigningIdentity`, `--watchProvisioningProfile`. Off by default (it adds a ~4-min xcodebuild step); simulator builds never embed, and the default `debug_sim_arm64` build is unaffected.

**`Telegram/WatchApp/` is a synced snapshot — do not hand-edit it.** The source of truth and dev tooling live in the `tgwatch` repo. To change the watch app, edit it there, then re-sync with `tgwatch/tools/export-sources.sh /abs/path/to/telegram-ios/Telegram/WatchApp` and commit the result. The committed `tgwatch.xcodeproj` is generated (kept via a `!tgwatch.xcodeproj` negation in `Telegram/WatchApp/.gitignore`, since the root `.gitignore` ignores `*.xcodeproj`); `.build`/`.swiftpm`/`xcuserdata` are excluded.

**How it's wired:** `//Telegram:TelegramWatchApp` (rule in `Telegram/prebuilt_watchos.bzl`) runs in **two actions**: `PrebuiltWatchosCompile` (`Telegram/prebuilt_watchos_compile.sh`) runs xcodebuild on the snapshot in a writable temp copy with PLACEHOLDER version/api values (the bundle ids are baked from the snapshot's pbxproj/Info.plist — `ph.telegra.Telegraph.watchkitapp` / `ph.telegra.Telegraph`), emitting an unsigned `.app`; `PrebuiltWatchosPatchSign` (`Telegram/prebuilt_watchos_patch.sh`) then rewrites **six** per-build Info.plist keys (`CFBundleShortVersionString`, `CFBundleVersion`, `TG_API_ID`, `TG_API_HASH`, `CFBundleIdentifier`, `WKCompanionAppBundleIdentifier`) and codesigns the `.app` + nested `TDLibFramework.framework` (identity + the watchkitapp profile from `--define`s). The result feeds the `Telegram` `ios_application`'s `watch_application` slot (gated by the `//Telegram:embedWatchApp` flag). The rule takes `bundle_id` (set to `"{telegram_bundle_id}.watchkitapp"` in `Telegram/BUILD`) and derives the host bundle id by stripping the `.watchkitapp` suffix; both are passed to the patch worker as args (not action inputs), so the patch action re-runs when the host bundle id changes but the (expensive) compile stays cached. **The compile action's only inputs are the snapshot (+ its worker)** — so changing the version, build number, api id/hash, host bundle id, or signing identity re-runs only the cheap patch+sign action, not xcodebuild; xcodebuild re-runs only when the snapshot changes. This is correct because none of those values reach the compiled binary: each lands only in the Info.plist (via `$(...)` substitution and a runtime `Bundle.main.object(forInfoDictionaryKey:)` lookup in `Secrets.swift`, except for the bundle-id keys which only Info.plist consumers read).

**Non-obvious invariants** (also in the `.bzl` comments): `AppleBundleInfo`'s public init is banned — use the internal `new_applebundleinfo`; `watch_application` requires BOTH `AppleBundleInfo` (with a non-None `infoplist` File) AND `WatchosApplicationBundleInfo`; the embedded watch app's `CFBundleShortVersionString`/`CFBundleVersion` must exactly equal the host's (sourced from `versions.json['app']` + `--define=buildNumber`); the host does NOT re-sign the embedded watch app, so the worker must sign it; the watch bundle id `ph.telegra.Telegraph.watchkitapp` must track the host `telegram_bundle_id`.

**Status:** verified with **development** signing on `debug_arm64` only. Open follow-ups before App Store shipping: secure timestamp (drop `codesign --timestamp=none`), distribution profile (`get-task-allow=false`), `release_arm64` + `altool --validate-app`, and committing a `Package.resolved` for hermetic remote-SwiftPM resolution.

## View frame ownership

A view does not control its own `frame`. The parent (or a layout system) sets the frame; the view positions its own subviews against `self.bounds` in response.

This matters in two places specifically:

- **Reusable components (`UIView`/`ASDisplayNode` subclasses).** Public methods like `update(...)` / `apply(...)` rebuild internal state, mutate child frames, and read `self.bounds` to lay them out — but they do not write `self.frame`. The caller has already chosen the frame; mutating it from inside the component overrides that choice and fights the parent's next layout pass.
- **`asyncLayout`-style content nodes.** The measure pass runs off-main and returns a size; the apply step runs on main and the chat layout system positions the node. A child view that writes `self.frame` from `update()` corrupts the size the parent just measured.

Rare exceptions: top-level view-controller views integrating with the system's first-responder/inset model. If you find yourself wanting `self.frame = …` from inside a child view, refactor so the parent positions it instead.

## ChatHistoryListNode composition

`ChatHistoryListNodeImpl` (`submodules/TelegramUI/Sources/ChatHistoryListNode.swift`) **composes** rather than inherits `ListViewImpl` (`submodules/Display/Source/ListView.swift`): it is an `ASDisplayNode` wrapper holding `private let listView: ListViewImpl` and exposes a deliberately narrowed surface (the `ChatHistoryListNode` protocol in `AccountContext` + curated concrete forwarders) instead of the full `ListView` API. `ListViewImpl` gained a `getCustomItemDeleteAnimationDuration` closure hook so the one former `override` works via composition.

These invariants are **compiler-invisible** — getting them wrong silently breaks the app's primary scroll surface:

- **The π rotation stays on the wrapper** (chat is bottom-up). The wrapper keeps `transform = π` + a `rotated` flag; the child `listView` gets only `rotated = true` (identity transform). So `historyNode.view`/`.layer` remain the rotated surface, and rotation-coupled code — hitTest coordinate conversions, the blur `drawHierarchy` flip, the dust/delete layer, `.layer` animations, and the overscroll-overlay + snapshot-slide reparenting — **stays on `self` (the wrapper)** unchanged.
- **Only genuine scroll-surface concerns route to the child:** gesture recognizers (selection pan; external taps via `addContentGestureRecognizer`) attach to `self.listView.view` to share the scroll pan's simultaneity environment, and scroller access goes to `self.listView.scroller`.
- **`let _ = self.view` in `init` is load-bearing.** The old inherited node was view-loaded eagerly (so `self.isNodeLoaded` was always true); `enqueueHistoryViewTransition` gates the history dequeue on it. The wrapper must force-load its view in init or off-screen nodes (created during thread switches) never become ready and `reloadChatLocation`'s completion never fires.
- **Item nodes are one level deeper.** Any `.supernode` chain / hierarchy-depth assumption passing through the history node gained one level (item → child `listView` → wrapper). E.g. `ChatMessageTransitionNode` converts item rects up `supernode?.supernode?.supernode?.view` (was 2 hops) so the wrapper's rotation is applied as an intermediate transform; a missing hop reflects effect-burst overlays ~180°.
- Child geometry is driven inside `updateLayout` via `transition.updateFrame(node: self.listView, …)` — the project never relies on ASDisplayNode's automatic `layout()`.

The public surface is being narrowed incrementally (e.g. `scroller` → `bounces`/`contentHeight`; the `trackingOffset`/`beganTrackingAtTopOrigin` pair → `didInteractivelyDragFromTopOrigin`). Prefer intent-named accessors over re-exposing raw `ListView` state.

## InstantPage V2 & rich-text messages

Typed markdown with structure the regular message-entity set can't represent (headings, lists, tables, formulas, nested blockquotes) is sent as a **rich message** — a `RichTextMessageAttribute` carrying an `InstantPage`, drawn by `ChatMessageRichDataBubbleContentNode` via the **InstantPage V2** renderer (with AI-streaming progressive reveal, inline custom emoji, and entity cases). The detailed architecture and non-obvious invariants — streaming reveal, V2 table/text-box layout, custom-emoji & entity round-trips, task-list checkboxes, nested blockquotes, thinking blocks, the markdown send / edit / copy / paste paths, and surfacing rich-message media through the shared-media/gallery/preview pipelines via `Message.effectiveMedia` — live in [`docs/instantpage-richtext.md`](docs/instantpage-richtext.md).

## Postbox → TelegramEngine refactor (in progress)

A gradual migration is underway to eliminate direct `import Postbox` from consumer submodules in favor of `TelegramEngine`.

**Historical record:** Wave-by-wave outcomes, the running tally of Postbox-free modules, the full wave-selection guidance, and the `TelegramEngine.Resources` facade inventory (also authoritatively defined in `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`) live in [`docs/superpowers/postbox-refactor-log.md`](docs/superpowers/postbox-refactor-log.md). Read that file when you need wave-specific context, a full worked example of a pattern, or the history of a particular module's migration.

See the log for per-wave detail; the current wave count and the list of still-open migration opportunities live in the `project_postbox_refactor_next_wave.md` memory file.

### Rules that apply to every wave

1. `TelegramCore` does **not** `@_exported import Postbox`. Once a consumer drops `import Postbox`, every remaining Postbox-type reference must use an engine-typealiased equivalent.
2. **Never typealias `Postbox`, `Account`, or `MediaBox`.** These umbrella types rename without encapsulating. Narrow utility typealiases (`MemoryBuffer`, `PostboxDecoder`, `PostboxEncoder`, `AdaptedPostboxDecoder`, `MediaResource`, …) remain allowed and expected.
3. No new engine wrapper **structs** unless the wave's spec explicitly allows — only typealiases and thin forwarding methods.
4. **Discovery first:** before adding any new engine wrapper/typealias, grep `submodules/TelegramCore/Sources/TelegramEngine/` for existing equivalents. Record the search result in the commit message.
5. **Abandonment protocol:** if a module can only be refactored by violating rule 2 or by editing a module outside the current wave's list, mark the task Abandoned with a recorded reason. Do NOT substitute a new module mid-wave.
6. Full project build per module. No unit tests exist in this project.
7. **TelegramCore never imports UIKit/Display.** `TelegramCore` is shared with the Telegram-Mac codebase; its Bazel `deps` and source files must not reference UIKit, Display, or any Apple-UI framework. UIKit-needing helpers (image scaling, rendering, etc.) stay in consumer-side submodules.
8. **Never substitute Postbox protocols (`Media`, `Peer`, `Message`) with `Any` / `AnyObject`** in code that previously used them. Type erasure throws away the domain semantics that the next reader expects. Use the matching engine wrapper (`EngineMedia`, `EnginePeer`, `EngineMessage`) — extending it as needed (e.g. add a missing case-init or convenience). If neither typealias nor wrapper covers the use site, restore the original Postbox import + type for now and flag the case for a future facade. Existing `Any`/`AnyObject` parameters predating the refactor are not in scope for this rule.

### Engine typealias cheat sheet (existing aliases)

```
PeerId              → EnginePeer.Id
MessageId           → EngineMessage.Id
MessageIndex        → EngineMessage.Index
MessageTags         → EngineMessage.Tags
MessageAttribute    → EngineMessage.Attribute
MessageFlags        → EngineMessage.Flags
MessageForwardInfo  → EngineMessage.ForwardInfo
MediaId             → EngineMedia.Id
PreferencesEntry    → EnginePreferencesEntry
TempBox             → EngineTempBox
PinnedItemId        → EngineChatList.PinnedItem.Id
MemoryBuffer        → EngineMemoryBuffer           (added 2026-04)
PostboxDecoder      → EnginePostboxDecoder         (added 2026-04)
PostboxEncoder      → EnginePostboxEncoder         (added 2026-04)
AdaptedPostboxDecoder → EngineAdaptedPostboxDecoder (added 2026-04)
ItemCollectionId    → EngineItemCollectionId       (added 2026-04-20)
FetchResourceSourceType → EngineFetchResourceSourceType (added 2026-04-20)
FetchResourceError  → EngineFetchResourceError     (added 2026-04-20)
StoryId             → EngineStoryId                (added 2026-05-02)
ChatListIndex       → EngineChatListIndex          (added 2026-05-03)
TempBoxFile         → EngineTempBoxFile            (added 2026-05-03)
ItemCollectionItemIndex → EngineItemCollectionItemIndex (added 2026-05-03)
ItemCollectionViewEntryIndex → EngineItemCollectionViewEntryIndex (added 2026-05-03)
ValueBoxEncryptionParameters → EngineValueBoxEncryptionParameters (added 2026-05-03)
MessageAndThreadId  → EngineMessageAndThreadId      (added 2026-05-03)
PeerStoryStats      → EnginePeerStoryStats          (added 2026-05-03)
MessageHistoryAnchorIndex → EngineMessageHistoryAnchorIndex (added 2026-05-03)
ChatListTotalUnreadStateCategory → EngineChatListTotalUnreadStateCategory (added 2026-05-03)
ChatListTotalUnreadStateStats → EngineChatListTotalUnreadStateStats (added 2026-05-03)
PeerSummaryCounterTags → EnginePeerSummaryCounterTags (added 2026-05-03)
ChatListTotalUnreadState → EngineChatListTotalUnreadState (added 2026-05-04)
ItemCacheEntryId    → EngineItemCacheEntryId        (added 2026-05-04)
HashFunctions       → EngineHashFunctions           (added 2026-05-04 wave 251)
CachedMediaResourceRepresentationResult → EngineCachedMediaResourceRepresentationResult (added 2026-05-04 wave 265)
MediaResourceDataFetchResult → EngineMediaResourceDataFetchResult (added 2026-05-04 wave 266)
MediaResourceDataFetchError → EngineMediaResourceDataFetchError (added 2026-05-04 wave 266)
MediaResourceStatus → EngineMediaResourceStatus     (added 2026-05-04 wave 272)
```

**Free-function thin forwarders in TelegramCore** (rule 3 allows):
- `engineFileSize(_ path:, useTotalFileAllocatedSize: Bool = false)` — forwards to Postbox's `fileSize(...)` (added 2026-05-04 wave 268)

**TelegramEngineUnauthorized.resources facade**: `UnauthorizedResources.storeResourceData(id: EngineMediaResource.Id, data:, synchronous:)` — bridges to `account.postbox.mediaBox.storeResourceData` (added 2026-05-04 wave 271)

For the `MediaResource` Postbox protocol, prefer the TelegramCore subtype `TelegramMediaResource` when the consumer's usage allows (note: `EngineMediaResource` is a wrapper **class**, not a typealias, so it is not interchangeable with the protocol).

### MediaResource → EngineMediaResource consumer migration

`EngineMediaResource` is a `final class` in `TelegramCore` wrapping a `MediaResource` value. Unlike the typealiases above it is **not** interchangeable with the protocol, but it does provide wrap/unwrap helpers:

- `EngineMediaResource(rawResource)` — wrap a raw `MediaResource`.
- `engineResource._asResource()` — unwrap to the raw `MediaResource`.
- `EngineMediaResource.ResourceData(rawResourceData)` — wrap `MediaResourceData`.
- `EngineMediaResource.Id(rawMediaResourceId)` — wrap `MediaResourceId`.

**Pattern for facade functions:** when a `TelegramEngine.<Area>` method leaks raw `MediaResource` in its public signature, **change the facade signature in place** to `EngineMediaResource` (and change any closure parameter types the same way). Bridge inside the facade body by calling the existing `_internal_*` function with `engineResource._asResource()` / wrapping raw inputs from inner closures with `EngineMediaResource(rawResource)`. Update all call sites in the same commit. The `_internal_*` function stays on raw `MediaResource` — it is the Postbox-facing layer.

Do **not** add opt-in `EngineMediaResource` overloads alongside raw-`MediaResource` overloads. Duplicate signatures fragment the public API and leave the leak in place forever.

For consumer modules, prefer `EngineMediaResource` as the type in properties, locals, generic arguments and function parameters when the usage is a pure type reference. Do **not** try to use `EngineMediaResource` where a class must conform to `TelegramMediaResource` (Postbox protocol) or override `isEqual(to: MediaResource)` — those remain `import Postbox`.

## tgcalls Testbench

This repo includes a tgcalls testbench (CLI tool, Go/Pion SFU, Docker build) layered on top of the iOS source. All testbench code, build instructions, and architecture docs live inside the tgcalls submodule:

- `submodules/TgVoipWebrtc/tgcalls/CLAUDE.md` — top-level testbench overview, build/run commands
- `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` — CLI test tool architecture
- `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md` — Go SFU internals
- `submodules/TgVoipWebrtc/CLAUDE.md` — tgcalls library internals + macOS/Linux build patches

Build the test binary from this directory with:

`./build-input/bazel-8.4.2 build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli`
