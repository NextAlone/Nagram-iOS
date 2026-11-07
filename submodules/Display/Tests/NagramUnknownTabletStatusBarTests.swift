import XCTest
import UIKit
@testable import Display

// MARK: NAGRAM
/// An iPad newer than the device table is recognized before its scene reports a status bar.
final class NagramUnknownTabletStatusBarTests: XCTestCase {
    /// iPad mini (A20 Pro), 756x1158pt, captured with no status bar frame: the first layout drew the navigation bar
    /// under the status bar until a rotation re-read the frame.
    func test_unrecognizedTablet_withoutCapturedHeight_usesTheTabletStatusBar() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 1158.0, height: 756.0), scale: 2.0, statusBarHeight: 0.0, onScreenNavigationHeight: nil, modelIdentifier: "iPad19,1")
        XCTAssertEqual(metrics.type, .tablet)
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 1158.0, height: 756.0)), 24.0)
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 756.0, height: 1158.0)), 24.0)
    }

    /// A height the system did report is kept.
    func test_unrecognizedTablet_keepsACapturedHeight() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 1158.0, height: 756.0), scale: 2.0, statusBarHeight: 32.0, onScreenNavigationHeight: nil, modelIdentifier: "iPad19,1")
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 1158.0, height: 756.0)), 32.0)
    }

    /// An unrecognized phone is unchanged: it has no status bar in landscape.
    func test_unrecognizedPhone_isUnchanged() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 400.0, height: 880.0), scale: 3.0, statusBarHeight: 0.0, onScreenNavigationHeight: 34.0, modelIdentifier: "iPhone99,1")
        XCTAssertEqual(metrics.type, .phone)
        XCTAssertNil(metrics.statusBarHeight(for: CGSize(width: 880.0, height: 400.0)))
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 400.0, height: 880.0)), 0.0)
    }
}
