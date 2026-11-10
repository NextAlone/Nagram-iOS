import XCTest
import UIKit
import Display
import TabBarLayout

// MARK: NAGRAM — the bottom-bar width and alignment settings.
final class NagramTabBarLayoutTests: XCTestCase {
    private let twoItems: [CGFloat] = [40.0, 44.0]

    func test_width_zero_isUIKitsBarWithoutAccessory() {
        // Two items hug their content: 24 * 2 + 32 + 54 * 2 = 188.
        let result = nagramTabBarSystemItemsLayout(fittedItemWidths: self.twoItems, availableLength: 300.0, fillRatio: 0.0, scale: 3.0)
        let official = tabBarSystemItemsLayout(fittedItemWidths: self.twoItems, availableLength: 300.0, hasAccessory: false, scale: 3.0)
        XCTAssertEqual(result, official)
        XCTAssertEqual(result.size.width, 188.0)
    }

    func test_width_full_fillsTheAvailableLength() {
        let result = nagramTabBarSystemItemsLayout(fittedItemWidths: self.twoItems, availableLength: 300.0, fillRatio: 1.0, scale: 3.0)
        XCTAssertEqual(result.size.width, 300.0)
    }

    func test_width_half_isHalfwayBetweenCompactAndFull() {
        let result = nagramTabBarSystemItemsLayout(fittedItemWidths: self.twoItems, availableLength: 300.0, fillRatio: 0.5, scale: 3.0)
        XCTAssertEqual(result.size.width, 244.0)
    }

    func test_width_growsWithTheRatio() {
        // The search button used to make UIKit's flexible layout fill the row at every ratio; the available
        // length already leaves the button out, so every step must lengthen the bar.
        var previous: CGFloat = 0.0
        for step in 0 ... 10 {
            let width = nagramTabBarSystemItemsLayout(fittedItemWidths: self.twoItems, availableLength: 300.0, fillRatio: CGFloat(step) / 10.0, scale: 3.0).size.width
            XCTAssertGreaterThan(width, previous, "ratio \(step * 10)%")
            previous = width
        }
    }

    func test_width_fourItems_zeroHugsInsteadOfFilling() {
        // 24 * 2 + 54 * 4 + 14 * 3 = 306.
        let items: [CGFloat] = [40.0, 40.0, 40.0, 40.0]
        let result = nagramTabBarSystemItemsLayout(fittedItemWidths: items, availableLength: 400.0, fillRatio: 0.0, scale: 3.0)
        XCTAssertEqual(result.size.width, 306.0)
        XCTAssertLessThanOrEqual(result.itemFrames.last?.maxX ?? 0.0, result.size.width)
        XCTAssertEqual(nagramTabBarSystemItemsLayout(fittedItemWidths: items, availableLength: 400.0, fillRatio: 1.0, scale: 3.0).size.width, 400.0)
    }

    func test_width_compactNeverExceedsTheAvailableLength() {
        let items: [CGFloat] = [80.0, 80.0, 80.0, 80.0, 80.0]
        XCTAssertEqual(nagramTabBarSystemCompactLength(fittedItemWidths: items, availableLength: 300.0, scale: 3.0), 300.0)
    }

    func test_rowOrigins_withoutSlot_startAtZero() {
        for alignment in [NagramTabBarRowAlignment.leading, .centeredBesideSlot, .centeredWithSlot] {
            let origins = nagramTabBarRowOrigins(tabsLength: 200.0, slotLength: nil, availableLength: 360.0, alignment: alignment)
            XCTAssertEqual(origins.tabs, 0.0)
            XCTAssertNil(origins.slot)
        }
    }

    func test_rowOrigins_withSlot() {
        // 360 - 62 - 8 = 290 for the items.
        let leading = nagramTabBarRowOrigins(tabsLength: 200.0, slotLength: 62.0, availableLength: 360.0, alignment: .leading)
        XCTAssertEqual(leading.tabs, 0.0)
        XCTAssertEqual(leading.slot, 298.0)

        let besideSlot = nagramTabBarRowOrigins(tabsLength: 200.0, slotLength: 62.0, availableLength: 360.0, alignment: .centeredBesideSlot)
        XCTAssertEqual(besideSlot.tabs, 45.0)
        XCTAssertEqual(besideSlot.slot, 298.0)

        // 200 + 8 + 62 = 270, centred in 360.
        let withSlot = nagramTabBarRowOrigins(tabsLength: 200.0, slotLength: 62.0, availableLength: 360.0, alignment: .centeredWithSlot)
        XCTAssertEqual(withSlot.tabs, 45.0)
        XCTAssertEqual(withSlot.slot, 253.0)
    }

    func test_rowOrigins_neverOverlapTheSlot() {
        for alignment in [NagramTabBarRowAlignment.leading, .centeredBesideSlot, .centeredWithSlot] {
            for tabsLength in stride(from: CGFloat(100.0), through: 290.0, by: 10.0) {
                let origins = nagramTabBarRowOrigins(tabsLength: tabsLength, slotLength: 62.0, availableLength: 360.0, alignment: alignment)
                let slot = origins.slot ?? 0.0
                XCTAssertGreaterThanOrEqual(origins.tabs, 0.0)
                XCTAssertGreaterThanOrEqual(slot - (origins.tabs + tabsLength), 8.0, "\(alignment) \(tabsLength)")
                XCTAssertLessThanOrEqual(slot + 62.0, 360.0)
            }
        }
    }

    func test_rowOrigins_fullItems_sameForEveryAlignment() {
        for alignment in [NagramTabBarRowAlignment.leading, .centeredBesideSlot, .centeredWithSlot] {
            let origins = nagramTabBarRowOrigins(tabsLength: 290.0, slotLength: 62.0, availableLength: 360.0, alignment: alignment)
            XCTAssertEqual(origins.tabs, 0.0)
            XCTAssertEqual(origins.slot, 298.0)
        }
    }
}
