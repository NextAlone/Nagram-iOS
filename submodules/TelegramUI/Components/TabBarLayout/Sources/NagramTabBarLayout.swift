import Foundation
import UIKit
import Display

// MARK: NAGRAM — the bottom-bar layout settings (button width and alignment) over iOS 27's portrait tab bar.

/// Where the bar's items sit when the standalone slot (the search button or an external item) shares the row.
public enum NagramTabBarRowAlignment: Equatable {
    /// The items start at the leading edge, the slot ends the row.
    case leading
    /// The items are centred in the length the slot leaves them, the slot ends the row.
    case centeredBesideSlot
    /// The items and the slot are centred together as one group.
    case centeredWithSlot
}

/// The gap between the items and the standalone slot.
public let nagramTabBarSlotSpacing: CGFloat = 8.0

/// The shortest bar `tabBarSystemItemsLayout` lays `fittedItemWidths` out in without squeezing them: up to three
/// items hug their content 32pt apart, as UIKit's own bar does; more keep their padded widths 14pt apart, the
/// smallest gap UIKit's flexible layout leaves before it shrinks items. Never longer than `availableLength`.
public func nagramTabBarSystemCompactLength(fittedItemWidths: [CGFloat], availableLength: CGFloat, scale: CGFloat = UIScreenScale) -> CGFloat {
    let count = fittedItemWidths.count
    if count == 0 {
        return min(availableLength, tabBarInnerInset * 2.0)
    }
    if count <= 3 {
        return tabBarSystemItemsLayout(fittedItemWidths: fittedItemWidths, availableLength: availableLength, hasAccessory: false, scale: scale).size.width
    }
    let sideInset: CGFloat = count > 4 ? 15.0 : 24.0
    let itemsLength = fittedItemWidths.reduce(0.0) { $0 + max(tabBarSystemItemThickness, $1 + 12.0) }
    let length = sideInset * 2.0 + itemsLength + CGFloat(count - 1) * 14.0
    return min(availableLength, ceil(length * scale) / scale)
}

/// The items of iOS 27's portrait bar under the width setting. `fillRatio` 0 is the compact bar
/// (`nagramTabBarSystemCompactLength`), 1 fills `availableLength`, which already leaves out the standalone slot;
/// between them the items share the bar as UIKit's flexible layout shares it. The slot does not stretch the bar by
/// itself (UIKit's accessory does), or the setting could not shorten a bar that has search.
public func nagramTabBarSystemItemsLayout(fittedItemWidths: [CGFloat], availableLength: CGFloat, fillRatio: CGFloat, scale: CGFloat = UIScreenScale) -> TabBarItemsLayout {
    let ratio = max(0.0, min(1.0, fillRatio))
    if fittedItemWidths.isEmpty {
        return tabBarSystemItemsLayout(fittedItemWidths: fittedItemWidths, availableLength: availableLength, hasAccessory: false, scale: scale)
    }
    let compactLength = nagramTabBarSystemCompactLength(fittedItemWidths: fittedItemWidths, availableLength: availableLength, scale: scale)
    if ratio <= 0.0 && fittedItemWidths.count <= 3 {
        // Exactly UIKit's bar without an accessory.
        return tabBarSystemItemsLayout(fittedItemWidths: fittedItemWidths, availableLength: availableLength, hasAccessory: false, scale: scale)
    }
    let length = floor((compactLength + (availableLength - compactLength) * ratio) * scale) / scale
    return tabBarSystemItemsLayout(fittedItemWidths: fittedItemWidths, availableLength: max(compactLength, length), hasAccessory: true, scale: scale)
}

/// The leading edges of the items (`tabsLength` long) and of the standalone slot (`slotLength`, nil when there is
/// none) in a row `availableLength` long. Without a slot the items start at 0: the bar hugs them and its owner
/// places it.
public func nagramTabBarRowOrigins(tabsLength: CGFloat, slotLength: CGFloat?, availableLength: CGFloat, alignment: NagramTabBarRowAlignment) -> (tabs: CGFloat, slot: CGFloat?) {
    guard let slotLength else {
        return (0.0, nil)
    }
    let tabsArea = max(0.0, availableLength - slotLength - nagramTabBarSlotSpacing)
    let clampedTabsLength = min(tabsLength, tabsArea)
    switch alignment {
    case .leading:
        return (0.0, availableLength - slotLength)
    case .centeredBesideSlot:
        return (floor((tabsArea - clampedTabsLength) * 0.5), availableLength - slotLength)
    case .centeredWithSlot:
        let groupLength = clampedTabsLength + nagramTabBarSlotSpacing + slotLength
        let origin = max(0.0, floor((availableLength - groupLength) * 0.5))
        return (origin, origin + clampedTabsLength + nagramTabBarSlotSpacing)
    }
}
