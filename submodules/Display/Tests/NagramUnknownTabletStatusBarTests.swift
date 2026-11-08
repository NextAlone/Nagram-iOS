import XCTest
import UIKit
@testable import Display

// MARK: NAGRAM
/// An iPad newer than the device table is recognized before its scene reports a status bar.
final class NagramUnknownTabletStatusBarTests: XCTestCase {
    /// An iPad with no profile, captured with no status bar frame: the first layout drew the navigation bar under the
    /// status bar until a rotation re-read the frame (the iPad mini (A20 Pro) did this before it had a profile).
    func test_unrecognizedTablet_withoutCapturedHeight_usesTheTabletStatusBar() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 1200.0, height: 780.0), scale: 2.0, statusBarHeight: 0.0, onScreenNavigationHeight: nil, modelIdentifier: "iPad99,1")
        guard case .unknown = metrics else {
            return XCTFail("expected an unrecognized device, got \(metrics)")
        }
        XCTAssertEqual(metrics.type, .tablet)
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 1200.0, height: 780.0)), 24.0)
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 780.0, height: 1200.0)), 24.0)
    }

    /// A height the system did report is kept.
    func test_unrecognizedTablet_keepsACapturedHeight() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 1200.0, height: 780.0), scale: 2.0, statusBarHeight: 32.0, onScreenNavigationHeight: nil, modelIdentifier: "iPad99,1")
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 1200.0, height: 780.0)), 32.0)
    }

    /// The iPad mini (A20 Pro) has its own profile, with or without a reported home indicator, in either orientation.
    func test_iPadMini8thGen_isRecognized() {
        for screenSize in [CGSize(width: 756.0, height: 1158.0), CGSize(width: 1158.0, height: 756.0)] {
            for onScreenNavigationHeight: CGFloat? in [nil, 20.0] {
                let metrics = DeviceMetrics(screenSize: screenSize, scale: 2.0, statusBarHeight: 0.0, onScreenNavigationHeight: onScreenNavigationHeight, modelIdentifier: "iPad19,1")
                XCTAssertEqual(metrics, .iPadMini8thGen)
                XCTAssertEqual(metrics.type, .tablet)
                XCTAssertEqual(metrics.statusBarHeight(for: screenSize), 24.0)
                XCTAssertEqual(metrics.standardInputHeight(inLandscape: false), metrics.keyboardHeight(inLandscape: false) + 50.0)
            }
        }
    }

    /// An unrecognized phone is unchanged: it has no status bar in landscape.
    func test_unrecognizedPhone_isUnchanged() {
        let metrics = DeviceMetrics(screenSize: CGSize(width: 400.0, height: 880.0), scale: 3.0, statusBarHeight: 0.0, onScreenNavigationHeight: 34.0, modelIdentifier: "iPhone99,1")
        XCTAssertEqual(metrics.type, .phone)
        XCTAssertNil(metrics.statusBarHeight(for: CGSize(width: 880.0, height: 400.0)))
        XCTAssertEqual(metrics.statusBarHeight(for: CGSize(width: 400.0, height: 880.0)), 0.0)
    }
}
