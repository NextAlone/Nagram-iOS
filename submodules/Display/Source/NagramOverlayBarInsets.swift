import Foundation
import UIKit

// MARK: NAGRAM
/// The bars a screen draws at its top and bottom edges, which the in-app picture-in-picture keeps clear of.
///
/// `top` is the distance from the screen's top edge to the bottom of its top bar, `bottom` the distance from the
/// screen's bottom edge to the top of its bottom bar (tab bar, chat input panel, edit toolbar). `nil` means the screen
/// does not report that edge, and the overlay keeps its own fixed insets for it. `0` means the screen has no bar
/// there.
public struct NagramOverlayBarInsets: Equatable {
    public var top: CGFloat?
    public var bottom: CGFloat?

    public init(top: CGFloat?, bottom: CGFloat?) {
        self.top = top
        self.bottom = bottom
    }
}

// MARK: NAGRAM
/// The bars of the screens under each half of the window, in window coordinates. The halves differ only beside an iPad
/// split view, where the left corners lie over the master column and the right corners over the detail column.
public struct NagramOverlayObstruction: Equatable {
    public var left: NagramOverlayBarInsets
    public var right: NagramOverlayBarInsets

    public init(left: NagramOverlayBarInsets, right: NagramOverlayBarInsets) {
        self.left = left
        self.right = right
    }

    public init(both: NagramOverlayBarInsets) {
        self.left = both
        self.right = both
    }
}

// MARK: NAGRAM
/// The vertical insets an overlay item keeps on one side of the window.
///
/// Without a report it keeps the upstream insets: the top inset `layout` carries (the status bar and a 44pt
/// navigation bar), and the bottom inset or keyboard plus 48pt. A reported top bar replaces the 44pt guess but never
/// goes above it, since a screen may draw more of its header below a short bar; a screen reporting no top bar keeps
/// clear of the status bar only. A reported bottom bar replaces the 48pt guess and never goes below the keyboard or
/// the bottom safe area.
public func nagramOverlayVerticalInsets(layout: ContainerViewLayout, bars: NagramOverlayBarInsets?, tempExtendedTopInset: Bool) -> (top: CGFloat, bottom: CGFloat) {
    let layoutInsets = layout.insets(options: [.input])
    let statusBarInset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
    var top: CGFloat
    if let reportedTop = bars?.top {
        if reportedTop <= statusBarInset {
            top = statusBarInset
        } else {
            top = max(reportedTop, layoutInsets.top)
        }
    } else {
        top = layoutInsets.top
    }
    if tempExtendedTopInset {
        top += 38.0
    }
    let bottom: CGFloat
    if let reportedBottom = bars?.bottom {
        bottom = max(reportedBottom, layoutInsets.bottom, layout.safeInsets.bottom)
    } else {
        bottom = layoutInsets.bottom + 48.0
    }
    return (top, bottom)
}

// MARK: NAGRAM
/// Tells the in-app picture-in-picture that a screen's bars may have moved.
///
/// Every controller layout pass invalidates it while the overlay shows something; the passes of one run loop turn are
/// coalesced into one notification after them, when the bars are in their final frames.
public final class NagramOverlayBarTracker {
    public static let shared = NagramOverlayBarTracker()

    /// Set by the overlay while it shows an item; nothing is scheduled while it is false.
    public var isActive: Bool = false
    public var invalidated: ((ContainedViewLayoutTransition) -> Void)?

    private var pendingTransition: ContainedViewLayoutTransition?

    private init() {
    }

    public func invalidate(transition: ContainedViewLayoutTransition) {
        guard self.isActive, Thread.isMainThread else {
            return
        }
        if let pendingTransition = self.pendingTransition {
            if !pendingTransition.isAnimated && transition.isAnimated {
                self.pendingTransition = transition
            }
            return
        }
        self.pendingTransition = transition
        DispatchQueue.main.async { [weak self] in
            guard let self, let transition = self.pendingTransition else {
                return
            }
            self.pendingTransition = nil
            self.invalidated?(transition)
        }
    }
}
