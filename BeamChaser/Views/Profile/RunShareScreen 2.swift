import SwiftUI
import UIKit
import PhotosUI

let sharePrimaryColor = Color(red: 1.0, green: 106.0 / 255.0, blue: 0)
let shareCardExportSize = CGSize(width: 1080, height: 1350)
let shareRouteLineWidth: CGFloat = 5

struct RunShareScreen: View {
    let record: RunRecord

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var selectedTab: ShareEditTab = .metrics
    @State private var selectedMetrics: [ShareMetricOption]
    @State private var selectedStyle: ShareVisualStyle = .light
    @State private var backgroundOption: ShareBackgroundOption = .white
    @State private var showBackgroundEditor = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var sharePayload: ShareSheetPayload?
    @State private var statusText: String?
    @State private var statusColor: Color = .red

    init(record: RunRecord) {
        self.record = record
        _selectedMetrics = State(initialValue: ShareMetricOption.defaultSelection(for: record))
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var availableMetrics: [ShareMetricOption] {
        ShareMetricOption.allCases.filter { $0.display(from: record) != nil }
    }

    private var primaryMetric: ShareMetricDisplay? {
        guard let metric = selectedMetrics.first else { return nil }
        return metric.display(from: record)
    }

    private var secondaryMetric: ShareMetricDisplay? {
        guard selectedMetrics.count > 1 else { return nil }
        return selectedMetrics[1].display(from: record)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let containerHeight = geometry.size.height
                let previewHeight = min(max(containerHeight * 0.42, 250), 440)

                VStack(spacing: 16) {
                    headerBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    previewSection(height: previewHeight)
                        .padding(.horizontal, 16)

                    editPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(red: 0.96, green: 0.96, blue: 0.95).ignoresSafeArea())
            }
            .navigationDestination(isPresented: $showBackgroundEditor) {
                BackgroundEditScreen(
                    appLanguage: appLanguage,
                    backgroundOption: $backgroundOption,
                    selectedPhotoItem: $selectedPhotoItem,
                    selectedPhotoImage: $selectedPhotoImage
                )
            }
            .sheet(item: $sharePayload) { payload in
                ActivityShareSheet(activityItems: [payload.image])
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    await loadPhoto(from: newValue)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showBackgroundEditor = true
            } label: {
                Text(appLanguage.text("배경", "Background"))
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(Color.black.opacity(0.76))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                sharePreview()
            } label: {
                Text(appLanguage.text("공유", "Share"))
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(sharePrimaryColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func previewSection(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let previewWidth = min(geometry.size.width, geometry.size.height * 4.0 / 5.0)
                let previewHeight = previewWidth * 5.0 / 4.0

                sharePreviewCard(size: CGSize(width: previewWidth, height: previewHeight), isExport: false)
                    .frame(width: previewWidth, height: previewHeight)
                    .shadow(color: Color.black.opacity(0.12), radius: 24, y: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: height)

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(statusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .lineLimit(2)
            }
        }
    }

    private var editPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(ShareEditTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title(appLanguage))
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .default))
                            .foregroundStyle(selectedTab == tab ? .white : Color.black.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(selectedTab == tab ? sharePrimaryColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.05))
            .clipShape(Capsule())
            .padding(16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .metrics:
                        metricsTab
                    case .style:
                        styleTab
                    case .photo:
                        photoTab
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var metricsTab: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(ShareMetricOption.allCases) { metric in
                let isSelected = selectedMetrics.contains(metric)
                let isEnabled = metric.display(from: record) != nil

                Button {
                    toggleMetric(metric)
                } label: {
                    Text(metric.title(appLanguage))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .default))
                        .foregroundStyle(isSelected ? .white : Color.black.opacity(isEnabled ? 0.76 : 0.26))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSelected ? sharePrimaryColor : Color.black.opacity(0.04))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
    }

    private var styleTab: some View {
        VStack(spacing: 10) {
            ForEach(ShareVisualStyle.allCases) { style in
                Button {
                    selectedStyle = style
                } label: {
                    HStack(spacing: 12) {
                        styleSwatch(for: style)

                        Text(style.title(appLanguage))
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(Color.black.opacity(0.78))

                        Spacer()

                        if selectedStyle == style {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(sharePrimaryColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                actionRow(title: appLanguage.text("사진 변경", "Change Photo"), symbol: "photo")
            }
            .buttonStyle(.plain)

            Button {
                removePhoto()
            } label: {
                actionRow(title: appLanguage.text("사진 제거", "Remove Photo"), symbol: "trash")
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotoImage == nil)
            .opacity(selectedPhotoImage == nil ? 0.45 : 1)

            if let selectedPhotoImage {
                Image(uiImage: selectedPhotoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func actionRow(title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(sharePrimaryColor)
                .frame(width: 30, height: 30)
                .background(sharePrimaryColor.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(Color.black.opacity(0.78))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.32))
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func styleSwatch(for style: ShareVisualStyle) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(style.swatchGradient)
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
    }

    private func toggleMetric(_ metric: ShareMetricOption) {
        guard metric.display(from: record) != nil else { return }

        if let index = selectedMetrics.firstIndex(of: metric) {
            guard selectedMetrics.count > 1 else { return }
            selectedMetrics.remove(at: index)
            return
        }

        if selectedMetrics.count == 2 {
            selectedMetrics.removeLast()
        }
        selectedMetrics.append(metric)
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhotoImage = image
        if backgroundOption == .white {
            backgroundOption = .photo
        }
    }

    private func removePhoto() {
        selectedPhotoItem = nil
        selectedPhotoImage = nil
        if backgroundOption == .photo {
            backgroundOption = .white
        }
    }

    @MainActor
    private func sharePreview() {
        guard let image = renderExportImage() else {
            statusText = appLanguage.text("공유 이미지를 만들 수 없어요.", "Could not create share image.")
            statusColor = .red
            return
        }

        statusText = nil
        sharePayload = ShareSheetPayload(image: image)
    }

    @MainActor
    private func renderExportImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: sharePreviewCard(size: shareCardExportSize, isExport: true)
                .frame(width: shareCardExportSize.width, height: shareCardExportSize.height)
        )
        renderer.scale = 1
        renderer.isOpaque = backgroundOption != .transparent
        return renderer.uiImage
    }

    private func sharePreviewCard(size: CGSize, isExport: Bool) -> some View {
        let routeFrame = CGRect(
            x: size.width * 0.10,
            y: size.height * 0.18,
            width: size.width * 0.80,
            height: size.height * 0.46
        )
        let foreground = foregroundColor
        let secondary = secondaryColor

        return ZStack(alignment: .topLeading) {
            previewBackground(size: size, isExport: isExport)

            routeGraphic(frame: routeFrame)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(sharePrimaryColor)
                        .frame(width: 8, height: 8)
                    Text("BEAMCHASER")
                        .font(.system(size: size.width * 0.032, weight: .bold, design: .default))
                        .foregroundStyle(foreground)
                        .tracking(1)
                }

                Spacer()

                VStack(alignment: .leading, spacing: size.height * 0.02) {
                    if let primaryMetric {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(primaryMetric.label(appLanguage))
                                .font(.system(size: size.width * 0.042, weight: .medium, design: .default))
                                .foregroundStyle(secondary)

                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(primaryMetric.main)
                                    .font(.system(size: size.width * 0.15, weight: .bold, design: .default))
                                    .foregroundStyle(foreground)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)

                                if let unit = primaryMetric.unit {
                                    Text(unit)
                                        .font(.system(size: size.width * 0.05, weight: .medium, design: .default))
                                        .foregroundStyle(secondary)
                                }
                            }
                        }
                    }

                    if let secondaryMetric {
                        HStack(spacing: 8) {
                            Text(secondaryMetric.label(appLanguage))
                                .font(.system(size: size.width * 0.04, weight: .medium, design: .default))
                                .foregroundStyle(secondary)
                            Text(secondaryMetric.inlineValue)
                                .font(.system(size: size.width * 0.05, weight: .bold, design: .default))
                                .foregroundStyle(foreground)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
            }
            .padding(.horizontal, size.width * 0.08)
            .padding(.vertical, size.height * 0.07)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: isExport ? 0 : 28, style: .continuous))
        .overlay {
            if !isExport {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(backgroundOption == .transparent ? 0.08 : 0.04), lineWidth: 1)
            }
        }
    }

    private func previewBackground(size: CGSize, isExport: Bool) -> some View {
        ZStack {
            switch backgroundOption {
            case .white:
                Color.white
            case .photo:
                photoBackground(size: size)
            case .gradient:
                LinearGradient(
                    colors: [sharePrimaryColor, Color.black.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .transparent:
                if isExport {
                    Color.clear
                } else {
                    checkerboardBackground
                }
            }

            styleOverlay
        }
    }

    private func photoBackground(size: CGSize) -> some View {
        Group {
            if let selectedPhotoImage {
                Image(uiImage: selectedPhotoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.92, blue: 0.90), Color(red: 0.82, green: 0.82, blue: 0.80)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var styleOverlay: some View {
        Group {
            switch selectedStyle {
            case .light:
                Color.white.opacity(backgroundOption == .photo ? 0.12 : 0)
            case .dark:
                Color.black.opacity(backgroundOption == .transparent ? 0.12 : 0.28)
            case .gradient:
                LinearGradient(
                    colors: [sharePrimaryColor.opacity(0.20), Color.black.opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .minimal:
                Color.clear
            case .routeHighlight:
                LinearGradient(
                    colors: [Color.white.opacity(0.02), sharePrimaryColor.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var foregroundColor: Color {
        switch selectedStyle {
        case .dark, .gradient:
            return .white
        case .minimal:
            return backgroundOption == .gradient ? .white : .black
        case .light, .routeHighlight:
            return backgroundOption == .gradient ? .white : .black
        }
    }

    private var secondaryColor: Color {
        switch selectedStyle {
        case .dark, .gradient:
            return Color.white.opacity(0.76)
        case .minimal:
            return backgroundOption == .gradient ? Color.white.opacity(0.72) : Color.black.opacity(0.52)
        case .light, .routeHighlight:
            return backgroundOption == .gradient ? Color.white.opacity(0.76) : Color.black.opacity(0.58)
        }
    }

    private var routeColors: [Color] {
        switch selectedStyle {
        case .light:
            return [sharePrimaryColor, sharePrimaryColor.opacity(0.82)]
        case .dark:
            return [sharePrimaryColor.opacity(0.92), Color.white.opacity(0.92)]
        case .gradient:
            return [Color(red: 1.0, green: 0.52, blue: 0.12), sharePrimaryColor, Color(red: 0.86, green: 0.14, blue: 0.08)]
        case .minimal:
            return backgroundOption == .gradient ? [.white, .white.opacity(0.82)] : [.black, .black.opacity(0.82)]
        case .routeHighlight:
            return [Color(red: 1.0, green: 0.74, blue: 0.20), sharePrimaryColor, Color(red: 0.86, green: 0.14, blue: 0.08)]
        }
    }

    private var routeGlowOpacity: Double {
        switch selectedStyle {
        case .routeHighlight:
            return 0.34
        case .gradient:
            return 0.24
        case .dark:
            return 0.22
        case .light:
            return 0.12
        case .minimal:
            return 0.04
        }
    }

    private func routeGraphic(frame: CGRect) -> some View {
        let points = previewRoutePoints(in: CGRect(origin: .zero, size: frame.size).insetBy(dx: 10, dy: 10))
        let path = smoothedPath(points)

        return ZStack {
            path
                .stroke(
                    LinearGradient(colors: routeColors.map { $0.opacity(routeGlowOpacity) }, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: shareRouteLineWidth + 6, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: selectedStyle == .minimal ? 0 : 6)

            path
                .stroke(
                    LinearGradient(colors: routeColors, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: shareRouteLineWidth, lineCap: .round, lineJoin: .round)
                )

            if let start = points.first {
                Circle()
                    .fill(Color.black)
                    .frame(width: 14, height: 14)
                    .position(start)
            }

            if let end = points.last {
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(Color.red, lineWidth: 4)
                    )
                    .position(end)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }

    private func previewRoutePoints(in rect: CGRect) -> [CGPoint] {
        let actualPoints = normalizedRoutePoints(in: rect)
        if !actualPoints.isEmpty {
            return actualPoints
        }

        return [
            CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.18),
            CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.62),
            CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.48),
            CGPoint(x: rect.minX + rect.width * 0.53, y: rect.maxY - rect.height * 0.78),
            CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.36),
            CGPoint(x: rect.minX + rect.width * 0.88, y: rect.maxY - rect.height * 0.14)
        ]
    }

    private func normalizedRoutePoints(in rect: CGRect) -> [CGPoint] {
        guard record.routePoints.count >= 2, record.totalDistanceMeters > 5 else { return [] }

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

    private func smoothedPath(_ points: [CGPoint]) -> Path {
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

    private var checkerboardBackground: some View {
        GeometryReader { geometry in
            let columns = 6
            let rows = 8
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ZStack {
                Color.white
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? Color.black.opacity(0.05) : Color.clear)
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: cellWidth * (CGFloat(column) + 0.5),
                                y: cellHeight * (CGFloat(row) + 0.5)
                            )
                    }
                }
            }
        }
    }
}

enum ShareEditTab: String, CaseIterable, Identifiable {
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

enum ShareMetricOption: String, CaseIterable, Identifiable {
    case time
    case distance
    case pace
    case heartRate
    case cadence
    case calories
    case elevation

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .time:
            return appLanguage.text("시간", "Time")
        case .distance:
            return appLanguage.text("거리", "Distance")
        case .pace:
            return appLanguage.text("페이스", "Pace")
        case .heartRate:
            return appLanguage.text("심박수", "Heart Rate")
        case .cadence:
            return appLanguage.text("케이던스", "Cadence")
        case .calories:
            return appLanguage.text("칼로리", "Calories")
        case .elevation:
            return appLanguage.text("고도", "Elevation")
        }
    }

    func display(from record: RunRecord) -> ShareMetricDisplay? {
        switch self {
        case .time:
            guard record.elapsedSeconds > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: record.formattedDuration, unit: nil)
        case .distance:
            guard record.distanceKm > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: String(format: "%.2f", record.distanceKm), unit: "km")
        case .pace:
            guard record.averagePaceSecondsPerKm > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: record.formattedPace, unit: "/km")
        case .heartRate:
            guard let value = record.averageHeartRateBpm, value > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: "\(value)", unit: "bpm")
        case .cadence:
            guard let value = record.averageCadenceSpm, value > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: "\(value)", unit: "spm")
        case .calories:
            let value = Int(record.estimatedCaloriesKcal.rounded())
            guard value > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: "\(value)", unit: "kcal")
        case .elevation:
            let value = Int(record.elevationGainMeters.rounded())
            guard value > 0 else { return nil }
            return ShareMetricDisplay(metric: self, main: "\(value)", unit: "m")
        }
    }

    static func defaultSelection(for record: RunRecord) -> [ShareMetricOption] {
        let priority: [ShareMetricOption] = [.time, .calories, .distance, .pace, .heartRate, .cadence, .elevation]
        let available = priority.filter { $0.display(from: record) != nil }
        return Array(available.prefix(2)).nonEmpty(or: [.time])
    }
}

struct ShareMetricDisplay {
    let metric: ShareMetricOption
    let main: String
    let unit: String?

    func label(_ appLanguage: AppLanguage) -> String {
        metric.title(appLanguage)
    }

    var inlineValue: String {
        if let unit {
            return "\(main) \(unit)"
        }
        return main
    }
}

enum ShareVisualStyle: String, CaseIterable, Identifiable {
    case light
    case dark
    case gradient
    case minimal
    case routeHighlight

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .light:
            return appLanguage.text("라이트", "Light")
        case .dark:
            return appLanguage.text("다크", "Dark")
        case .gradient:
            return appLanguage.text("그라데이션", "Gradient")
        case .minimal:
            return appLanguage.text("미니멀", "Minimal")
        case .routeHighlight:
            return appLanguage.text("경로 강조", "Route Highlight")
        }
    }

    var swatchGradient: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(colors: [Color.white, Color(red: 0.94, green: 0.94, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dark:
            return LinearGradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradient:
            return LinearGradient(colors: [sharePrimaryColor, Color.black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .minimal:
            return LinearGradient(colors: [Color.white, Color.black.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .routeHighlight:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.8, blue: 0.2), sharePrimaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

enum ShareBackgroundOption: String, CaseIterable, Identifiable {
    case white
    case photo
    case gradient
    case transparent

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .white:
            return appLanguage.text("화이트", "White")
        case .photo:
            return appLanguage.text("사진", "Photo")
        case .gradient:
            return appLanguage.text("그라데이션", "Gradient")
        case .transparent:
            return appLanguage.text("투명", "Transparent")
        }
    }
}

private struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension Array {
    func nonEmpty(or fallback: @autoclosure () -> [Element]) -> [Element] {
        isEmpty ? fallback() : self
    }
}
