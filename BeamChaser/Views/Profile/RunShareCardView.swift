import SwiftUI
import UIKit
import PhotosUI
import CoreLocation

private enum ShareMetricToggle: String, CaseIterable, Identifiable {
    case distance
    case time
    case pace
    case calories

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .distance:
            return appLanguage.text("거리", "distance")
        case .time:
            return appLanguage.text("시간", "time")
        case .pace:
            return appLanguage.text("페이스", "pace")
        case .calories:
            return appLanguage.text("칼로리", "calories")
        }
    }

    func value(from record: RunRecord) -> String? {
        switch self {
        case .distance:
            guard record.distanceKm > 0 else { return nil }
            return String(format: "%.2f km", record.distanceKm)
        case .time:
            guard record.elapsedSeconds > 0 else { return nil }
            return record.formattedDuration
        case .pace:
            guard record.averagePaceSecondsPerKm > 0 else { return nil }
            return record.formattedPace
        case .calories:
            guard record.estimatedCaloriesKcal > 0 else { return nil }
            return String(format: "%.0f kcal", record.estimatedCaloriesKcal)
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

private struct CanvasTransform: Equatable {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var rotation: Angle = .zero

    mutating func clamp(scale range: ClosedRange<CGFloat>) {
        scale = min(max(scale, range.lowerBound), range.upperBound)
    }
}

private enum ShareTemplate: String, CaseIterable, Identifiable {
    case routeOnly
    case routeTime
    case routeDistance
    case fullStats

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .routeOnly:
            return appLanguage.text("경로만", "Route Only")
        case .routeTime:
            return appLanguage.text("경로 + 시간", "Route + Time")
        case .routeDistance:
            return appLanguage.text("경로 + 거리", "Route + Distance")
        case .fullStats:
            return appLanguage.text("전체 수치", "Full Stats")
        }
    }

    var defaultMetrics: Set<ShareMetricToggle> {
        switch self {
        case .routeOnly:
            return []
        case .routeTime:
            return [.time]
        case .routeDistance:
            return [.distance]
        case .fullStats:
            return [.distance, .time, .pace, .calories]
        }
    }

    var preferredHeroMetric: ShareMetricToggle? {
        switch self {
        case .routeOnly:
            return nil
        case .routeTime:
            return .time
        case .routeDistance:
            return .distance
        case .fullStats:
            return .distance
        }
    }
}

private enum RouteColorPreset: String, CaseIterable, Identifiable {
    case black
    case laserOrange
    case red
    case electricBlue

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .black:
            return appLanguage.text("검정", "black")
        case .laserOrange:
            return appLanguage.text("레이저 오렌지", "laser orange")
        case .red:
            return appLanguage.text("빨강", "red")
        case .electricBlue:
            return appLanguage.text("일렉트릭 블루", "electric blue")
        }
    }

    var solidColor: Color {
        switch self {
        case .black:
            return .black
        case .laserOrange:
            return Color(red: 0.91, green: 0.48, blue: 0.13)
        case .red:
            return Color(red: 0.79, green: 0.19, blue: 0.18)
        case .electricBlue:
            return Color(red: 0.17, green: 0.44, blue: 0.92)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .black:
            return [.black, .black]
        case .laserOrange:
            return [Color(red: 0.98, green: 0.69, blue: 0.33), Color(red: 0.86, green: 0.38, blue: 0.09)]
        case .red:
            return [Color(red: 0.9, green: 0.42, blue: 0.35), Color(red: 0.67, green: 0.13, blue: 0.16)]
        case .electricBlue:
            return [Color(red: 0.48, green: 0.76, blue: 1.0), Color(red: 0.06, green: 0.32, blue: 0.86)]
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
            return appLanguage.text("화이트", "white")
        case .fullPhoto:
            return appLanguage.text("전체 사진", "full")
        case .overlayPhoto:
            return appLanguage.text("오버레이", "overlay")
        case .transparent:
            return appLanguage.text("투명", "transparent")
        }
    }

    var usesPhoto: Bool {
        switch self {
        case .white, .transparent:
            return false
        case .fullPhoto, .overlayPhoto:
            return true
        }
    }
}

private enum EditableLayer: Hashable {
    case photo
    case route
    case primaryMetric
    case secondaryMetrics
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
            return appLanguage.text("스케일", "scale")
        case .positionX:
            return appLanguage.text("가로", "x")
        case .positionY:
            return appLanguage.text("세로", "y")
        case .opacity:
            return appLanguage.text("투명도", "opacity")
        case .blur:
            return appLanguage.text("블러", "blur")
        case .brightness:
            return appLanguage.text("밝기", "brightness")
        case .contrast:
            return appLanguage.text("대비", "contrast")
        }
    }
}

private enum FontPreset: String, CaseIterable, Identifiable {
    case athletic
    case clean
    case mono

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .athletic:
            return appLanguage.text("애슬레틱", "athletic")
        case .clean:
            return appLanguage.text("클린", "clean")
        case .mono:
            return appLanguage.text("모노", "mono")
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
            return appLanguage.text("수치", "metrics")
        case .style:
            return appLanguage.text("스타일", "style")
        case .photo:
            return appLanguage.text("사진", "photo")
        }
    }
}

private struct FloatingChip: View {
    let title: String
    let selected: Bool
    let enabled: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: selected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var foregroundColor: Color {
        guard enabled else { return Color.black.opacity(0.22) }
        return selected ? .black : Color.black.opacity(0.58)
    }

    private var backgroundColor: Color {
        guard enabled else { return Color.black.opacity(0.03) }
        return selected ? Color.black.opacity(0.08) : Color.white
    }

    private var borderColor: Color {
        guard enabled else { return Color.black.opacity(0.05) }
        return selected ? Color.black.opacity(0.18) : Color.black.opacity(0.08)
    }
}

private struct TemplateThumbnail: View {
    let title: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 46, height: 3)
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 28, height: 3)
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 20, height: 3)
            }
        }
        .padding(14)
        .frame(width: 132, height: 84, alignment: .leading)
        .background(selected ? Color.black.opacity(0.06) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? Color.black.opacity(0.18) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SelectionOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.black.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .overlay(alignment: .topLeading) { handle }
            .overlay(alignment: .topTrailing) { handle }
            .overlay(alignment: .bottomLeading) { handle }
            .overlay(alignment: .bottomTrailing) { handle }
            .padding(-8)
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 1))
            .padding(3)
    }
}

private struct EditableCanvasLayer<Content: View>: View {
    let layer: EditableLayer
    @Binding var selectedLayer: EditableLayer?
    @Binding var transform: CanvasTransform
    let interactive: Bool
    let allowsRotation: Bool
    let scaleRange: ClosedRange<CGFloat>
    let content: Content

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureRotation: Angle = .zero

    init(
        layer: EditableLayer,
        selectedLayer: Binding<EditableLayer?>,
        transform: Binding<CanvasTransform>,
        interactive: Bool,
        allowsRotation: Bool = true,
        scaleRange: ClosedRange<CGFloat> = 0.55...3.0,
        @ViewBuilder content: () -> Content
    ) {
        self.layer = layer
        _selectedLayer = selectedLayer
        _transform = transform
        self.interactive = interactive
        self.allowsRotation = allowsRotation
        self.scaleRange = scaleRange
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .overlay {
                if interactive, selectedLayer == layer {
                    SelectionOverlay()
                }
            }
            .scaleEffect(transform.scale * gestureScale)
            .rotationEffect(transform.rotation + gestureRotation)
            .offset(
                x: transform.offset.width + dragTranslation.width,
                y: transform.offset.height + dragTranslation.height
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard interactive else { return }
                selectedLayer = layer
            }
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(scaleGesture)
            .simultaneousGesture(rotationGesture)
            .allowsHitTesting(interactive)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                guard interactive else { return }
                state = value.translation
            }
            .onEnded { value in
                guard interactive else { return }
                transform.offset.width += value.translation.width
                transform.offset.height += value.translation.height
            }
    }

    private var scaleGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                guard interactive else { return }
                state = value
            }
            .onEnded { value in
                guard interactive else { return }
                transform.scale *= value
                transform.clamp(scale: scaleRange)
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .updating($gestureRotation) { value, state, _ in
                guard interactive, allowsRotation else { return }
                state = value
            }
            .onEnded { value in
                guard interactive, allowsRotation else { return }
                transform.rotation += value
            }
    }
}

struct RunShareCardView: View {
    let record: RunRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backendService: BackendService
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var selectedTemplate: ShareTemplate = .fullStats
    @State private var visibleMetrics: Set<ShareMetricToggle> = ShareTemplate.fullStats.defaultMetrics
    @State private var selectedLayer: EditableLayer?

    @State private var routeTransform = CanvasTransform(offset: CGSize(width: 0, height: -30), scale: 1.0)
    @State private var primaryMetricTransform = CanvasTransform(offset: CGSize(width: 0, height: 144), scale: 1.0)
    @State private var secondaryMetricsTransform = CanvasTransform(offset: CGSize(width: 0, height: 194), scale: 1.0)
    @State private var photoTransform = CanvasTransform(scale: 1.0)

    @State private var routeColorPreset: RouteColorPreset = .black
    @State private var routeLineWidth: Double = 2.8
    @State private var routeGlowIntensity: Double = 0.65
    @State private var selectedFontPreset: FontPreset = .athletic
    @State private var selectedControlPanel: EditorControlPanel = .metrics
    @State private var backgroundMode: BackgroundMode = .white
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var selectedPhotoAdjustment: PhotoAdjustment = .scale
    @State private var photoOpacity: Double = 0.9
    @State private var photoBlur: Double = 0
    @State private var photoBrightness: Double = 0
    @State private var photoContrast: Double = 1.0

    @State private var isPosting = false
    @State private var statusText: String?
    @State private var statusTint: Color = .black
    @State private var templateToastText: String?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var canvasSize: CGSize {
        let width = min(UIScreen.main.bounds.width - 32, 404)
        return CGSize(width: width, height: width * 1.18)
    }

    private var hasRenderableRoute: Bool {
        record.routePoints.count >= 2 && record.totalDistanceMeters > 5
    }

    private var activeMetricTexts: [(ShareMetricToggle, String)] {
        ShareMetricToggle.allCases.compactMap { metric in
            guard visibleMetrics.contains(metric), let value = metric.value(from: record) else { return nil }
            return (metric, value)
        }
    }

    private var heroMetric: ShareMetricToggle? {
        if let preferred = selectedTemplate.preferredHeroMetric,
           visibleMetrics.contains(preferred),
           preferred.value(from: record) != nil {
            return preferred
        }
        return activeMetricTexts.first?.0
    }

    private var heroMetricText: String? {
        guard let heroMetric else { return nil }
        return heroMetric.value(from: record)
    }

    private var secondaryMetricTexts: [String] {
        activeMetricTexts
            .filter { $0.0 != heroMetric }
            .map(\.1)
    }

    private var primaryTextColor: Color {
        switch backgroundMode {
        case .white, .transparent:
            return .black
        case .fullPhoto, .overlayPhoto:
            return .white
        }
    }

    private var secondaryTextColor: Color {
        switch backgroundMode {
        case .white, .transparent:
            return Color.black.opacity(0.66)
        case .fullPhoto, .overlayPhoto:
            return Color.white.opacity(0.86)
        }
    }

    private var textShadowColor: Color {
        switch backgroundMode {
        case .white, .transparent:
            return .clear
        case .fullPhoto, .overlayPhoto:
            return Color.black.opacity(0.26)
        }
    }

    private var canPost: Bool {
        backendService.isSignedIn && !isPosting
    }

    var body: some View {
        RunShareScreen(record: record)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                FloatingChip(
                    title: appLanguage.text("닫기", "close"),
                    selected: false,
                    enabled: true
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task {
                    await postToCommunity()
                }
            } label: {
                FloatingChip(
                    title: isPosting ? appLanguage.text("등록 중", "posting") : appLanguage.text("피드", "feed"),
                    selected: false,
                    enabled: canPost
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPost)

            Button {
                shareCard()
            } label: {
                FloatingChip(
                    title: appLanguage.text("공유", "share"),
                    selected: false,
                    enabled: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var templateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ShareTemplate.allCases) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        TemplateThumbnail(
                            title: template.title(appLanguage),
                            selected: selectedTemplate == template
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var previewCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)

            canvasContent(size: canvasSize, forExport: false)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

            if let templateToastText {
                VStack {
                    Text(templateToastText)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.74))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Spacer()
                }
                .padding(.top, 18)
                .allowsHitTesting(false)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .frame(maxWidth: .infinity)
        .simultaneousGesture(templateSwipeGesture)
    }

    @ViewBuilder
    private func canvasContent(size: CGSize, forExport: Bool) -> some View {
        ZStack {
            canvasBackground

            if backgroundMode.usesPhoto, let selectedPhotoImage {
                photoLayer(image: selectedPhotoImage, canvasSize: size, forExport: forExport)
            }

            if hasRenderableRoute {
                routeLayer(canvasSize: size, forExport: forExport)
            }

            if let heroMetricText {
                primaryMetricLayer(text: heroMetricText, forExport: forExport)
            }

            if !secondaryMetricTexts.isEmpty {
                secondaryMetricsLayer(texts: secondaryMetricTexts, forExport: forExport)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !forExport else { return }
            selectedLayer = nil
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        switch backgroundMode {
        case .white, .overlayPhoto:
            Color.white
        case .fullPhoto:
            Color.black.opacity(0.04)
        case .transparent:
            Color.clear
        }
    }

    private func photoLayer(image: UIImage, canvasSize: CGSize, forExport: Bool) -> some View {
        let baseSize = photoBaseSize(for: canvasSize)
        let cornerRadius: CGFloat = backgroundMode == .overlayPhoto ? 20 : 0

        return EditableCanvasLayer(
            layer: .photo,
            selectedLayer: $selectedLayer,
            transform: $photoTransform,
            interactive: !forExport,
            allowsRotation: false,
            scaleRange: 0.6...3.2
        ) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: baseSize.width, height: baseSize.height)
                    .opacity(photoOpacity)
                    .brightness(photoBrightness)
                    .contrast(photoContrast)
                    .blur(radius: photoBlur)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                if backgroundMode == .fullPhoto {
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: baseSize.width, height: baseSize.height)
                }
            }
        }
    }

    private func routeLayer(canvasSize: CGSize, forExport: Bool) -> some View {
        let frame = routeFrameSize(for: canvasSize)
        let strokeWidth = CGFloat(routeLineWidth)

        return EditableCanvasLayer(
            layer: .route,
            selectedLayer: $selectedLayer,
            transform: $routeTransform,
            interactive: !forExport,
            allowsRotation: true,
            scaleRange: 0.6...2.2
        ) {
            GeometryReader { geometry in
                let rect = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 12, dy: 12)
                let points = normalizedRoutePoints(in: rect)
                let path = smoothedRoutePath(points)

                ZStack {
                    if routeGlowOpacity > 0 {
                        path
                            .stroke(routeGlowColor.opacity(routeGlowOpacity), style: StrokeStyle(lineWidth: strokeWidth + 3.4, lineCap: .square, lineJoin: .miter))
                            .blur(radius: backgroundMode == .white ? 2 : 4)
                    }

                    if backgroundMode == .white || routeColorPreset == .black {
                        path
                            .stroke(routeColorPreset.solidColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .square, lineJoin: .miter))
                    } else {
                        path
                            .stroke(
                                LinearGradient(
                                    colors: routeColorPreset.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .square, lineJoin: .miter)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: frame.width, height: frame.height)
        }
    }

    private func primaryMetricLayer(text: String, forExport: Bool) -> some View {
        EditableCanvasLayer(
            layer: .primaryMetric,
            selectedLayer: $selectedLayer,
            transform: $primaryMetricTransform,
            interactive: !forExport,
            allowsRotation: true,
            scaleRange: 0.55...2.4
        ) {
            Text(text)
                .font(heroFont(for: text))
                .foregroundStyle(primaryTextColor)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .tracking(selectedFontPreset == .mono ? -0.8 : -2.0)
                .shadow(color: textShadowColor, radius: 8, y: 3)
        }
    }

    private func secondaryMetricsLayer(texts: [String], forExport: Bool) -> some View {
        EditableCanvasLayer(
            layer: .secondaryMetrics,
            selectedLayer: $selectedLayer,
            transform: $secondaryMetricsTransform,
            interactive: !forExport,
            allowsRotation: true,
            scaleRange: 0.55...2.2
        ) {
            VStack(spacing: 6) {
                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(secondaryMetricFont())
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: textShadowColor, radius: 6, y: 2)
                }
            }
        }
    }

    private var floatingDock: some View {
        VStack(spacing: 12) {
            chipRow {
                ForEach(EditorControlPanel.allCases) { panel in
                    Button {
                        selectedControlPanel = panel
                    } label: {
                        FloatingChip(
                            title: panel.title(appLanguage),
                            selected: selectedControlPanel == panel,
                            enabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            switch selectedControlPanel {
            case .metrics:
                chipRow {
                    ForEach(ShareMetricToggle.allCases) { metric in
                        Button {
                            toggleMetric(metric)
                        } label: {
                            FloatingChip(
                                title: metric.title(appLanguage),
                                selected: visibleMetrics.contains(metric),
                                enabled: metric.value(from: record) != nil
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(metric.value(from: record) == nil)
                    }
                }
            case .style:
                chipRow {
                    ForEach(RouteColorPreset.allCases) { preset in
                        Button {
                            routeColorPreset = preset
                        } label: {
                            FloatingChip(
                                title: preset.title(appLanguage),
                                selected: routeColorPreset == preset,
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingSlider(
                    title: appLanguage.text("두께", "thickness"),
                    value: $routeLineWidth,
                    range: 1.4...6.4,
                    format: { String(format: "%.1f", $0) }
                )

                settingSlider(
                    title: appLanguage.text("글로우", "glow"),
                    value: $routeGlowIntensity,
                    range: 0...1,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )

                chipRow {
                    ForEach(FontPreset.allCases) { preset in
                        Button {
                            selectedFontPreset = preset
                        } label: {
                            FloatingChip(
                                title: preset.title(appLanguage),
                                selected: selectedFontPreset == preset,
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .photo:
                chipRow {
                    ForEach(BackgroundMode.allCases) { mode in
                        Button {
                            guard mode == .white || mode == .transparent || selectedPhotoImage != nil else { return }
                            backgroundMode = mode
                        } label: {
                            FloatingChip(
                                title: mode.title(appLanguage),
                                selected: backgroundMode == mode,
                                enabled: mode == .white || mode == .transparent || selectedPhotoImage != nil
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        FloatingChip(
                            title: appLanguage.text(selectedPhotoImage == nil ? "사진" : "변경", selectedPhotoImage == nil ? "photo" : "change"),
                            selected: false,
                            enabled: true
                        )
                    }

                    if selectedPhotoImage != nil {
                        Button {
                            removePhoto()
                        } label: {
                            FloatingChip(
                                title: appLanguage.text("삭제", "remove"),
                                selected: false,
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedPhotoImage != nil, backgroundMode.usesPhoto {
                    chipRow {
                        ForEach(PhotoAdjustment.allCases) { adjustment in
                            Button {
                                selectedPhotoAdjustment = adjustment
                                selectedLayer = .photo
                            } label: {
                                FloatingChip(
                                    title: adjustment.title(appLanguage),
                                    selected: selectedPhotoAdjustment == adjustment,
                                    enabled: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingSlider(
                        title: selectedPhotoAdjustment.title(appLanguage),
                        value: photoAdjustmentBinding,
                        range: photoAdjustmentRange,
                        format: photoAdjustmentValueText
                    )
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                content()
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 40)
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))

                Spacer()

                Text(format(value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.62))
            }

            Slider(value: value, in: range)
                .tint(routeColorPreset == .black ? .black : routeColorPreset.solidColor)
        }
        .padding(.horizontal, 4)
    }

    private var routeGlowColor: Color {
        routeColorPreset.gradientColors.first ?? routeColorPreset.solidColor
    }

    private var routeGlowOpacity: Double {
        guard routeColorPreset != .black else { return 0 }
        let baseOpacity: Double
        switch backgroundMode {
        case .white:
            baseOpacity = 0.05
        case .fullPhoto, .overlayPhoto, .transparent:
            baseOpacity = 0.16
        }
        return baseOpacity * routeGlowIntensity
    }

    private func photoBaseSize(for canvasSize: CGSize) -> CGSize {
        switch backgroundMode {
        case .fullPhoto:
            return CGSize(width: canvasSize.width * 1.08, height: canvasSize.height * 1.08)
        case .overlayPhoto:
            return CGSize(width: canvasSize.width * 0.9, height: canvasSize.height * 0.62)
        case .white, .transparent:
            return .zero
        }
    }

    private func routeFrameSize(for canvasSize: CGSize) -> CGSize {
        let width = canvasSize.width * 0.86
        let heightMultiplier: CGFloat = selectedTemplate == .routeOnly ? 0.62 : 0.5
        return CGSize(width: width, height: canvasSize.height * heightMultiplier)
    }

    private func heroFontSize(for text: String) -> CGFloat {
        text.count >= 9 ? 72 : 84
    }

    private func heroFont(for text: String) -> Font {
        switch selectedFontPreset {
        case .athletic:
            return .system(size: heroFontSize(for: text), weight: .black, design: .default)
        case .clean:
            return .system(size: heroFontSize(for: text), weight: .bold, design: .rounded)
        case .mono:
            return .system(size: heroFontSize(for: text), weight: .bold, design: .monospaced)
        }
    }

    private func secondaryMetricFont() -> Font {
        switch selectedFontPreset {
        case .athletic:
            return .system(size: 24, weight: .semibold, design: .default)
        case .clean:
            return .system(size: 24, weight: .medium, design: .rounded)
        case .mono:
            return .system(size: 24, weight: .medium, design: .monospaced)
        }
    }

    private func toggleMetric(_ metric: ShareMetricToggle) {
        guard metric.value(from: record) != nil else { return }

        if visibleMetrics.contains(metric) {
            visibleMetrics.remove(metric)
        } else {
            visibleMetrics.insert(metric)
        }

        if heroMetricText == nil {
            selectedLayer = hasRenderableRoute ? .route : nil
        }
    }

    private func applyTemplate(_ template: ShareTemplate) {
        visibleMetrics = template.defaultMetrics.filterSet { $0.value(from: record) != nil }
        let routeVisible = hasRenderableRoute

        switch template {
        case .routeOnly:
            routeTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? -12 : 0), scale: routeVisible ? 1.08 : 1.0)
            primaryMetricTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 138 : 0), scale: 1.0)
            secondaryMetricsTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 188 : 72), scale: 1.0)
        case .routeTime:
            routeTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? -32 : 0), scale: 1.0)
            primaryMetricTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 124 : 0), scale: 1.0)
            secondaryMetricsTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 176 : 70), scale: 1.0)
        case .routeDistance:
            routeTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? -28 : 0), scale: 1.0)
            primaryMetricTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 126 : 0), scale: 1.0)
            secondaryMetricsTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 178 : 70), scale: 1.0)
        case .fullStats:
            routeTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? -46 : 0), scale: routeVisible ? 0.96 : 1.0)
            primaryMetricTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 108 : -8), scale: 1.0)
            secondaryMetricsTransform = CanvasTransform(offset: CGSize(width: 0, height: routeVisible ? 166 : 66), scale: 1.0)
        }

        selectedLayer = nil
    }

    private var templateSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard selectedLayer == nil else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 44, abs(horizontal) > abs(vertical) else { return }
                stepTemplate(horizontal < 0 ? 1 : -1)
            }
    }

    private func stepTemplate(_ direction: Int) {
        guard let currentIndex = ShareTemplate.allCases.firstIndex(of: selectedTemplate) else { return }
        let nextIndex = currentIndex + direction
        guard ShareTemplate.allCases.indices.contains(nextIndex) else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedTemplate = ShareTemplate.allCases[nextIndex]
        }
    }

    private func showTemplateToast(for template: ShareTemplate) {
        let text = template.title(appLanguage)
        withAnimation(.easeOut(duration: 0.18)) {
            templateToastText = text
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            if templateToastText == text {
                withAnimation(.easeIn(duration: 0.18)) {
                    templateToastText = nil
                }
            }
        }
    }

    private func pruneUnavailableMetrics() {
        visibleMetrics = visibleMetrics.filterSet { $0.value(from: record) != nil }
    }

    private func removePhoto() {
        selectedPhotoItem = nil
        selectedPhotoImage = nil
        backgroundMode = backgroundMode == .transparent ? .transparent : .white
        photoTransform = CanvasTransform(scale: 1.0)
        photoOpacity = 0.9
        photoBlur = 0
        photoBrightness = 0
        photoContrast = 1.0
        if selectedLayer == .photo {
            selectedLayer = hasRenderableRoute ? .route : nil
        }
    }

    private var photoAdjustmentBinding: Binding<Double> {
        switch selectedPhotoAdjustment {
        case .scale:
            return Binding(
                get: { Double(photoTransform.scale) },
                set: { newValue in
                    photoTransform.scale = CGFloat(newValue)
                    photoTransform.clamp(scale: 0.6...3.2)
                }
            )
        case .positionX:
            return Binding(
                get: { Double(photoTransform.offset.width) },
                set: { newValue in
                    photoTransform.offset.width = CGFloat(newValue)
                }
            )
        case .positionY:
            return Binding(
                get: { Double(photoTransform.offset.height) },
                set: { newValue in
                    photoTransform.offset.height = CGFloat(newValue)
                }
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
            return 0.6...3.2
        case .positionX:
            return Double(-canvasSize.width * 0.28)...Double(canvasSize.width * 0.28)
        case .positionY:
            return Double(-canvasSize.height * 0.24)...Double(canvasSize.height * 0.24)
        case .opacity:
            return 0.15...1.0
        case .blur:
            return 0...16
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

        let maxWidth = rect.width * 0.86
        let maxHeight = rect.height * 0.86
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

        if points.count <= 4 {
            path.addLines(Array(points.dropFirst()))
            return path
        }

        guard points.count > 4 else { return path }

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

    private var selectedMetricKeysForPost: [RunShareMetricKey] {
        ShareMetricToggle.allCases.compactMap { metric in
            guard visibleMetrics.contains(metric) else { return nil }
            return metric.feedMetricKey
        }
    }

    private var resolvedHeadline: String {
        let weekday = RunPresentationFormatter.shortWeekdayString(from: record.startDate, appLanguage: appLanguage)
        if let heroMetricText {
            return "\(weekday) \(heroMetricText)"
        }
        return "\(weekday) \(record.formattedDistance)"
    }

    private var resolvedFeedBody: String {
        activeMetricTexts.map(\.1).joined(separator: " · ")
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhotoImage = image
        if backgroundMode == .white {
            backgroundMode = .fullPhoto
        }
        selectedControlPanel = .photo
        selectedLayer = .photo
    }

    @MainActor
    private func renderedCardData() -> Data? {
        let renderer = ImageRenderer(content: canvasContent(size: canvasSize, forExport: true))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = backgroundMode != .transparent
        return renderer.uiImage?.pngData()
    }

    @MainActor
    private func shareCard() {
        guard let data = renderedCardData() else { return }

        if let storyURL = URL(string: "instagram-stories://share"),
           UIApplication.shared.canOpenURL(storyURL) {
            UIPasteboard.general.setItems(
                [[
                    "com.instagram.sharedSticker.stickerImage": data,
                    "com.instagram.sharedSticker.backgroundTopColor": storyBackgroundHex,
                    "com.instagram.sharedSticker.backgroundBottomColor": storyBackgroundHex
                ]],
                options: [.expirationDate: Date().addingTimeInterval(300)]
            )
            UIApplication.shared.open(storyURL)
            return
        }

        guard let url = temporaryShareURL(from: data) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topViewController()?.present(activityVC, animated: true)
    }

    private var storyBackgroundHex: String {
        switch backgroundMode {
        case .white, .overlayPhoto:
            return "#F6F5F2"
        case .fullPhoto, .transparent:
            return "#000000"
        }
    }

    private func temporaryShareURL(from data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeamChaser-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
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

    @MainActor
    private func postToCommunity() async {
        guard let userId = backendService.userId else {
            statusText = appLanguage.text("로그인 후 등록할 수 있어요.", "Sign in to post.")
            statusTint = RBColor.danger
            return
        }

        let author = backendService.currentUser
        isPosting = true
        defer { isPosting = false }

        do {
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
                photoURL: nil,
                likedUserIds: [],
                comments: [],
                type: RunnerPost.PostType.runResult.firestoreValue,
                createdAt: Date()
            )

            try await backendService.createFeedPost(post)
            statusText = appLanguage.text("피드에 등록했습니다.", "Posted to feed.")
            statusTint = RBColor.success
        } catch {
            statusText = appLanguage.text("등록에 실패했습니다: \(error.localizedDescription)", "Couldn't post: \(error.localizedDescription)")
            statusTint = RBColor.danger
        }
    }
}

private extension Set {
    func filterSet(_ isIncluded: (Element) -> Bool) -> Set<Element> {
        Set(filter(isIncluded))
    }
}
