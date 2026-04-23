import SwiftUI
import UIKit
import PhotosUI
import CoreLocation
import UniformTypeIdentifiers

private enum ShareEditorScreen {
    case share
    case background
}

private struct ShareMetricValueDisplay {
    let main: String
    let unit: String?
    let footerText: String
}

private enum ShareMetricToggle: String, CaseIterable, Identifiable {
    case distance
    case time
    case pace
    case calories

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .distance:
            return appLanguage.text("거리", "Distance")
        case .time:
            return appLanguage.text("시간", "Time")
        case .pace:
            return appLanguage.text("페이스", "Pace")
        case .calories:
            return appLanguage.text("칼로리", "Calories")
        }
    }

    var symbolName: String {
        switch self {
        case .distance:
            return "location.north.line"
        case .time:
            return "timer"
        case .pace:
            return "speedometer"
        case .calories:
            return "flame.fill"
        }
    }

    func valueDisplay(from record: RunRecord) -> ShareMetricValueDisplay? {
        switch self {
        case .distance:
            guard record.distanceKm > 0 else { return nil }
            let value = String(format: "%.2f", record.distanceKm)
            return ShareMetricValueDisplay(main: value, unit: "km", footerText: "\(value) km")
        case .time:
            guard record.elapsedSeconds > 0 else { return nil }
            return ShareMetricValueDisplay(main: record.formattedDuration, unit: nil, footerText: record.formattedDuration)
        case .pace:
            guard record.averagePaceSecondsPerKm > 0 else { return nil }
            return ShareMetricValueDisplay(main: record.formattedPace, unit: "/km", footerText: "\(record.formattedPace)/km")
        case .calories:
            guard record.estimatedCaloriesKcal > 0 else { return nil }
            let value = String(format: "%.0f", record.estimatedCaloriesKcal)
            return ShareMetricValueDisplay(main: value, unit: "kcal", footerText: "\(value) kcal")
        }
    }

    var feedMetricKey: RunShareMetricKey? {
        switch self {
        case .distance:
            return nil
        case .time:
            return .duration
        case .pace:
            return .pace
        case .calories:
            return .calories
        }
    }
}

private enum ShareTemplate: String, CaseIterable, Identifiable {
    case routeOnly
    case routeDistance
    case routeTime
    case fullStats

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .routeOnly:
            return appLanguage.text("경로만", "Route Only")
        case .routeDistance:
            return appLanguage.text("경로+거리", "Route+Distance")
        case .routeTime:
            return appLanguage.text("경로+시간", "Route+Time")
        case .fullStats:
            return appLanguage.text("전체 수치", "Full Stats")
        }
    }

    var defaultMetrics: Set<ShareMetricToggle> {
        switch self {
        case .routeOnly:
            return []
        case .routeDistance:
            return [.distance, .time, .pace, .calories]
        case .routeTime:
            return [.time, .distance, .pace, .calories]
        case .fullStats:
            return [.distance, .time, .pace, .calories]
        }
    }

    var defaultOrder: [ShareMetricToggle] {
        switch self {
        case .routeOnly:
            return ShareMetricToggle.allCases
        case .routeDistance:
            return [.distance, .time, .pace, .calories]
        case .routeTime:
            return [.time, .distance, .pace, .calories]
        case .fullStats:
            return [.distance, .time, .pace, .calories]
        }
    }
}

private enum BackgroundMode: String, CaseIterable, Identifiable {
    case white
    case fullPhoto
    case overlayPhoto
    case transparent

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .white:
            return appLanguage.text("화이트", "White")
        case .fullPhoto:
            return appLanguage.text("사진 배경", "Photo")
        case .overlayPhoto:
            return appLanguage.text("오버레이", "Overlay")
        case .transparent:
            return appLanguage.text("투명 배경", "Transparent")
        }
    }

    var usesPhoto: Bool {
        switch self {
        case .fullPhoto, .overlayPhoto:
            return true
        case .white, .transparent:
            return false
        }
    }
}

private enum RouteColorPreset: String, CaseIterable, Identifiable {
    case black
    case laserOrange
    case laserRed
    case electricBlue
    case violet
    case lime
    case spectrum

    var id: String { rawValue }

    var gradientColors: [Color] {
        switch self {
        case .black:
            return [.black, .black]
        case .laserOrange:
            return [Color(red: 0.99, green: 0.78, blue: 0.18), Color(red: 0.97, green: 0.36, blue: 0.09)]
        case .laserRed:
            return [Color(red: 0.99, green: 0.42, blue: 0.20), Color(red: 0.97, green: 0.12, blue: 0.21)]
        case .electricBlue:
            return [Color(red: 0.30, green: 0.62, blue: 0.98), Color(red: 0.13, green: 0.30, blue: 0.96)]
        case .violet:
            return [Color(red: 0.55, green: 0.44, blue: 0.88), Color(red: 0.44, green: 0.28, blue: 0.76)]
        case .lime:
            return [Color(red: 0.72, green: 0.86, blue: 0.25), Color(red: 0.45, green: 0.68, blue: 0.10)]
        case .spectrum:
            return [
                Color(red: 0.98, green: 0.58, blue: 0.12),
                Color(red: 0.98, green: 0.17, blue: 0.22),
                Color(red: 0.34, green: 0.42, blue: 0.95),
                Color(red: 0.46, green: 0.79, blue: 0.30)
            ]
        }
    }

    var primaryColor: Color {
        switch self {
        case .black:
            return .black
        case .laserOrange:
            return Color(red: 0.98, green: 0.51, blue: 0.10)
        case .laserRed:
            return Color(red: 0.97, green: 0.18, blue: 0.22)
        case .electricBlue:
            return Color(red: 0.21, green: 0.43, blue: 0.96)
        case .violet:
            return Color(red: 0.47, green: 0.34, blue: 0.81)
        case .lime:
            return Color(red: 0.54, green: 0.74, blue: 0.12)
        case .spectrum:
            return Color(red: 0.98, green: 0.51, blue: 0.10)
        }
    }
}

private enum RouteStrokeStyle: String, CaseIterable, Identifiable {
    case laser
    case soft
    case dashed
    case mono
    case muted

    var id: String { rawValue }

    var dashPattern: [CGFloat] {
        switch self {
        case .dashed:
            return [10, 9]
        default:
            return []
        }
    }

    var glowMultiplier: Double {
        switch self {
        case .laser:
            return 1.0
        case .soft:
            return 0.55
        case .dashed:
            return 0.28
        case .mono:
            return 0.05
        case .muted:
            return 0.12
        }
    }

    var opacityMultiplier: Double {
        switch self {
        case .muted:
            return 0.52
        default:
            return 1.0
        }
    }

    var usesMonochrome: Bool {
        self == .mono
    }
}

private enum PhotoAdjustment: String, CaseIterable, Identifiable {
    case scale
    case positionX
    case positionY
    case opacity
    case blur
    case brightness
    case contrast

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .scale:
            return appLanguage.text("크기", "Scale")
        case .positionX:
            return appLanguage.text("가로", "X")
        case .positionY:
            return appLanguage.text("세로", "Y")
        case .opacity:
            return appLanguage.text("투명도", "Opacity")
        case .blur:
            return appLanguage.text("블러", "Blur")
        case .brightness:
            return appLanguage.text("밝기", "Brightness")
        case .contrast:
            return appLanguage.text("대비", "Contrast")
        }
    }
}

private enum EditorControlPanel: String, CaseIterable, Identifiable {
    case metrics
    case style
    case photo

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .metrics:
            return appLanguage.text("수치", "Metrics")
        case .style:
            return appLanguage.text("스타일", "Style")
        case .photo:
            return appLanguage.text("사진", "Photo")
        }
    }
}

private enum PreviewBackgroundKind {
    case light
    case dark
    case photo
}

private enum WidePreviewLayout {
    case heroOnly
    case statsRow
}

private enum WidePreviewStyle: String, CaseIterable, Identifiable {
    case distanceLight
    case timeDark
    case photoStats
    case cleanStats

    var id: String { rawValue }

    var template: ShareTemplate {
        switch self {
        case .distanceLight:
            return .routeDistance
        case .timeDark:
            return .routeTime
        case .photoStats, .cleanStats:
            return .fullStats
        }
    }

    var backgroundKind: PreviewBackgroundKind {
        switch self {
        case .distanceLight, .cleanStats:
            return .light
        case .timeDark:
            return .dark
        case .photoStats:
            return .photo
        }
    }

    var layout: WidePreviewLayout {
        switch self {
        case .distanceLight, .timeDark:
            return .heroOnly
        case .photoStats, .cleanStats:
            return .statsRow
        }
    }
}

private struct MetricReorderDropDelegate: DropDelegate {
    let target: ShareMetricToggle
    @Binding var metricOrder: [ShareMetricToggle]
    @Binding var draggedMetric: ShareMetricToggle?

    func dropEntered(info: DropInfo) {
        guard let draggedMetric,
              draggedMetric != target,
              let fromIndex = metricOrder.firstIndex(of: draggedMetric),
              let toIndex = metricOrder.firstIndex(of: target) else {
            return
        }

        if metricOrder[toIndex] != draggedMetric {
            withAnimation(.easeInOut(duration: 0.16)) {
                metricOrder.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedMetric = nil
        return true
    }
}

private struct EditorSegmentButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.black.opacity(0.66))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(selected ? Color.black : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ToggleChipButton: View {
    let title: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(active ? Color(red: 0.99, green: 0.43, blue: 0.05) : Color.black.opacity(0.08))
                    .frame(width: 24, height: 14)
                    .overlay(alignment: active ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .padding(2)
                    }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? Color.black.opacity(active ? 0.92 : 0.68) : Color.black.opacity(0.22))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(active ? Color(red: 0.99, green: 0.43, blue: 0.05).opacity(0.28) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct ColorSwatchButton: View {
    let colors: [Color]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                if selected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 36, height: 36)
            .background(selected ? Color.black : Color.clear)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct RouteStylePreviewButton: View {
    let selected: Bool
    let action: () -> Void
    let previewTint: Color
    let usesDash: Bool
    let usesMonochrome: Bool

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.black : Color.black.opacity(0.04))
                    .frame(width: 44, height: 32)

                Path { path in
                    path.move(to: CGPoint(x: 10, y: 22))
                    path.addCurve(
                        to: CGPoint(x: 34, y: 10),
                        control1: CGPoint(x: 16, y: 8),
                        control2: CGPoint(x: 24, y: 28)
                    )
                }
                .stroke(
                    usesMonochrome ? (selected ? Color.white : Color.black.opacity(0.45)) : (selected ? Color.white : previewTint),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: usesDash ? [4, 3] : [])
                )
                .frame(width: 44, height: 32)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BackgroundOptionTile: View {
    let title: String
    let selected: Bool
    let enabled: Bool
    let preview: AnyView
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 74, height: 58)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Color(red: 0.99, green: 0.43, blue: 0.05) : Color.black.opacity(0.08), lineWidth: selected ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(enabled ? 1 : 0.35)

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? Color.black.opacity(0.72) : Color.black.opacity(0.28))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct LayoutMetricBox: View {
    let title: String?
    let isLarge: Bool
    let active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.black.opacity(active ? 0.18 : 0.08), style: StrokeStyle(lineWidth: 1, dash: active ? [] : [4, 4]))
            .frame(height: isLarge ? 72 : 62)
            .overlay {
                if let title {
                    Text(title)
                        .font(.system(size: isLarge ? 16 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(active ? 0.78 : 0.28))
                        .padding(.horizontal, 12)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
    }
}

private struct WorkflowIndicator: View {
    let selectedStep: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...3, id: \.self) { step in
                ZStack {
                    Circle()
                        .fill(step == selectedStep ? Color.black : Color.black.opacity(0.08))
                        .frame(width: 24, height: 24)
                    Text("\(step)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(step == selectedStep ? Color.white : Color.black.opacity(0.52))
                }
            }
        }
    }
}

struct RunShareComposerScene: View {
    let record: RunRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backendService: BackendService
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var editorScreen: ShareEditorScreen = .share
    @State private var selectedTemplate: ShareTemplate = .routeDistance
    @State private var visibleMetrics: Set<ShareMetricToggle> = ShareTemplate.routeDistance.defaultMetrics
    @State private var metricOrder: [ShareMetricToggle] = ShareTemplate.routeDistance.defaultOrder
    @State private var selectedControlPanel: EditorControlPanel = .metrics

    @State private var routeColorPreset: RouteColorPreset = .laserOrange
    @State private var routeStrokeStyle: RouteStrokeStyle = .laser
    @State private var routeLineWidth: Double = 6

    @State private var backgroundMode: BackgroundMode = .white
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var photoScale: Double = 1.0
    @State private var photoOffset: CGSize = .zero
    @State private var photoOpacity: Double = 0.94
    @State private var photoBlur: Double = 0
    @State private var photoBrightness: Double = 0
    @State private var photoContrast: Double = 1.0
    @State private var selectedPhotoAdjustment: PhotoAdjustment = .scale

    @State private var draggedMetric: ShareMetricToggle?
    @State private var isPosting = false
    @State private var statusText: String?
    @State private var statusTint: Color = RBColor.textSecondary

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var previewCanvasSize: CGSize {
        let width = min(UIScreen.main.bounds.width - 40, 332)
        return CGSize(width: width, height: width * 1.36)
    }

    private var hasRenderableRoute: Bool {
        record.routePoints.count >= 2 && record.totalDistanceMeters > 5
    }

    private var orderedMetricDisplays: [(ShareMetricToggle, ShareMetricValueDisplay)] {
        metricOrder.compactMap { metric in
            guard visibleMetrics.contains(metric), let display = metric.valueDisplay(from: record) else { return nil }
            return (metric, display)
        }
    }

    private var heroMetric: (ShareMetricToggle, ShareMetricValueDisplay)? {
        orderedMetricDisplays.first
    }

    private var secondaryMetrics: [(ShareMetricToggle, ShareMetricValueDisplay)] {
        Array(orderedMetricDisplays.dropFirst())
    }

    private var selectedMetricKeysForPost: [RunShareMetricKey] {
        orderedMetricDisplays.compactMap { $0.0.feedMetricKey }
    }

    private var resolvedHeadline: String {
        let weekday = RunPresentationFormatter.shortWeekdayString(from: record.startDate, appLanguage: appLanguage)
        if let heroMetric {
            return "\(weekday) \(heroMetric.1.footerText)"
        }
        return "\(weekday) \(String(format: "%.2f km", record.distanceKm))"
    }

    private var resolvedFeedBody: String {
        orderedMetricDisplays.map { $0.1.footerText }.joined(separator: " · ")
    }

    private var cardTextColor: Color {
        switch backgroundMode {
        case .fullPhoto:
            return .white
        case .white, .overlayPhoto, .transparent:
            return .black
        }
    }

    private var cardSecondaryTextColor: Color {
        switch backgroundMode {
        case .fullPhoto:
            return Color.white.opacity(0.84)
        case .white, .overlayPhoto, .transparent:
            return Color.black.opacity(0.72)
        }
    }

    private var headerAccentColor: Color {
        Color(red: 0.99, green: 0.43, blue: 0.05)
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.96)
                .ignoresSafeArea()

            if editorScreen == .share {
                shareScreen
            } else {
                backgroundEditorScreen
            }
        }
        .onAppear {
            applyTemplate(.routeDistance)
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await loadPhoto(from: newValue)
            }
        }
    }

    private var shareScreen: some View {
        VStack(spacing: 0) {
            screenHeader(title: appLanguage.text("공유하기", "Share"), selectedStep: 2, trailingTitle: isPosting ? appLanguage.text("업로드 중", "Posting") : appLanguage.text("완료", "Done")) {
                Task {
                    await postToCommunity()
                }
            }

            VStack(spacing: 14) {
                portraitShareCard(size: previewCanvasSize)
                    .frame(width: previewCanvasSize.width, height: previewCanvasSize.height)
                    .shadow(color: Color.black.opacity(0.10), radius: 24, y: 14)
                    .frame(maxWidth: .infinity)

                if let statusText {
                    Text(statusText)
                        .font(RBFont.caption(11))
                        .foregroundStyle(statusTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        editorScreen = .background
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 13, weight: .semibold))
                        Text(appLanguage.text("배경 편집", "Edit Background"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.black.opacity(0.72))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.white)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    panelPicker
                    currentPanelContent
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 22)
            }
        }
    }

    private var backgroundEditorScreen: some View {
        VStack(spacing: 0) {
            backgroundScreenHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle(appLanguage.text("템플릿 선택", "Template"))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ShareTemplate.allCases) { template in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            applyTemplate(template)
                                        }
                                    } label: {
                                        templateCard(template)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle(appLanguage.text("공유 미리보기", "Share Preview"))

                        VStack(spacing: 14) {
                            ForEach(WidePreviewStyle.allCases) { style in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        applyTemplate(style.template)
                                    }
                                } label: {
                                    widePreviewCard(style: style)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle(appLanguage.text("배경 옵션", "Background"))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                BackgroundOptionTile(
                                    title: appLanguage.text("화이트", "White"),
                                    selected: backgroundMode == .white,
                                    enabled: true,
                                    preview: AnyView(Color.white)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        backgroundMode = .white
                                    }
                                }

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    BackgroundOptionTile(
                                        title: appLanguage.text("사진 배경", "Photo"),
                                        selected: backgroundMode == .fullPhoto,
                                        enabled: true,
                                        preview: AnyView(photoOptionPreview(mode: .fullPhoto))
                                    ) {
                                        if selectedPhotoImage != nil {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                backgroundMode = .fullPhoto
                                            }
                                        }
                                    }
                                }

                                BackgroundOptionTile(
                                    title: appLanguage.text("오버레이", "Overlay"),
                                    selected: backgroundMode == .overlayPhoto,
                                    enabled: selectedPhotoImage != nil,
                                    preview: AnyView(photoOptionPreview(mode: .overlayPhoto))
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        backgroundMode = .overlayPhoto
                                    }
                                }

                                BackgroundOptionTile(
                                    title: appLanguage.text("투명 배경", "Transparent"),
                                    selected: backgroundMode == .transparent,
                                    enabled: true,
                                    preview: AnyView(checkerPreview)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        backgroundMode = .transparent
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        if selectedPhotoImage != nil {
                            HStack(spacing: 10) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Text(appLanguage.text("사진 변경", "Change Photo"))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.72))
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(Color.white)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                }

                                Button {
                                    removePhoto()
                                } label: {
                                    Text(appLanguage.text("삭제", "Remove"))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.72))
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(Color.white)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 110)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                shareCard()
            } label: {
                Text(appLanguage.text("공유하기", "Share"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.99, green: 0.56, blue: 0.08), Color(red: 0.98, green: 0.32, blue: 0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color.white)
        }
    }

    private func screenHeader(title: String, selectedStep: Int, trailingTitle: String, trailingAction: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.black.opacity(0.92))

                Spacer()

                Button(action: trailingAction) {
                    Text(trailingTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(headerAccentColor)
                        .frame(minWidth: 32)
                }
                .buttonStyle(.plain)
                .disabled(isPosting)
                .opacity(isPosting ? 0.55 : 1)
            }

            WorkflowIndicator(selectedStep: selectedStep)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var backgroundScreenHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        editorScreen = .share
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(appLanguage.text("템플릿 선택", "Template"))
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(Color.black.opacity(0.92))

                Spacer()

                Color.clear
                    .frame(width: 32, height: 32)
            }

            WorkflowIndicator(selectedStep: 3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var panelPicker: some View {
        HStack(spacing: 6) {
            ForEach(EditorControlPanel.allCases) { panel in
                EditorSegmentButton(
                    title: panel.title(appLanguage),
                    selected: selectedControlPanel == panel
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedControlPanel = panel
                    }
                }
            }
        }
        .padding(4)
        .background(Color.white)
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var currentPanelContent: some View {
        switch selectedControlPanel {
        case .metrics:
            metricsPanel
        case .style:
            stylePanel
        case .photo:
            photoPanel
        }
    }

    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(ShareMetricToggle.allCases) { metric in
                        ToggleChipButton(
                            title: metric.title(appLanguage),
                            active: visibleMetrics.contains(metric),
                            enabled: metric.valueDisplay(from: record) != nil
                        ) {
                            toggleMetric(metric)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle(appLanguage.text("레이아웃 편집", "Layout"))
                    Spacer()
                    Button(appLanguage.text("초기화", "Reset")) {
                        resetMetricLayout()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
                }

                VStack(spacing: 12) {
                    metricLayoutBox(metricAtIndex(0), isLarge: true)

                    HStack(spacing: 12) {
                        metricLayoutBox(metricAtIndex(1), isLarge: false)
                        metricLayoutBox(metricAtIndex(2), isLarge: false)
                        metricLayoutBox(metricAtIndex(3), isLarge: false)
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(appLanguage.text("색상", "Color"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RouteColorPreset.allCases) { preset in
                            ColorSwatchButton(
                                colors: preset.gradientColors,
                                selected: routeColorPreset == preset
                            ) {
                                routeColorPreset = preset
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(appLanguage.text("경로 스타일", "Route Style"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RouteStrokeStyle.allCases) { style in
                            RouteStylePreviewButton(
                                selected: routeStrokeStyle == style,
                                action: { routeStrokeStyle = style },
                                previewTint: routeColorPreset.primaryColor,
                                usesDash: !style.dashPattern.isEmpty,
                                usesMonochrome: style.usesMonochrome
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            sliderCard(
                title: appLanguage.text("두께", "Thickness"),
                valueText: "\(Int(routeLineWidth.rounded()))pt"
            ) {
                Slider(value: $routeLineWidth, in: 3...12, step: 1)
                    .tint(routeColorPreset.primaryColor)
            }
        }
    }

    private var photoPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(appLanguage.text(selectedPhotoImage == nil ? "사진 선택" : "사진 변경", selectedPhotoImage == nil ? "Choose Photo" : "Change Photo"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Color.white)
                            .overlay(
                                Capsule()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }

                    if selectedPhotoImage != nil {
                        Button {
                            removePhoto()
                        } label: {
                            Text(appLanguage.text("삭제", "Remove"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Color.white)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedPhotoImage {
                    Image(uiImage: selectedPhotoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if selectedPhotoImage != nil {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PhotoAdjustment.allCases) { adjustment in
                                Button {
                                    selectedPhotoAdjustment = adjustment
                                } label: {
                                    Text(adjustment.title(appLanguage))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(selectedPhotoAdjustment == adjustment ? Color.white : Color.black.opacity(0.66))
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(selectedPhotoAdjustment == adjustment ? Color.black : Color.white)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(selectedPhotoAdjustment == adjustment ? 0 : 0.08), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sliderCard(
                        title: selectedPhotoAdjustment.title(appLanguage),
                        valueText: photoAdjustmentValueText(photoAdjustmentBinding.wrappedValue)
                    ) {
                        Slider(value: photoAdjustmentBinding, in: photoAdjustmentRange)
                            .tint(routeColorPreset.primaryColor)
                    }
                }
                .padding(16)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func sliderCard<Content: View>(title: String, valueText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(title)
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
            }

            content()
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricLayoutBox(_ metric: ShareMetricToggle?, isLarge: Bool) -> some View {
        Group {
            if let metric {
                LayoutMetricBox(title: metric.title(appLanguage), isLarge: isLarge, active: true)
                    .onDrag {
                        draggedMetric = metric
                        return NSItemProvider(object: metric.rawValue as NSString)
                    }
                    .onDrop(of: [UTType.plainText], delegate: MetricReorderDropDelegate(target: metric, metricOrder: $metricOrder, draggedMetric: $draggedMetric))
            } else {
                LayoutMetricBox(title: nil, isLarge: isLarge, active: false)
            }
        }
    }

    private func metricAtIndex(_ index: Int) -> ShareMetricToggle? {
        let visibleOrder = metricOrder.filter { visibleMetrics.contains($0) }
        guard visibleOrder.indices.contains(index) else { return nil }
        return visibleOrder[index]
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.84))
    }

    private func templateCard(_ template: ShareTemplate) -> some View {
        let isSelected = selectedTemplate == template
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(headerAccentColor)
                    .frame(width: 6, height: 6)
                Text("BEAMCHASER")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.72))
                    .tracking(0.8)
            }

            GeometryReader { geometry in
                let rect = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 8, dy: 10)
                let points = routePreviewPoints(in: rect)
                let path = smoothedRoutePath(points)

                ZStack {
                    path
                        .stroke(
                            LinearGradient(
                                colors: routeColorPreset.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                        )

                    if let end = points.last {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.red.opacity(0.85), lineWidth: 2))
                            .position(end)
                    }
                }
            }
            .frame(height: 44)

            Text(template.title(appLanguage))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.72))
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 118, height: 116, alignment: .topLeading)
        .background(isSelected ? Color.black : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? headerAccentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func portraitShareCard(size: CGSize) -> some View {
        let routeFrame = CGRect(x: size.width * 0.06, y: size.height * 0.10, width: size.width * 0.88, height: size.height * 0.50)

        return ZStack(alignment: .topLeading) {
            portraitCardBackground(size: size)

            routeGraphic(frame: routeFrame, backgroundMode: backgroundMode)

            VStack(alignment: .leading, spacing: 0) {
                brandMark(foreground: cardTextColor)

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    if selectedTemplate != .routeOnly, let heroMetric {
                        metricHeroBlock(metric: heroMetric.0, display: heroMetric.1)
                    }

                    if !secondaryMetrics.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(Array(secondaryMetrics.prefix(3)), id: \.0.id) { item in
                                smallMetricCell(metric: item.0, value: item.1.footerText)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(backgroundMode == .fullPhoto ? 0.02 : 0.06), lineWidth: 1)
        )
    }

    private func widePreviewCard(style: WidePreviewStyle) -> some View {
        let size = CGSize(width: UIScreen.main.bounds.width - 36, height: 132)
        let metricDisplays = metricDisplays(for: style.template)
        let hero = metricDisplays.first
        let footerMetrics = Array(metricDisplays.prefix(4))
        let foreground = widePreviewForegroundColor(for: style.backgroundKind)
        let secondary = widePreviewSecondaryColor(for: style.backgroundKind)
        let routeFrame = CGRect(x: size.width * 0.34, y: size.height * 0.10, width: size.width * 0.60, height: size.height * 0.58)

        return ZStack(alignment: .topLeading) {
            widePreviewBackground(size: size, kind: style.backgroundKind)
            routeGraphic(frame: routeFrame, backgroundKind: style.backgroundKind)

            VStack(alignment: .leading, spacing: 0) {
                brandMark(foreground: foreground)
                Spacer()

                if style.layout == .heroOnly {
                    HStack(alignment: .bottom, spacing: 14) {
                        if let hero {
                            metricHeroBlock(metric: hero.0, display: hero.1, foreground: foreground, secondary: secondary, large: false)
                        }
                        Spacer(minLength: 8)
                    }
                } else {
                    HStack(spacing: 16) {
                        ForEach(footerMetrics, id: \.0.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.1.main)
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(foreground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .monospacedDigit()

                                Text(item.1.unit ?? item.0.title(appLanguage))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
    }

    private func portraitCardBackground(size: CGSize) -> some View {
        ZStack {
            switch backgroundMode {
            case .white:
                Color.white
            case .transparent:
                checkerPreview
            case .fullPhoto:
                photoCardLayer(size: size, inset: 0, cornerRadius: 0)
            case .overlayPhoto:
                Color.white
                photoCardLayer(size: size, inset: 14, cornerRadius: 22)
            }

            if backgroundMode == .fullPhoto {
                LinearGradient(
                    colors: [Color.black.opacity(0.06), Color.black.opacity(0.12), Color.black.opacity(0.46)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if backgroundMode == .overlayPhoto {
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.34), Color.white.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func widePreviewBackground(size: CGSize, kind: PreviewBackgroundKind) -> some View {
        ZStack {
            switch kind {
            case .light:
                Color.white
            case .dark:
                LinearGradient(
                    colors: [Color.black.opacity(0.92), Color.black.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .photo:
                if selectedPhotoImage != nil {
                    photoCardLayer(size: size, inset: 0, cornerRadius: 0)
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.black.opacity(0.36)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.28, green: 0.34, blue: 0.44), Color(red: 0.06, green: 0.08, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private func photoCardLayer(size: CGSize, inset: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if let selectedPhotoImage {
                GeometryReader { geometry in
                    let frameWidth = max(10, geometry.size.width - inset * 2)
                    let frameHeight = max(10, geometry.size.height - inset * 2)

                    Image(uiImage: selectedPhotoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frameWidth, height: frameHeight)
                        .scaleEffect(photoScale)
                        .offset(x: photoOffset.width, y: photoOffset.height)
                        .opacity(photoOpacity)
                        .brightness(photoBrightness)
                        .contrast(photoContrast)
                        .blur(radius: photoBlur)
                        .frame(width: frameWidth, height: frameHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            } else {
                LinearGradient(
                    colors: [Color(red: 0.92, green: 0.94, blue: 0.98), Color(red: 0.80, green: 0.86, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private func brandMark(foreground: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(headerAccentColor)
                .frame(width: 8, height: 8)

            Text("BEAMCHASER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(foreground)
                .tracking(1.1)
        }
    }

    private func metricHeroBlock(metric: ShareMetricToggle, display: ShareMetricValueDisplay, foreground: Color? = nil, secondary: Color? = nil, large: Bool = true) -> some View {
        let resolvedForeground = foreground ?? cardTextColor
        let resolvedSecondary = secondary ?? cardSecondaryTextColor

        return HStack(alignment: .lastTextBaseline, spacing: display.unit == nil ? 0 : (large ? 4 : 3)) {
            Text(display.main)
                .font(.system(size: large ? 62 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(resolvedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()

            if let unit = display.unit {
                Text(unit)
                    .font(.system(size: large ? 19 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(resolvedSecondary)
            }
        }
    }

    private func smallMetricCell(metric: ShareMetricToggle, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(cardSecondaryTextColor)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(cardSecondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
    }

    private func photoOptionPreview(mode: BackgroundMode) -> some View {
        ZStack {
            switch mode {
            case .fullPhoto:
                if let selectedPhotoImage {
                    Image(uiImage: selectedPhotoImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.92, green: 0.82, blue: 0.68), Color(red: 0.60, green: 0.68, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .overlayPhoto:
                Color.white
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .padding(6)
                    .overlay {
                        if let selectedPhotoImage {
                            Image(uiImage: selectedPhotoImage)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(6)
                        }
                    }
            case .white:
                Color.white
            case .transparent:
                checkerPreview
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var checkerPreview: some View {
        GeometryReader { geometry in
            let columns = 4
            let rows = 3
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ZStack {
                Color.white
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? Color.black.opacity(0.03) : Color.clear)
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: cellWidth * (CGFloat(column) + 0.5),
                                y: cellHeight * (CGFloat(row) + 0.5)
                            )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func routeGraphic(frame: CGRect, backgroundMode: BackgroundMode? = nil, backgroundKind: PreviewBackgroundKind? = nil) -> some View {
        let rect = CGRect(origin: .zero, size: frame.size)
        let points = routePreviewPoints(in: rect.insetBy(dx: 6, dy: 6))
        let path = smoothedRoutePath(points)
        let lineWidth = CGFloat(routeLineWidth)
        let glowOpacity = (backgroundMode == .fullPhoto || backgroundKind == .dark || backgroundKind == .photo ? 0.28 : 0.12) * routeStrokeStyle.glowMultiplier
        let monoColor = (backgroundMode == .fullPhoto || backgroundKind == .dark || backgroundKind == .photo) ? Color.white : Color.black
        let resolvedOpacity = routeStrokeStyle.opacityMultiplier
        let strokeStyle = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: routeStrokeStyle.dashPattern
        )
        let routeShapeStyle = routeStrokeStyle.usesMonochrome
            ? AnyShapeStyle(monoColor.opacity(resolvedOpacity))
            : AnyShapeStyle(
                LinearGradient(
                    colors: routeColorPreset.gradientColors.map { $0.opacity(resolvedOpacity) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        let glowShapeStyle = routeStrokeStyle.usesMonochrome
            ? AnyShapeStyle(monoColor.opacity(glowOpacity))
            : AnyShapeStyle(
                LinearGradient(
                    colors: routeColorPreset.gradientColors.map { $0.opacity(glowOpacity) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

        return ZStack {
            path
                .stroke(glowShapeStyle, style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round, lineJoin: .round, dash: routeStrokeStyle.dashPattern))
                .blur(radius: 6)

            path
                .stroke(routeShapeStyle, style: strokeStyle)

            if let start = points.first {
                Circle()
                    .fill(routeColorPreset.gradientColors.first ?? routeColorPreset.primaryColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .position(start)
            }

            if let end = points.last {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.red.opacity(0.90), lineWidth: 3))
                    .position(end)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }

    private func routePreviewPoints(in rect: CGRect) -> [CGPoint] {
        let actualPoints = normalizedRoutePoints(in: rect)
        if !actualPoints.isEmpty {
            return actualPoints
        }

        return [
            CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.08),
            CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.68),
            CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.50),
            CGPoint(x: rect.minX + rect.width * 0.56, y: rect.maxY - rect.height * 0.80),
            CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY - rect.height * 0.36),
            CGPoint(x: rect.minX + rect.width * 0.90, y: rect.maxY - rect.height * 0.18)
        ]
    }

    private func normalizedRoutePoints(in rect: CGRect) -> [CGPoint] {
        guard hasRenderableRoute else { return [] }

        let latitudes = record.routePoints.map(\.latitude)
        let longitudes = record.routePoints.map(\.longitude)

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return []
        }

        let latSpan = max(maxLat - minLat, 0.000001)
        let lonSpan = max(maxLon - minLon, 0.000001)
        let routeAspect = lonSpan / latSpan
        let rectAspect = rect.width / max(rect.height, 1)
        let maxWidth = rect.width * 0.88
        let maxHeight = rect.height * 0.88

        let fittedSize: CGSize
        if routeAspect > rectAspect {
            fittedSize = CGSize(width: maxWidth, height: maxWidth / routeAspect)
        } else {
            fittedSize = CGSize(width: maxHeight * routeAspect, height: maxHeight)
        }

        let origin = CGPoint(
            x: rect.midX - fittedSize.width / 2,
            y: rect.midY - fittedSize.height / 2
        )

        return record.routePoints.map { point in
            let normalizedX = (point.longitude - minLon) / lonSpan
            let normalizedY = 1 - ((point.latitude - minLat) / latSpan)

            return CGPoint(
                x: origin.x + fittedSize.width * normalizedX,
                y: origin.y + fittedSize.height * normalizedY
            )
        }
    }

    private func smoothedRoutePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)

        guard points.count > 2 else {
            path.addLines(Array(points.dropFirst()))
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[min(index + 1, points.count - 1)]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            let control = CGPoint(
                x: current.x - (next.x - previous.x) * 0.18,
                y: current.y - (next.y - previous.y) * 0.18
            )
            path.addQuadCurve(to: midpoint, control: control)

            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: midpoint)
            }
        }

        return path
    }

    private func metricDisplays(for template: ShareTemplate) -> [(ShareMetricToggle, ShareMetricValueDisplay)] {
        template.defaultOrder.compactMap { metric in
            guard template.defaultMetrics.contains(metric), let display = metric.valueDisplay(from: record) else { return nil }
            return (metric, display)
        }
    }

    private func widePreviewForegroundColor(for kind: PreviewBackgroundKind) -> Color {
        switch kind {
        case .light:
            return .black
        case .dark, .photo:
            return .white
        }
    }

    private func widePreviewSecondaryColor(for kind: PreviewBackgroundKind) -> Color {
        switch kind {
        case .light:
            return Color.black.opacity(0.58)
        case .dark, .photo:
            return Color.white.opacity(0.72)
        }
    }

    private var photoAdjustmentBinding: Binding<Double> {
        switch selectedPhotoAdjustment {
        case .scale:
            return Binding(
                get: { photoScale },
                set: { photoScale = min(max($0, 0.8), 2.4) }
            )
        case .positionX:
            return Binding(
                get: { Double(photoOffset.width) },
                set: { photoOffset.width = CGFloat($0) }
            )
        case .positionY:
            return Binding(
                get: { Double(photoOffset.height) },
                set: { photoOffset.height = CGFloat($0) }
            )
        case .opacity:
            return $photoOpacity
        case .blur:
            return $photoBlur
        case .brightness:
            return $photoBrightness
        case .contrast:
            return $photoContrast
        }
    }

    private var photoAdjustmentRange: ClosedRange<Double> {
        switch selectedPhotoAdjustment {
        case .scale:
            return 0.8...2.4
        case .positionX:
            return -70...70
        case .positionY:
            return -90...90
        case .opacity:
            return 0.2...1.0
        case .blur:
            return 0...18
        case .brightness:
            return -0.4...0.4
        case .contrast:
            return 0.5...1.8
        }
    }

    private func photoAdjustmentValueText(_ value: Double) -> String {
        switch selectedPhotoAdjustment {
        case .scale:
            return String(format: "%.2f", value)
        case .positionX, .positionY:
            return String(format: "%.0f", value)
        case .opacity:
            return String(format: "%.0f%%", value * 100)
        case .blur:
            return String(format: "%.0f", value)
        case .brightness:
            return String(format: "%+.2f", value)
        case .contrast:
            return String(format: "%.2f", value)
        }
    }

    private func applyTemplate(_ template: ShareTemplate) {
        selectedTemplate = template
        visibleMetrics = template.defaultMetrics.filterSet { $0.valueDisplay(from: record) != nil }
        metricOrder = mergeMetricOrder(preferred: template.defaultOrder)
    }

    private func mergeMetricOrder(preferred: [ShareMetricToggle]) -> [ShareMetricToggle] {
        preferred + ShareMetricToggle.allCases.filter { !preferred.contains($0) }
    }

    private func toggleMetric(_ metric: ShareMetricToggle) {
        guard metric.valueDisplay(from: record) != nil else { return }

        if visibleMetrics.contains(metric) {
            visibleMetrics.remove(metric)
        } else {
            visibleMetrics.insert(metric)
        }
    }

    private func resetMetricLayout() {
        metricOrder = mergeMetricOrder(preferred: selectedTemplate.defaultOrder)
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhotoImage = image
        if backgroundMode != .overlayPhoto {
            backgroundMode = .fullPhoto
        }
        selectedControlPanel = .photo
    }

    private func removePhoto() {
        selectedPhotoItem = nil
        selectedPhotoImage = nil
        photoScale = 1.0
        photoOffset = .zero
        photoOpacity = 0.94
        photoBlur = 0
        photoBrightness = 0
        photoContrast = 1.0
        if backgroundMode.usesPhoto {
            backgroundMode = .white
        }
    }

    @MainActor
    private func renderShareImage(scale: CGFloat = 3.0) -> UIImage? {
        let renderer = ImageRenderer(
            content: portraitShareCard(size: previewCanvasSize)
                .frame(width: previewCanvasSize.width, height: previewCanvasSize.height)
        )
        renderer.scale = scale
        renderer.isOpaque = backgroundMode != .transparent
        return renderer.uiImage
    }

    @MainActor
    private func renderShareData() -> Data? {
        renderShareImage()?.pngData()
    }

    @MainActor
    private func shareCard() {
        guard let image = renderShareImage(), let data = image.pngData() else {
            statusText = appLanguage.text("공유 이미지를 만들지 못했어요.", "Couldn't render the share image.")
            statusTint = RBColor.danger
            return
        }

        if let storyURL = URL(string: "instagram-stories://share"),
           UIApplication.shared.canOpenURL(storyURL) {
            UIPasteboard.general.setItems(
                [[
                    "com.instagram.sharedSticker.stickerImage": data,
                    "com.instagram.sharedSticker.backgroundTopColor": backgroundMode == .fullPhoto ? "#141414" : "#F7F6F2",
                    "com.instagram.sharedSticker.backgroundBottomColor": backgroundMode == .fullPhoto ? "#141414" : "#F7F6F2"
                ]],
                options: [.expirationDate: Date().addingTimeInterval(300)]
            )
            UIApplication.shared.open(storyURL)
            return
        }

        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        topViewController()?.present(controller, animated: true)
    }

    @MainActor
    private func postToCommunity() async {
        guard let userId = backendService.userId else {
            statusText = appLanguage.text("로그인 후 등록할 수 있어요.", "Sign in to post.")
            statusTint = RBColor.danger
            return
        }

        guard let imageData = renderShareData() else {
            statusText = appLanguage.text("공유 카드를 만들지 못했어요.", "Couldn't render the share card.")
            statusTint = RBColor.danger
            return
        }

        let author = backendService.currentUser
        isPosting = true
        defer { isPosting = false }

        do {
            let photoURL = try await backendService.uploadPhoto(
                data: imageData,
                path: "feed_photos/\(userId)/share_cards/\(UUID().uuidString).png",
                contentType: "image/png"
            )

            let post = FirestoreFeedPost(
                id: UUID().uuidString,
                authorId: userId,
                authorName: author?.displayName ?? appLanguage.text("러너", "Runner"),
                authorLevel: author?.level ?? RunnerLevel.starter.rawValue,
                headline: resolvedHeadline,
                content: resolvedFeedBody,
                runId: record.id.uuidString,
                runStartedAt: record.startDate,
                distanceKm: record.distanceKm,
                durationFormatted: record.formattedDuration,
                paceFormatted: record.formattedPace,
                averageHeartRateBpm: record.averageHeartRateBpm,
                averageSpeedKmh: record.averageSpeedKmh,
                cadenceSpm: record.averageCadenceSpm,
                elevationGainMeters: record.elevationGainMeters,
                caloriesKcal: record.estimatedCaloriesKcal,
                targetPaceFormatted: record.targetPace?.formatted,
                goalDeltaSeconds: record.goalDeltaSeconds,
                selectedMetricKeys: selectedMetricKeysForPost.map(\.rawValue),
                photoURL: photoURL,
                likedUserIds: [],
                comments: [],
                type: RunnerPost.PostType.runResult.firestoreValue,
                createdAt: Date()
            )

            try await backendService.createFeedPost(post)
            statusText = appLanguage.text("공유 카드가 피드에 등록됐어요.", "The share card was posted to the feed.")
            statusTint = RBColor.success
        } catch {
            statusText = appLanguage.text("등록에 실패했습니다: \(error.localizedDescription)", "Couldn't post: \(error.localizedDescription)")
            statusTint = RBColor.danger
        }
    }

    private func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController

        var controller = root
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

private extension Set {
    func filterSet(_ isIncluded: (Element) -> Bool) -> Set<Element> {
        Set(filter(isIncluded))
    }
}
