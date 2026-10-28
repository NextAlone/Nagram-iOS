You are an experienced, pragmatic software engineering AI agent. Do not over-engineer a solution when a simple one is possible. Keep edits minimal. If you want an exception to ANY rule, you MUST stop and get permission first.

# AGENTS.md

This file guides AI agents working in this repository. It is specific to Nagram-iOS and should be kept in sync with the repo, not with generic Telegram-iOS assumptions.

## Project Overview

Nagram-iOS is a third-party enhancement fork of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), targeting Chinese users and aligning selected features with Android [Nagram](https://github.com/NextAlone/Nagram). The goal is to keep the fork easy to rebase onto upstream Telegram while adding Nagram-specific settings, UI, translation, privacy, and interaction features.

Technology stack:

- iOS app code in Swift, Objective-C, Objective-C++, C, and C++.
- Bazel workspace (`WORKSPACE`, `MODULE.bazel`) with a custom Python wrapper at `build-system/Make/Make.py`.
- Xcode/iOS SDK toolchains; expected versions are tracked in `versions.json`, while local build caveats live in `docs/build.md`.
- Telegram modules under `submodules/` (`TelegramCore`, `TelegramUI`, `Display`, `SwiftSignalKit`, `Postbox`, etc.) plus vendored native dependencies under `third-party/`.

## Reference

Important directories:

- `Nagram/` — all new Nagram feature code. Main modules are `Settings/`, `SettingsSignal/`, `SettingsUI/`, `Strings/`, and `Translate/`.
- `Telegram/` — main app target, app extensions, app plist fragments, icons, and app-level Bazel rules.
- `submodules/` — upstream Telegram libraries. Modify only when a feature must integrate with upstream code, and mark the edit.
- `third-party/` — vendored dependencies. Avoid style-only or opportunistic changes here.
- `Tests/` — Bazel test/demo targets; `Tests/AllTests/BUILD` currently includes `//submodules/TgVoipWebrtc:TgCallsTests`.
- `Telegram/Tests/Sources/` — XCUITest sources for the generated Xcode project.
- `docs/` — build notes, UI testing notes, and the Postbox-to-TelegramEngine migration log.

Important files:

- `README.md` and `docs/build.md` — signing modes, build commands, and current local toolchain pitfalls.
- `.bazelrc` — imports gitignored `local.bazelrc`; local signing/provisioning flags belong there.
- `build-system/Make/Make.py` — supported build/test/clean/query entry point.
- `Telegram/BUILD` — app target, plist fragments, Nagram app name, strings, and icon integration.
- `Nagram/Settings/NagramSettings.swift` — central Nagram settings store.
- `Nagram/SettingsSignal/Sources/NagramSettingsSignal.swift` — reactive settings bridge.
- `Nagram/SettingsUI/NagramSettingsController.swift` — Nagram settings UI entry controller.
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` — Settings screen Nagram entry point (`SettingsSection.nagram`, item id `50`).
- `docs/superpowers/postbox-refactor-log.md` — source of truth for the Postbox migration waves.

## Essential Commands

Full app builds are the only reliable validation path for app changes. There is no supported per-module build workflow for this fork.

### Device build hard gate

For any request to build for or install on a physical iPhone, follow this order before selecting a signing mode or starting a build:

1. Read `docs/build.md` sections “签名模式选择”, “真机构建强制预检”, “在 workspace / worktree 构建真机包”, and the matching signing-mode section.
2. Check the connected device, Apple Development identity, main-app and all 6 extension profiles, `build-input/local-configuration.json`, `build-input/codesigning-development/`, Bazel rule/submodule directories, and signing flags in `local.bazelrc`.
3. If the app and all 6 extension profiles are available, use full signing. Never set `disableExtensions` or `disableProvisioningProfiles`.
4. Missing gitignored `build-input` files in an isolated jj workspace do **not** imply free-signing mode. Restore them from the operator-approved private source first; do not inspect another workspace without explicit permission.
5. Use free Apple ID signing only when complete profiles are genuinely unavailable and the user requested that mode. It may disable extensions, but never provisioning profiles.
6. Empty Bazel rule/submodule directories are dependency failures, not signing failures. Do not change signing mode to work around them. If recovery requires a `git` command, request explicit authorization for that exact command under the jj-only policy.
7. Do not claim a device build succeeded until the IPA is produced, installed with `devicectl`, and the install result is verified.

### Build

Simulator-only, codesigning-free setup:

```sh
cat > local.bazelrc <<'EOF'
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
EOF

python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

Full/formal device signing needs app plus all 6 extension profiles (`Share`, `NotificationContent`, `NotificationService`, `Intents`, `Widget`, `BroadcastUpload`). Do not disable extensions in that mode:

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

Free Apple ID device signing may disable extensions, but must not disable provisioning profiles. See `docs/build.md` before changing signing flags.

### Install

Simulator install must uninstall first; `simctl install` does not replace existing Frameworks dylibs reliably:

```sh
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim
xcrun simctl uninstall booted ph.telegra.Telegraph 2>/dev/null
xcrun simctl install booted /tmp/tg-sim/Payload/Telegram.app
```

Device install:

```sh
xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <UDID> /tmp/tg-device/Payload/Telegram.app
```

### Test

Bazel test wrapper (`debug_sim_arm64`, target `Tests/AllTests`):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  test \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning
```

UI tests require a generated `Telegram/Telegram.xcodeproj` and a matching simulator. Always pass `--ui-test`; see `docs/ui-testing.md`.

```sh
xcodebuild test \
  -project Telegram/Telegram.xcodeproj \
  -scheme iOSAppUITestSuite \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
```

### Format and lint

No dedicated repo-wide formatter or lint command was found. Follow local Swift style, keep imports sorted, and rely on Bazel/Swift warnings-as-errors for touched targets. Do not run broad auto-formatting over upstream files.

### Clean

```sh
python3 build-system/Make/Make.py clean
```

`Make.py clean` runs `bazel clean --expunge`; recreate `local.bazelrc` afterward if it disappears.

### Development server

There is no development server. Build the app, then run it in a simulator or install it on a device.

### Other scripts

List shell scripts before using one:

```sh
find . -path './.jj' -prune -o -type f -name '*.sh' -print | sort
```

Prefer `build-system/Make/Make.py` for app build/test/clean. Use `build-system/generate-xcode-project.sh`, `build-system/verify.sh`, `Telegram/*Icon*.sh`, and `third-party/*/build-*-bazel.sh` only when the task specifically calls for them.

## Nagram Fork Patterns

- Put new Nagram-only code under `Nagram/`. Keep `Nagram/Settings` as the low-level data layer and `Nagram/SettingsUI` as the UI layer.
- When upstream files must change, annotate the modification site with `// MARK: NAGRAM`. This is required for upstream rebases.
- The Nagram settings entry appears below “我的资料” (My Profile) in `PeerInfoSettingsItems.swift`; long press opens Nagram debug settings.
- Main app display name is `Nagram` in `Telegram/BUILD` (`CFBundleDisplayName` / `CFBundleName`). Extension plist targets remain `Telegram` unless a task explicitly changes that behavior.
- App icon integration is in `Telegram/BUILD`: `alternate_icon_folders` includes `Nagram`, and Composer source icons include `Nagram`, `NagramBlock`, and `NagramColorful`.
- Settings defaults should preserve native Telegram behavior unless the feature explicitly requires a different default. Existing settings use `@NagramDefault` and sync through local `UserDefaults` plus iCloud KVS.
- Use `NagramSettingsSignal` helpers when UI must react live to setting changes. Do not add ad-hoc polling.

## Postbox → TelegramEngine Refactor

A gradual upstream migration is eliminating direct `import Postbox` from consumer submodules. Read `docs/superpowers/postbox-refactor-log.md` before touching this area.

Rules:

1. `TelegramCore` does not `@_exported import Postbox`; migrated modules must use engine typealiases for Postbox-type references.
2. Never typealias `Postbox`, `Account`, or `MediaBox`. Narrow utility typealiases such as `MemoryBuffer`, `PostboxDecoder`, and `PostboxEncoder` are allowed.
3. Do not add new engine wrapper structs unless the wave spec allows it. Prefer typealiases and thin forwarding methods.
4. Search `submodules/TelegramCore/Sources/TelegramEngine/` for existing equivalents before adding a wrapper.
5. `TelegramCore` must not import UIKit or Display. UIKit-dependent helpers stay in consumer-side submodules.

Common mappings:

```text
PeerId              → EnginePeer.Id          MessageId           → EngineMessage.Id
MessageIndex        → EngineMessage.Index    MessageTags         → EngineMessage.Tags
MessageAttribute    → EngineMessage.Attribute MessageFlags       → EngineMessage.Flags
MessageForwardInfo  → EngineMessage.ForwardInfo MediaId           → EngineMedia.Id
PreferencesEntry    → EnginePreferencesEntry TempBox             → EngineTempBox
PinnedItemId        → EngineChatList.PinnedItem.Id
MemoryBuffer        → EngineMemoryBuffer     PostboxDecoder      → EnginePostboxDecoder
PostboxEncoder      → EnginePostboxEncoder   AdaptedPostboxDecoder → EngineAdaptedPostboxDecoder
ItemCollectionId    → EngineItemCollectionId FetchResourceSourceType → EngineFetchResourceSourceType
FetchResourceError  → EngineFetchResourceError
```

`EngineMediaResource` is a wrapper class, not a typealias. It wraps/unwraps via `EngineMediaResource(rawResource)` and `._asResource()`. Use it when a pure type reference is enough; use raw `MediaResource` only for protocol conformance or `isEqual(to:)`.

## Anti-Patterns

- Do not put Nagram-only feature code into upstream `submodules/` when it can live in `Nagram/`.
- Do not edit upstream files without a nearby `// MARK: NAGRAM` marker.
- Do not pass `--disableExtensions` or `--disableProvisioningProfiles` to `Make.py build`; those are Bazel flags for `local.bazelrc`, not Make.py build arguments.
- Do not use `disableProvisioningProfiles` for device builds.
- Do not disable extensions when full/formal provisioning profiles are present.
- Do not mix functional changes with whitespace cleanup.
- Do not treat stale-submodule errors (`tgcalls` missing files, WebRTC/FFmpeg API mismatches) as app code failures; verify submodule state first. The upstream README uses Git commands for this, so ask for explicit authorization before running them in a jj-only agent workspace.
- Do not add production-data UI tests. XCUITests must launch with `--ui-test` so they use isolated data and Telegram test servers.

## Code Style

- Follow existing Swift conventions: PascalCase types, camelCase members, sorted imports, clear names over abbreviations.
- Keep changes localized and boring. Prefer existing Telegram/Nagram helpers over new abstractions.
- New Nagram Bazel modules should use `swift_library`, public visibility only when needed, and `copts = ["-warnings-as-errors"]` like the existing Nagram targets.
- Boundary code should fail loudly with actionable errors; avoid silent fallback paths unless the product behavior explicitly requires one.
- Do not commit debug prints, `debugger`, temporary TODOs, or commented-out old implementations.

## Commit and Pull Request Guidelines

Use `jj` in this workspace. The upstream `.github/CONTRIBUTING.md` is Git-oriented human guidance; AI agents should not run Git commands unless the user explicitly authorizes a concrete command in the current turn.

Before editing:

```sh
jj st
jj log -r @ -n 1 --no-graph
```

Before committing:

- Re-read the request and confirm the change scope did not drift.
- Run the narrowest useful validation, then a full app build when the touched area can affect compilation or runtime behavior.
- For docs-only changes, at minimum inspect the Markdown and run `jj diff --git`.
- Do not modify tests to fit a broken implementation.

Commit messages in recent history use `type: summary`, especially `feat:`, `fix:`, `chore:`, and `docs:`. Prefer one focused change per commit:

```sh
jj commit -m "docs: improve agent guide"
```

Pull request descriptions should include:

- Summary of user-visible or developer-visible changes.
- Validation commands and whether they passed, failed, or were skipped with a reason.
- Screenshots or screen recordings for UI changes.
- Signing/build mode used for validation (`debug_sim_arm64`, `debug_arm64`, full profiles, free Apple ID, etc.).
- Rebase or upstream-touch notes for every modified upstream file with `// MARK: NAGRAM`.

Do not create or open a PR unless the user explicitly asks for it.

## Visual features and animations: judge them from recorded frames

A green build and passing unit tests say nothing about how a change looks or moves. For any visual change, and always
for one that animates, record the simulator while it happens, turn the recording into images of its frames labelled
with their index and time, and evaluate the animation from those before calling the work done. Unit tests pin the
model (a choreography's values, a layout's frames); only the frames show what is drawn: what is clipped, what pops in,
what moves together and what lags, where it overshoots and whether it settles.

### 1. Know what correct looks like first

Write down, before recording, what the frames should show: which elements move, which move together, the direction,
roughly how long, whether a spring should overshoot and how many times, what must never be visible (a gap, a clipped
edge, an element standing still while its neighbours move). The evaluation is a comparison against this; without it
the frames only get described.

### 2. Record

Recording is passive: it does not touch the installed app or its state. Installing or replacing the app is not; follow
`CLAUDE.md` and the user's standing instructions on which simulator an agent may install on, and otherwise ask the user
to install the build and then record what they or you trigger.

```sh
U=<simulator udid>                       # xcrun simctl list devices booted
OUT=<scratch directory>                  # not the repo
xcrun simctl io "$U" recordVideo --codec=h264 --force "$OUT/anim.mp4" > "$OUT/rec.log" 2>&1 &
REC=$!
until grep -q "Recording started" "$OUT/rec.log"; do sleep 0.1; done
# … trigger the animation: XcodeBuildMCP taps/swipes, a deep link (xcrun simctl openurl), or ask the user …
sleep 1                                  # let it settle on camera
kill -INT $REC; wait $REC                # SIGINT finalizes the file
```

- Use `simctl io recordVideo`, not XcodeBuildMCP's `record_sim_video`: the latter resamples to a fixed rate (30 fps by
  default), which hides exactly the frame-level detail being looked for.
- The recording is **variable-rate**. The simulator writes a frame only when the screen changes, stamped with its own
  time (1/600 s units), at the display's rate while something moves (16.7 ms median on an iPhone 17 / iOS 26.5
  simulator, 10 ms on the iPhone 18 Pro / iOS 27 one; the script prints it). A still screen produces no frames, so a
  stall appears as one long interval, and time must always come from a frame's timestamp, never from its index. It
  also writes the odd near-copy a few ms after a frame.
- **Take the timestamps from `ffprobe`, never from `ffmpeg`.** The file can carry a duplicated timestamp, after which
  `ffmpeg` (its `showinfo`, its `select` on `t`) falls back to each frame's decode time, seconds behind (measured:
  11.66 s, then 8.07 s for the next frame); the frames themselves still come out in order. The script handles this;
  anything hand-rolled must too.
- Frames are the device's pixels (3x: a 402 × 874 pt screen records at 1206 × 2622).
- A tap at a point, where XcodeBuildMCP offers only element taps: `axe touch -x X -y Y --down --up --delay 0.08
  --udid "$U"` (points). Issue it in the same shell command as the recording, so the tap lands a known time into it.
- Record the whole gesture with a little still time on both sides, once per path the change touches (open and close,
  each entry point, light and dark, with and without the optional content), and in slow motion only in addition to
  real speed, never instead: timing is part of what is being judged.

### 3. Turn it into frames

```sh
python3 tools/animation_sheet.py "$OUT/anim.mp4" "$OUT/sheet" --start 0.4 --end 1.6 \
  [--crop X,Y,W,H] [--track NAME=X,Y,W,H ...] [--tile-width 200] [--columns 8] [--rows 4]
```

All geometry is in points (the recording's pixels over `--scale`, 3 by default): `--crop`, `--track` and every number
it prints.

It writes, into the output directory:

- `sheet-NN.png`: every frame in the range, tiled in time order, each labelled `#index  t=seconds  +ms since the
  previous frame`, with flagged frames framed in red. Open them with the image-reading tool.
- `motion.png`: per frame, how much the picture changed since the previous frame (bars), the interval since the
  previous frame (dots, dashes at the median) and how far the picture still is from the last frame (green line).
- `tracks.png` (with `--track`): each tracked region's offset from its resting place per frame, one line each.
- `frames.tsv`: the same numbers per frame, with the region that changed and each track's offset and match error.
- `frames/NNNNN.png`: the frames themselves, numbered as on the sheets.

and prints a summary: when the motion starts and stops, when it comes within 2% of its resting state for good, every
time it passes its rest and comes back out (a spring's overshoot, an oscillation), every flagged frame, each track's
path and how far apart the tracks ever are:

- `gap`: an interval over 1.5x the median while the picture changes by at least 5% of the clip's largest change: a
  frame drawn late, or a stall (a spinner or caret drawing at its own lower rate is not counted).
- `jump`: a frame that changed over 3x as much as the frames around it: a snap, a teleport, something appearing or
  vanishing at once in the middle of smooth motion.

**Tracks are the precise instrument.** `--track NAME=X,Y,W,H` names a region of the LAST frame (the rest; for
something leaving, a close, pass `--track-reference first` and name it in the first frame); in every frame the script finds where that content stands, shifted vertically, and reports the offset in points: negative
above its rest, positive below, 0 at rest. One track gives an element's real path (where it starts, how far past its
rest it goes, when it is within 1 pt); several give "these move together" as a number: in every frame where all are
found their offsets must agree. Pick each region inside one element, with texture (text, icons, edges), clear of
anything that moves differently, and get its coordinates from the last frame (`frames/` holds it at points scale).
Matches are only as good as the template: text that is still changing size or colour, or that lies over content
changing behind it (a photo, a pattern fading in), reads as not found (`-`) or, worse, as a confident wrong offset in a
handful of frames; rows that look alike (list rows) can match one another. Trust a stretch where several tracks
agree, and check a disagreement on the sheet before reporting it.

Use `--start`/`--end` to keep only the motion (the summary's times are the recording's own clock) and `--crop` to look
at one part of the screen: the distance-from-rest curve and the change bars measure whatever is in the picture. Mind
the scale: a 200 px tile of a 402 pt screen is half a pixel per point, so a 9 pt overshoot moves 4–5 px on the sheet;
crop and raise `--tile-width` until the motion being judged is visible.

### 4. Evaluate

- **Shape.** The green line is the motion's shape: an ease-out falls to 0 and stays; a spring falls, touches its rest
  and rises again by its overshoot before settling, once per oscillation; a step in it is a hitch. Compare the summary's
  duration, settle time and passes with what was intended. The pass percentages are of the picture's difference, not
  of the travel distance: use them to tell whether it overshoots and how many times, and read the amount off the
  frames.
- **Togetherness.** For "these move together", track each element: elements that move as one stand at the same
  offset in every frame, overshoot included, which the summary's pairwise "apart by at most" states. An element that
  rests while its neighbours move, arrives a frame late or overshoots alone is the defect class this catches. Elements
  on one spring but with different travel overshoot in proportion to their travel: same phase, different amplitude.
- **Every flagged frame.** Open the tiles around it and say what it is. A `jump` can be legitimate (an element meant
  to appear at once); a `gap` on the simulator can be the Mac's. A gap that recurs at the same point across several
  recordings is the app's; frame pacing itself is confirmed on a device, not the simulator.
- **The frames, not just the numbers.** Read the sheets end to end for what no metric sees: clipping, a wrong z-order
  for a frame, a colour flash, text re-wrapping mid-flight, an element drawn twice during a hand-over.

Report findings with their evidence, by frame: "#23–#31 (t=0.512–0.645): the list stays at rest while the buttons
overshoot 9 pt" names something another agent or the user can open and check. A claim about an animation without frame
references has not been verified.
