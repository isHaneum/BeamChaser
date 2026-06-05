import SwiftUI

enum ComponentTokens {
    enum RunActive {
        static let topOverlayOuterPadding: CGFloat = 8
        static let topOverlayInnerSpacing: CGFloat = 0
        static let topIndicatorHeight: CGFloat = 28
        static let modeToggleOuterHeight: CGFloat = 0
        static let metricBarOuterHeight: CGFloat = 0
        static let pageChromeGap: CGFloat = 8
        static let pageBottomClearance: CGFloat = 40
        static let runningControlHeight = LayoutTokens.bottomLayerHeight
        static let pausedPanelCompactHeight: CGFloat = 150
        static let pausedPanelRegularHeight: CGFloat = 160
        static let bottomOverlayPadding = LayoutTokens.overlayBottomPadding
        static let pageAnimationDuration: Double = 0.16
        static let swipeMinimumDistance: CGFloat = 34

        static func topOverlayHeight(compact: Bool) -> CGFloat {
            topIndicatorHeight
        }

        static func pausedPanelHeight(compact: Bool) -> CGFloat {
            compact ? pausedPanelCompactHeight : pausedPanelRegularHeight
        }

        static func bottomControlHeight(isPaused: Bool, compact: Bool) -> CGFloat {
            isPaused ? pausedPanelHeight(compact: compact) : runningControlHeight
        }

        static func topOverlayTop(safeTop: CGFloat) -> CGFloat {
            safeTop + topOverlayOuterPadding
        }

        static func bottomOverlayBottom(safeBottom: CGFloat) -> CGFloat {
            safeBottom + bottomOverlayPadding
        }

        static func pageTopPadding(safeTop: CGFloat, compact: Bool) -> CGFloat {
            topOverlayTop(safeTop: safeTop) + topOverlayHeight(compact: compact) + pageChromeGap
        }

        static func pageBottomPadding(safeBottom: CGFloat, isPaused: Bool, compact: Bool) -> CGFloat {
            bottomControlHeight(isPaused: isPaused, compact: compact)
                + safeBottom
                + pageBottomClearance
        }
    }

    enum RunSurface {
        static let verticalSpacingSmall: CGFloat = 8
        static let verticalSpacingMedium: CGFloat = 12
        static let verticalSpacingLarge: CGFloat = 20
        static let pillRadius: CGFloat = 18
        static let controlRadius: CGFloat = 24
        static let headerButtonHeight: CGFloat = 56
        static let exportButtonMinWidth: CGFloat = 96

        static func metricBarHeight(compact: Bool) -> CGFloat {
            ComponentTokens.RunActive.metricBarOuterHeight
        }

        static func mapSummaryHeight(compact: Bool) -> CGFloat {
            ComponentTokens.RunActive.runningControlHeight
        }

        static func audioCardHeight(compact: Bool) -> CGFloat {
            compact ? 128 : 148
        }

        static func pausedPanelHeight(compact: Bool) -> CGFloat {
            ComponentTokens.RunActive.pausedPanelHeight(compact: compact)
        }

        static func sharePanelHeight(compact: Bool) -> CGFloat {
            compact ? 300 : 340
        }
    }

    enum ShareEditor {
        static let exportCanvasSize = CGSize(width: 1080, height: 1350)
        static let routeLineWidth: CGFloat = 3.2
        static let compactHeightThreshold: CGFloat = 760
        static let compactWidthThreshold: CGFloat = 390
        static let compactPanelRatio: CGFloat = 0.40
        static let regularPanelRatio: CGFloat = 0.36
        static let panelMinHeight: CGFloat = 300
        static let panelMaxHeight: CGFloat = 380
        static let headerButtonHeight: CGFloat = 48
        static let headerTopGap: CGFloat = 16
        static let headerBottomPadding: CGFloat = 12
        static let previewPanelGap: CGFloat = 64
        static let previewMinHeight: CGFloat = 180
        static let panelGrabberWidth: CGFloat = 34
        static let panelGrabberHeight: CGFloat = 4
    }
}

enum RunSurfaceToken {
    static let horizontalPadding: CGFloat = LayoutTokens.horizontalPadding
    static let shareHorizontalPadding: CGFloat = LayoutTokens.horizontalPadding
    static let verticalSpacingSmall = ComponentTokens.RunSurface.verticalSpacingSmall
    static let verticalSpacingMedium = ComponentTokens.RunSurface.verticalSpacingMedium
    static let verticalSpacingLarge = ComponentTokens.RunSurface.verticalSpacingLarge
    static let cardRadius: CGFloat = LayoutTokens.cardRadius
    static let pillRadius = ComponentTokens.RunSurface.pillRadius
    static let controlRadius = ComponentTokens.RunSurface.controlRadius

    static let glassBackground = ColorTokens.Run.glass
    static let darkPanelBackground = ColorTokens.Run.panel
    static let lightPanelBackground = Color.white
    static let primaryBlue = RBColor.primary
    static let secondaryText = ColorTokens.Run.secondaryText
    static let dividerColor = ColorTokens.Run.divider

    static let modeToggleHeight: CGFloat = 48
    static let runningControlHeight = ComponentTokens.RunActive.runningControlHeight
    static let headerButtonHeight = ComponentTokens.RunSurface.headerButtonHeight
    static let exportButtonMinWidth = ComponentTokens.RunSurface.exportButtonMinWidth

    static func metricBarHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunSurface.metricBarHeight(compact: compact)
    }

    static func mapSummaryHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunSurface.mapSummaryHeight(compact: compact)
    }

    static func audioCardHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunSurface.audioCardHeight(compact: compact)
    }

    static func pausedPanelHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunSurface.pausedPanelHeight(compact: compact)
    }

    static func sharePanelHeight(compact: Bool) -> CGFloat {
        ComponentTokens.RunSurface.sharePanelHeight(compact: compact)
    }
}
