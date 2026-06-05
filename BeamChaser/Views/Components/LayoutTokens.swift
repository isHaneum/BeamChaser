import SwiftUI

enum LayoutTokens {
    static let horizontalPadding: CGFloat = 24
    static let compactHorizontalPadding: CGFloat = 20
    static let expandedHorizontalPadding: CGFloat = 28
    static let overlayEdgePadding: CGFloat = 8
    static let overlayBottomPadding: CGFloat = 16
    static let cardRadius: CGFloat = 28
    static let smallCardRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 20
    static let componentSpacing: CGFloat = 12
    static let topLayerHeight: CGFloat = 158
    static let bottomLayerHeight: CGFloat = 76
    static let compactViewportHeight: CGFloat = 700
    static let compactViewportWidth: CGFloat = 390

    static func contentWidth(for screenWidth: CGFloat, horizontalPadding: CGFloat = horizontalPadding) -> CGFloat {
        max(0, screenWidth - horizontalPadding * 2)
    }

    static func runHorizontalPadding(compact: Bool) -> CGFloat {
        compact ? compactHorizontalPadding : expandedHorizontalPadding
    }

    static func runContentWidth(for screenWidth: CGFloat, compact: Bool) -> CGFloat {
        contentWidth(for: screenWidth, horizontalPadding: runHorizontalPadding(compact: compact))
    }

    static func viewportHeight(size: CGSize, safeAreaInsets: EdgeInsets) -> CGFloat {
        max(0, size.height - safeAreaInsets.top - safeAreaInsets.bottom)
    }

    static func isCompactRunLayout(size: CGSize, safeAreaInsets: EdgeInsets) -> Bool {
        viewportHeight(size: size, safeAreaInsets: safeAreaInsets) < compactViewportHeight
            || size.width < compactViewportWidth
    }
}
