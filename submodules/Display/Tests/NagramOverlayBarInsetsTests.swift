import XCTest
import UIKit
@testable import Display

// MARK: NAGRAM
/// The in-app picture-in-picture keeps clear of the bars a screen reports, and keeps the upstream insets otherwise.
final class NagramOverlayBarInsetsTests: XCTestCase {
    /// The layout `OverlayMediaControllerImpl` passes on: the top inset is the status bar plus a 44pt navigation bar.
    private func layout(inputHeight: CGFloat? = nil) -> ContainerViewLayout {
        return ContainerViewLayout(size: CGSize(width: 402.0, height: 874.0), metrics: LayoutMetrics(widthClass: .compact, heightClass: .regular, orientation: nil), deviceMetrics: .iPhone16Pro, intrinsicInsets: UIEdgeInsets(top: 62.0 + 44.0, left: 0.0, bottom: 34.0, right: 0.0), safeInsets: UIEdgeInsets(top: 62.0, left: 0.0, bottom: 34.0, right: 0.0), reservedCorners: .none, division: nil, additionalInsets: UIEdgeInsets(), statusBarHeight: 62.0, inputHeight: inputHeight, inputHeightIsInteractivellyChanging: false, inVoiceOver: false, presentedInFormSheet: false)
    }

    func test_unreported_keepsUpstreamInsets() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(), bars: nil, tempExtendedTopInset: false)
        XCTAssertEqual(insets.top, 106.0)
        XCTAssertEqual(insets.bottom, 34.0 + 48.0)

        let extended = nagramOverlayVerticalInsets(layout: self.layout(), bars: NagramOverlayBarInsets(top: nil, bottom: nil), tempExtendedTopInset: true)
        XCTAssertEqual(extended.top, 106.0 + 38.0)
    }

    func test_unreported_bottom_followsTheKeyboard() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(inputHeight: 336.0), bars: nil, tempExtendedTopInset: false)
        XCTAssertEqual(insets.bottom, 336.0 + 48.0)
    }

    func test_reportedBars_replaceTheGuesses() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(), bars: NagramOverlayBarInsets(top: 122.0, bottom: 96.0), tempExtendedTopInset: false)
        XCTAssertEqual(insets.top, 122.0)
        XCTAssertEqual(insets.bottom, 96.0)
    }

    /// A screen drawing its header below a short bar (the chat list's folder tabs) never moves the item up.
    func test_reportedTop_neverAboveTheUpstreamGuess() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(), bars: NagramOverlayBarInsets(top: 98.0, bottom: nil), tempExtendedTopInset: false)
        XCTAssertEqual(insets.top, 106.0)
    }

    /// A screen without a top bar (a full-screen gallery) leaves only the status bar; no bottom bar leaves the home
    /// indicator.
    func test_noBars_keepClearOfTheSafeArea() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(), bars: NagramOverlayBarInsets(top: 0.0, bottom: 0.0), tempExtendedTopInset: false)
        XCTAssertEqual(insets.top, 62.0)
        XCTAssertEqual(insets.bottom, 34.0)
    }

    /// The keyboard wins over a bottom bar it covers (a tab with a search field focused).
    func test_reportedBottom_neverBelowTheKeyboard() {
        let insets = nagramOverlayVerticalInsets(layout: self.layout(inputHeight: 336.0), bars: NagramOverlayBarInsets(top: 122.0, bottom: 96.0), tempExtendedTopInset: false)
        XCTAssertEqual(insets.bottom, 336.0)
    }
}
