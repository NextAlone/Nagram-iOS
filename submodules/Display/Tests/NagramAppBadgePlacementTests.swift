import XCTest
import UIKit
@testable import Display

// MARK: NAGRAM
/// The app badge is centred on the camera housing, which is the hardware's: it is read from the model's own profile,
/// whatever profile the zoomed screen size resolves to.
final class NagramAppBadgePlacementTests: XCTestCase {
    /// A zoomed iPhone 16 Pro Max resolved a notched profile by its screen size and drew the badge at the screen's top
    /// edge, half of it above the island.
    func test_zoomedPhone_usesItsModelsIsland() {
        let resolved = DeviceMetrics(screenSize: CGSize(width: 375.0, height: 812.0), scale: 3.0, statusBarHeight: 50.0, onScreenNavigationHeight: 34.0, modelIdentifier: "iPhone17,2")
        XCTAssertNotEqual(resolved, .iPhone16ProMax)
        XCTAssertEqual(DeviceMetrics.appBadgeCenterY(resolved: resolved, modelIdentifier: "iPhone17,2"), DeviceMetrics.iPhone16ProMax.cutoutFrame?.midY)
    }

    /// The island centres are those of the status bar, which iOS centres on the island (iOS 27 simulator).
    func test_islandCentres_matchTheStatusBar() {
        let cases: [(String, CGFloat)] = [
            ("iPhone17,2", 32.17),
            ("iPhone19,3", 32.17),
            ("iPhone18,3", 32.17),
            ("iPhone18,4", 38.17),
        ]
        for (identifier, statusBarCentre) in cases {
            guard let centre = DeviceMetrics.appBadgeCenterY(resolved: .unknown(screenSize: .zero, statusBarHeight: 0.0, onScreenNavigationHeight: nil, screenCornerRadius: 0.0), modelIdentifier: identifier) else {
                XCTFail(identifier)
                continue
            }
            XCTAssertEqual(centre, statusBarCentre, accuracy: 0.5, identifier)
        }
    }

    func test_unknownModel_fallsBackToTheResolvedProfile() {
        XCTAssertEqual(DeviceMetrics.appBadgeCenterY(resolved: .iPhoneAir, modelIdentifier: "iPhone99,9"), DeviceMetrics.iPhoneAir.cutoutFrame?.midY)
        XCTAssertNil(DeviceMetrics.appBadgeCenterY(resolved: .iPad, modelIdentifier: nil))
    }

    func test_duo_showsNoBadge() {
        XCTAssertNil(DeviceMetrics.appBadgeCenterY(resolved: .iPhoneDuo, modelIdentifier: "iPhone19,4"))
    }
}
