# Bottom Bar Layout Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Nagram settings subpage that edits the whole bottom bar and top search layout with a live preview.

**Architecture:** Add a pure `NagramBottomBarSettings` model in `Nagram/Settings`, expose derived compatibility values for existing `hideTabBar*`, `showTabBarSearch`, and `wideTabBar` behavior, then connect Telegram root/tab rendering to the new model. Add a `NagramBottomBarSettingsController` under `Nagram/SettingsUI` with a live preview that edits placement only: drag reorders bottom items, drag into the right external slot swaps with the current external item. Actual visibility is controlled by explicit option rows below the preview. Search is constrained to the right standalone button when visible; hiding search releases the standalone slot.

**Tech Stack:** Swift, UserDefaults-backed Nagram settings, ItemListUI, AsyncDisplayKit/UIKit views, existing Telegram `TabBarComponent` integration, Bazel full-app build for verification.

---

### File Structure

- Create `Nagram/Settings/NagramBottomBarSettings.swift`: bottom bar item IDs, placement/order model, layout options, migration/defaults, mutation helpers.
- Create `Nagram/SettingsUI/NagramBottomBarSettingsController.swift`: settings subpage with preview, drag/drop editing, and middle layout options.
- Modify `Nagram/Settings/NagramSettings.swift`: store new settings and map legacy keys.
- Modify `Nagram/SettingsUI/NagramSettingsController.swift`: replace scattered bottom bar rows with a single navigation row.
- Modify `Nagram/SettingsUI/BUILD`: add dependencies needed by the preview view if the glob is not enough.
- Modify `Nagram/Strings/Strings/*.lproj/NagramLocalizable.strings`: add page labels and option labels.
- Modify `submodules/TelegramUI/Sources/TelegramRootController.swift`: use the new model for root controller list updates.
- Modify `submodules/TabBarUI/Sources/TabBarContollerNode.swift`: pass new model to `TabBarComponent`, filter/order items, map the external slot.
- Modify `submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift`: support custom external item, optional labels, width/alignment/slot policy.
- Modify `submodules/ChatListUI/Sources/ChatListController.swift` and `submodules/ChatListUI/Sources/ChatListControllerNode.swift`: use `topSearchVisible` instead of legacy `showTabBarSearch` naming.

### Task 1: Add Bottom Bar Model

**Files:**
- Create: `Nagram/Settings/NagramBottomBarSettings.swift`
- Modify: `Nagram/Settings/NagramSettings.swift`

- [ ] Define `NagramBottomBarItemId` cases: `contacts`, `calls`, `chats`, `settings`, `search`.
- [ ] Define placement as a model with `bottomItems: [NagramBottomBarItemId]`, `externalItem: NagramBottomBarItemId?`, `hiddenItems: Set<NagramBottomBarItemId>`, `topSearchVisible: Bool`, and `searchMode` (`button`, `hidden`; legacy `bar` normalizes to `button`).
- [ ] Define layout options: `showLabels`, `widthMode` (`full`, `adaptive`), `slotMode` (`visibleOnly`, `preserveHidden`), `alignment` (`left`, `center`).
- [ ] Add mutation helpers: `toggleHidden(_:)`, `moveBottomItem(from:to:)`, `moveToExternal(_:)`, `moveToBottom(_:at:)`.
- [ ] Enforce invariants in one normalization path:
  - each item appears once across bottom/external/hidden;
  - external has at most one item;
  - search never enters bottom items; when visible it is the right standalone button, and when hidden it releases the standalone slot;
  - bottom order remains stable when hidden items are restored.
- [ ] Add compatibility accessors so old keys map to the new model until all call sites move.

### Task 2: Add Settings Entry

**Files:**
- Modify: `Nagram/SettingsUI/NagramSettingsController.swift`
- Modify: `Nagram/Strings/Strings/*.lproj/NagramLocalizable.strings`

- [ ] Replace Interface group rows for `HideTabBar*`, `ShowTabBarSearch`, and `WideTabBar` with one navigation row `Nagram.BottomBarLayout`.
- [ ] Keep `HideStories` in the Interface group.
- [ ] Preserve deep-link aliases by mapping old row tokens to the new `BottomBarLayout` row.
- [ ] Add localized names for the page title, reset action, layout options, item names, hidden area, and external slot.

### Task 3: Build Interactive Editor UI

**Files:**
- Create: `Nagram/SettingsUI/NagramBottomBarSettingsController.swift`

- [ ] Build an `ItemListController` page with custom preview item, explicit visibility rows, layout option rows, and reset row.
- [ ] Preview top section renders top search row when `topSearchVisible` is true.
- [ ] Preview bottom section renders bottom items in current order and one external slot on the right.
- [ ] Preview taps do not toggle real visibility; preview is for placement and visual state only.
- [ ] Long-press dragging inside bottom items reorders bottom items.
- [ ] Dragging a bottom item onto the external slot swaps it with the current external item.
- [ ] Dragging an external item back to bottom inserts it at the nearest bottom index.
- [ ] Hidden items render in a hidden area as previews only.
- [ ] Middle option rows expose `topSearchVisible`, five visibility chips in the bottom bar switch row, `showLabels`, `buttonWidthFillRatio`, and `alignment`.
- [ ] The search chip in the bottom bar switch row is two-state: enabled renders search in the right standalone slot; disabled removes it from the slot and from bottom items.
- [ ] Disable or visually de-emphasize alignment when width mode is `full`.

### Task 4: Connect Runtime Bottom Bar

**Files:**
- Modify: `submodules/TelegramUI/Sources/TelegramRootController.swift`
- Modify: `submodules/TabBarUI/Sources/TabBarContollerNode.swift`
- Modify: `submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift`

- [ ] Subscribe to one string/int signal or UserDefaults notification covering the new bottom bar settings and refresh root controllers.
- [ ] Build root controllers from enabled navigational items, but keep hidden controllers available internally so deep links and navigation APIs do not break.
- [ ] Render bottom items in the configured order.
- [ ] Render external slot as the configured item; if search is visible, it reserves the right standalone slot and keeps current search button behavior.
- [ ] If a navigational item is external, route its tap to the same controller selection action as its bottom item.
- [ ] If external slot contains search, route activation to `tabBarActivateSearch`.
- [ ] Apply label visibility only to bottom items; external slot stays icon-only.
- [ ] Apply width mode, slot policy, and alignment to `TabBarComponent`.

### Task 5: Connect Search Visibility

**Files:**
- Modify: `submodules/ChatListUI/Sources/ChatListController.swift`
- Modify: `submodules/ChatListUI/Sources/ChatListControllerNode.swift`
- Modify: `submodules/TelegramUI/Sources/TelegramRootController.swift`

- [ ] Replace legacy `showTabBarSearch` reads with `bottomBarSettings.topSearchVisible` where the UI means top search row visibility.
- [ ] Keep search button placement independent from top search visibility.
- [ ] Ensure search activation/deactivation still restores the configured bottom bar hidden state.

### Task 6: Verification

**Files:**
- Read-only verification across modified files.

- [ ] Run `swift` type-oriented checks when feasible for pure `Nagram/Settings` files.
- [ ] Run full device build through `build-system/Make/Make.py --configuration=debug_arm64 --continueOnError`.
- [ ] If the build succeeds, list connected devices with `xcrun devicectl list devices`.
- [ ] Install `bazel-bin/Telegram/Telegram.ipa` to the available device.
- [ ] Re-read requirements and check each feature:
  - bottom bar settings are one subpage;
  - preview covers top search, bottom items, hidden area, and external slot;
  - preview tap does not toggle visibility;
  - lower option rows toggle top search and the five bottom bar switch chips, with search mapped to the right standalone button;
  - drag reorders;
  - drag to external slot swaps;
  - external slot has at most one item;
  - labels/width/alignment are middle options;
  - runtime bottom bar follows saved settings.

### Self-Review

- Spec coverage: all requested capabilities map to Tasks 1-5; verification and install map to Task 6.
- Placeholder scan: no placeholder implementation steps remain.
- Type consistency: all runtime code reads the same `NagramBottomBarSettings` model and does not keep adding independent booleans.
- Risk notes:
  - The existing project has no test target, so verification is compile/build plus manual install.
  - Full drag/drop in ItemList custom nodes is the riskiest UI piece; if it conflicts with ItemList gestures, the fallback is edit-mode reorder plus tap-to-move external slot while preserving the same settings model.
