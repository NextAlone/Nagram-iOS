import Foundation
import UIKit
import Display
import ChatListHeaderComponent

// The header (search field, stories row) collapses as the current list scrolls and stops at the search field's height
// (`ChatListNavigationBar.View.clippedScrollOffset`), whatever `scrollHeightTopInset` lets a list scroll: the root lists'
// 150 (search and stories) is not where the header ends. A list is past the header ("navigation hidden") from that offset
// on, and a list matched to a current one that is past it goes there, not further: further would leave its first chat
// under the collapsed header.
enum ChatListNavigationOffset {
    private static let defaultCollapsedOffset: CGFloat = ChatListNavigationBar.searchScrollHeight

    // MARK: NAGRAM — the header's collapsed height follows Nagram's search bar setting.
    static func isNavigationHidden(_ offset: ListViewVisibleContentOffset, collapsedOffset: CGFloat = defaultCollapsedOffset) -> Bool {
        switch offset {
        case let .known(value):
            // Negative while the stories row is expanded.
            return value >= collapsedOffset - 1.0
        case .none:
            return false
        case .unknown:
            return true
        }
    }

    // The offset from the top a list that is not current moves to so that its navigation state matches the current
    // list's, or nil when it already does or cannot (it has no rows yet).
    static func offsetMatching(isNavigationHidden: Bool, from offset: ListViewVisibleContentOffset, collapsedOffset: CGFloat = defaultCollapsedOffset) -> CGFloat? { // MARK: NAGRAM
        if self.isNavigationHidden(offset, collapsedOffset: collapsedOffset) == isNavigationHidden {
            return nil
        }
        if case .known = offset, !self.isNavigationHidden(offset, collapsedOffset: collapsedOffset) {
            return isNavigationHidden ? collapsedOffset : nil
        } else {
            return isNavigationHidden ? nil : 0.0
        }
    }
}
