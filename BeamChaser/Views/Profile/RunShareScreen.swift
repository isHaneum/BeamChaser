import SwiftUI
import UIKit
import PhotosUI
import MapKit

let sharePrimaryColor = ColorTokens.Share.primary
let sharePrimaryDeepColor = ColorTokens.Share.primaryDeep
let sharePrimaryMistColor = ColorTokens.Share.primaryMist
let shareCardExportSize = ComponentTokens.ShareEditor.exportCanvasSize
let shareRouteLineWidth = ComponentTokens.ShareEditor.routeLineWidth

private struct ShareEditorLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let compact: Bool
    let contentWidth: CGFloat
    let headerTopPadding: CGFloat
    let headerHeight: CGFloat
    let panelHeight: CGFloat
    let previewRegionHeight: CGFloat
    let previewSize: CGSize

    init(size: CGSize, safeAreaInsets: EdgeInsets, previewAspectRatio: CGFloat) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        compact = size.height < ComponentTokens.ShareEditor.compactHeightThreshold
            || size.width < ComponentTokens.ShareEditor.compactWidthThreshold
        contentWidth = LayoutTokens.contentWidth(for: size.width)
        headerTopPadding = safeAreaInsets.top + ComponentTokens.ShareEditor.headerTopGap
        headerHeight = headerTopPadding
            + ComponentTokens.ShareEditor.headerButtonHeight
            + ComponentTokens.ShareEditor.headerBottomPadding

        let panelRatio = compact
            ? ComponentTokens.ShareEditor.compactPanelRatio
            : ComponentTokens.ShareEditor.regularPanelRatio
        let idealPanelHeight = min(
            max(size.height * panelRatio, ComponentTokens.ShareEditor.panelMinHeight),
            ComponentTokens.ShareEditor.panelMaxHeight
        )
        let availableBelowHeader = max(0, size.height - headerHeight - safeAreaInsets.bottom)
        let maxPanelHeightLeavingPreview = max(0, availableBelowHeader - ComponentTokens.ShareEditor.previewMinHeight)
        if maxPanelHeightLeavingPreview >= ComponentTokens.ShareEditor.panelMinHeight {
            panelHeight = min(idealPanelHeight, maxPanelHeightLeavingPreview)
        } else {
            panelHeight = min(idealPanelHeight, availableBelowHeader * 0.62)
        }

        previewRegionHeight = max(0, availableBelowHeader - panelHeight)
        let previewMaxWidth = contentWidth
        let fittedHeight = min(
            max(0, previewRegionHeight - ComponentTokens.ShareEditor.previewPanelGap),
            previewMaxWidth * previewAspectRatio
        )
        let resolvedHeight = max(1, fittedHeight)
        let resolvedWidth = min(previewMaxWidth, resolvedHeight / max(previewAspectRatio, 0.01))
        previewSize = CGSize(width: resolvedWidth, height: resolvedWidth * previewAspectRatio)
    }
}

private struct ShareEditorView<Header: View, Preview: View, Panel: View>: View {
    let layout: ShareEditorLayout
    @ViewBuilder let header: () -> Header
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        ZStack(alignment: .top) {
            ColorTokens.Share.background
                .ignoresSafeArea()

            header()
                .frame(width: layout.contentWidth)
                .padding(.top, layout.headerTopPadding)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
                .zIndex(2)

            preview()
                .frame(width: layout.contentWidth, height: layout.previewRegionHeight, alignment: .center)
                .padding(.top, layout.headerHeight)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
                .zIndex(1)

            VStack {
                Spacer(minLength: 0)
                panel()
                    .frame(width: layout.contentWidth, height: layout.panelHeight, alignment: .top)
                    .padding(.bottom, layout.safeAreaInsets.bottom)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .zIndex(3)
        }
    }
}

private struct SharePreviewCard<Content: View>: View {
    let size: CGSize
    let isExport: Bool
    var borderOpacity: Double = 0.88
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: isExport ? 0 : RunSurfaceToken.cardRadius, style: .continuous))
            .overlay {
                if !isExport {
                    ZStack {
                        RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                            .stroke(Color.white.opacity(borderOpacity), lineWidth: 2)

                        RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                            .inset(by: 1)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
                }
            }
    }
}

private struct ShareEditorPanel<Tabs: View, Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let tabs: () -> Tabs
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(RBColor.textTertiary.opacity(0.5))
                .frame(
                    width: ComponentTokens.ShareEditor.panelGrabberWidth,
                    height: ComponentTokens.ShareEditor.panelGrabberHeight
                )
                .padding(.top, 10)

            tabs()

            ScrollView(showsIndicators: false) {
                content()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
            .frame(maxHeight: max(0, maxHeight - 68))
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)
        .background(RunSurfaceToken.lightPanelBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RunSurfaceToken.cardRadius, style: .continuous)
                .stroke(RBColor.divider.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }
}

struct RunShareScreen: View {
    let record: RunRecord

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("appColorTheme") private var appColorThemeRaw: String = AppColorTheme.beam.rawValue

    @State private var selectedTab: ShareEditTab = .data
    @State private var selectedMetrics: [ShareMetricOption]
    @State private var selectedStyle: ShareVisualStyle = .light
    @State private var selectedCanvasRatio: ShareCanvasRatio = .post
    @State private var backgroundOption: ShareBackgroundOption = .map
    @State private var showBackgroundEditor = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var selectedMetricForPlacement: ShareMetricOption?
    @State private var metricPlacements: [ShareMetricOption: CGPoint] = [:]
    @State private var metricDragOrigins: [ShareMetricOption: CGPoint] = [:]
    @State private var metricScales: [ShareMetricOption: CGFloat] = [:]
    @State private var metricScaleOrigins: [ShareMetricOption: CGFloat] = [:]
    @State private var photoScale: CGFloat = 1
    @State private var photoScaleOrigin: CGFloat = 1
    @State private var photoOffset: CGSize = .zero
    @State private var photoOffsetOrigin: CGSize = .zero
    @State private var mapSnapshot: ShareMapSnapshot?
    @State private var sharePayload: ShareSheetPayload?
    @State private var statusText: String?
    @State private var statusColor: Color = .red

    init(record: RunRecord) {
        self.record = record
        let defaultMetrics = ShareMetricOption.defaultSelection(for: record)
        _selectedMetrics = State(initialValue: defaultMetrics)
        _selectedMetricForPlacement = State(initialValue: defaultMetrics.first)
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var shareAccent: Color {
        currentSharePalette.primary
    }

    private var shareAccentDeep: Color {
        currentSharePalette.deep
    }

    private var shareAccentMist: Color {
        currentSharePalette.mist
    }

    private var currentSharePalette: ShareRoutePalette {
        ShareRoutePalette(rawValue: appColorThemeRaw) ?? .beam
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

    private var selectedMetricDisplays: [ShareMetricDisplay] {
        selectedMetrics.compactMap { $0.display(from: record) }
    }

    private var exportCanvasSize: CGSize {
        selectedCanvasRatio.exportSize
    }

    private var previewAspectRatio: CGFloat {
        selectedCanvasRatio.exportSize.height / selectedCanvasRatio.exportSize.width
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let editorLayout = ShareEditorLayout(
                    size: geometry.size,
                    safeAreaInsets: geometry.safeAreaInsets,
                    previewAspectRatio: previewAspectRatio
                )

                ShareEditorView(layout: editorLayout) {
                    headerBar
                } preview: {
                    previewSection(cardSize: editorLayout.previewSize)
                } panel: {
                    editPanel(maxHeight: editorLayout.panelHeight)
                }
            }
            .navigationDestination(isPresented: $showBackgroundEditor) {
                BackgroundEditScreen(
                    appLanguage: appLanguage,
                    backgroundOption: $backgroundOption,
                    selectedPhotoItem: $selectedPhotoItem,
                    selectedPhotoImage: $selectedPhotoImage,
                    onApply: {
                        sharePreview()
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sharePayload) { payload in
                ActivityShareSheet(activityItems: [payload.image])
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    await loadPhoto(from: newValue)
                }
            }
            .task(id: mapSnapshotRequestKey) {
                await refreshMapSnapshotIfNeeded()
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(RunSurfaceToken.lightPanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
                    .accessibilityLabel(appLanguage.text("닫기", "Close"))

            Spacer()

            Button {
                showBackgroundEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(appLanguage.text("배경", "BG"))
                        .font(RBFont.label(12))
                }
                .foregroundStyle(RBColor.textPrimary)
                .frame(width: 64, height: 48)
                .background(RunSurfaceToken.lightPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            }
            .buttonStyle(.plain)

            Button {
                sharePreview()
            } label: {
                Text(appLanguage.text("내보내기", "Export"))
                    .font(RBFont.label(15))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 48)
                    .background(shareAccent)
                    .clipShape(RoundedRectangle(cornerRadius: RunSurfaceToken.pillRadius, style: .continuous))
                    .shadow(color: shareAccent.opacity(0.24), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
        }
    }

    private func previewSection(cardSize: CGSize) -> some View {
        VStack(spacing: 16) {
            sharePreviewCard(size: cardSize, isExport: false)
                .frame(width: cardSize.width, height: cardSize.height)
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 12)
                .frame(maxWidth: .infinity, alignment: .center)

            if backgroundOption == .photo || !selectedMetricDisplays.isEmpty {
                Text(appLanguage.text("카드 편집 활성화", "Card editing active"))
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            if let statusText {
                Text(statusText)
                    .font(RBFont.caption(12))
                    .foregroundStyle(statusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func previewHintChip(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(RBFont.caption(11))
        }
        .foregroundStyle(RBColor.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RBColor.cardBg.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(RBColor.divider.opacity(0.76), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func editPanel(maxHeight: CGFloat) -> some View {
        ShareEditorPanel(maxHeight: maxHeight) {
            HStack(spacing: 4) {
                ForEach(ShareEditTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.title(appLanguage))
                                .font(RBFont.caption(11))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                            .foregroundStyle(selectedTab == tab ? .white : RBColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(selectedTab == tab ? shareAccent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title(appLanguage))
                }
            }
            .padding(4)
            .background(RBColor.cardBgLight.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedTab {
                case .layout:
                    layoutTab
                case .data:
                    dataTab
                case .style:
                    styleTab
                case .photo:
                    photoTab
                }
            }
        }
    }

    private var layoutTab: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(ShareLayoutPreset.allCases) { preset in
                let isSelected = isLayoutPresetSelected(preset)
                Button {
                    applyLayoutPreset(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: preset.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : shareAccent)
                        Text(preset.title(appLanguage))
                            .font(RBFont.label(13))
                            .foregroundStyle(isSelected ? .white : RBColor.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 64)
                    .padding(.horizontal, 14)
                    .background(isSelected ? shareAccent : RBColor.cardBgLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                            .stroke(isSelected ? shareAccent : RBColor.divider.opacity(0.8), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(ShareMetricOption.allCases) { metric in
                    let isSelected = selectedMetrics.contains(metric)
                    let isEnabled = metric.display(from: record) != nil
                    let isFocused = selectedMetricForPlacement == metric

                    Button {
                        toggleMetric(metric)
                    } label: {
                        HStack(spacing: 6) {
                            Text(metric.title(appLanguage))
                                .font(RBFont.label(12))
                                .lineLimit(1)
                            if isFocused && isSelected {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                            .foregroundStyle(isSelected ? .white : (isEnabled ? RBColor.textPrimary : RBColor.textDisabled))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(isSelected ? shareAccent : RBColor.cardBgLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? (isFocused ? Color.white.opacity(0.78) : shareAccent)
                                            : RBColor.divider.opacity(isEnabled ? 0.8 : 0.45),
                                        lineWidth: isFocused && isSelected ? 1.2 : 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
                }
            }

            if let metric = activeMetricForPlacement {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(metric.title(appLanguage))
                            .font(RBFont.label(14))
                            .foregroundStyle(RBColor.textPrimary)

                        Spacer()

                        if selectedMetrics.count > 1 {
                            Button(appLanguage.text("숨기기", "Hide")) {
                                selectedMetrics.removeAll { $0 == metric }
                                if selectedMetricForPlacement == metric {
                                    selectedMetricForPlacement = selectedMetrics.first
                                }
                            }
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                        }

                        Button(appLanguage.text("리셋", "Reset")) {
                            resetMetricTransform(metric)
                        }
                        .font(RBFont.caption(11))
                        .foregroundStyle(shareAccent)
                    }

                    HStack(spacing: 8) {
                        metricInspectorButton(
                            title: appLanguage.text("작게", "Small"),
                            isSelected: metricScale(for: metric) < 0.95
                        ) {
                            setMetricScale(0.84, for: metric)
                        }

                        metricInspectorButton(
                            title: appLanguage.text("기본", "Default"),
                            isSelected: abs(metricScale(for: metric) - 1.0) < 0.08
                        ) {
                            setMetricScale(1.0, for: metric)
                        }

                        metricInspectorButton(
                            title: appLanguage.text("크게", "Large"),
                            isSelected: metricScale(for: metric) > 1.12
                        ) {
                            setMetricScale(1.24, for: metric)
                        }
                    }

                    HStack(spacing: 8) {
                        metricInspectorButton(title: appLanguage.text("상단", "Top")) {
                            snapMetric(metric, y: 0.30)
                        }

                        metricInspectorButton(title: appLanguage.text("중앙", "Center")) {
                            snapMetric(metric, y: 0.52)
                        }

                        metricInspectorButton(title: appLanguage.text("하단", "Bottom")) {
                            snapMetric(metric, y: 0.74)
                        }
                    }
                }
                .padding(12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RBColor.divider.opacity(0.8), lineWidth: 1)
                )
            }
        }
    }

    private func metricInspectorButton(title: String, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RBFont.label(12))
                .foregroundStyle(isSelected ? .white : RBColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isSelected ? shareAccent : RBColor.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? shareAccent : RBColor.divider.opacity(0.78), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var styleTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            styleSectionTitle(appLanguage.text("포맷", "Format"))

            HStack(spacing: 8) {
                ForEach(ShareCanvasRatio.allCases) { ratio in
                    Button {
                        selectedCanvasRatio = ratio
                    } label: {
                        Text(ratio.title(appLanguage))
                            .font(RBFont.label(12))
                            .foregroundStyle(selectedCanvasRatio == ratio ? .white : RBColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(selectedCanvasRatio == ratio ? shareAccent : RBColor.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selectedCanvasRatio == ratio ? shareAccent : RBColor.divider.opacity(0.8), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            styleSectionTitle(appLanguage.text("배경", "Background"))

            let backgroundOptions: [ShareBackgroundOption] = [.map, .photo, .white, .gradient, .transparent]

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(backgroundOptions) { option in
                        Button {
                            if option == .photo && selectedPhotoImage == nil {
                                selectedTab = .photo
                            } else {
                                backgroundOption = option
                            }
                        } label: {
                            HStack(spacing: 7) {
                                backgroundSwatch(for: option)
                                Text(option.title(appLanguage))
                                    .font(RBFont.label(12))
                                    .lineLimit(1)
                                if backgroundOption == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .foregroundStyle(backgroundOption == option ? .white : RBColor.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .background(backgroundOption == option ? shareAccent : RBColor.cardBgLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(backgroundOption == option ? shareAccent : RBColor.divider.opacity(0.8), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            styleSectionTitle(appLanguage.text("무드", "Mood"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShareVisualStyle.allCases) { style in
                        Button {
                            selectedStyle = style
                        } label: {
                            HStack(spacing: 7) {
                                styleSwatch(for: style)
                                    .frame(width: 26, height: 26)
                                Text(style.title(appLanguage))
                                    .font(RBFont.label(12))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selectedStyle == style ? .white : RBColor.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .background(selectedStyle == style ? shareAccent : RBColor.cardBgLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selectedStyle == style ? shareAccent : RBColor.divider.opacity(0.8), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
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
                resetPhotoTransform()
            } label: {
                actionRow(title: appLanguage.text("사진 위치 리셋", "Reset Photo Position"), symbol: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotoImage == nil)
            .opacity(selectedPhotoImage == nil ? 0.35 : 1)

            Button {
                removePhoto()
            } label: {
                actionRow(title: appLanguage.text("사진 제거", "Remove Photo"), symbol: "trash")
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotoImage == nil)
            .opacity(selectedPhotoImage == nil ? 0.35 : 1)

            if let selectedPhotoImage {
                Image(uiImage: selectedPhotoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
            }
        }
    }

    private func actionRow(title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(shareAccent)
                .frame(width: 30, height: 30)
                .background(shareAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RBColor.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
    }

    private func styleSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(RBFont.caption(10))
            .foregroundStyle(RBColor.textTertiary)
            .tracking(1.1)
            .padding(.top, 2)
    }

    private func backgroundSwatch(for option: ShareBackgroundOption) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(option.swatch)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(RBColor.divider.opacity(0.9), lineWidth: 1)
            )
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

    private func isLayoutPresetSelected(_ preset: ShareLayoutPreset) -> Bool {
        switch preset {
        case .routeOnly:
            return selectedStyle == .routeOnly
        case .routeStats:
            return selectedStyle == .light && backgroundOption == .map
        case .photoRoute:
            return selectedStyle == .dark && (backgroundOption == .photo || backgroundOption == .gradient)
        case .minimalStats:
            return selectedStyle == .minimal
        }
    }

    private func applyLayoutPreset(_ preset: ShareLayoutPreset) {
        switch preset {
        case .routeOnly:
            selectedStyle = .routeOnly
            backgroundOption = .white
        case .routeStats:
            selectedStyle = .light
            backgroundOption = .map
        case .photoRoute:
            selectedStyle = .dark
            backgroundOption = selectedPhotoImage == nil ? .gradient : .photo
        case .minimalStats:
            selectedStyle = .minimal
            backgroundOption = .white
        }
    }

    private func toggleMetric(_ metric: ShareMetricOption) {
        guard metric.display(from: record) != nil else { return }

        if selectedMetrics.contains(metric) {
            selectedMetricForPlacement = metric
            return
        }

        selectedMetrics.append(metric)
        selectedMetricForPlacement = metric
    }

    private var activeMetricForPlacement: ShareMetricOption? {
        if let selectedMetricForPlacement, selectedMetrics.contains(selectedMetricForPlacement) {
            return selectedMetricForPlacement
        }
        return selectedMetrics.first
    }

    private func metricContext(for metric: ShareMetricOption) -> (index: Int, count: Int) {
        let count = max(selectedMetrics.count, 1)
        let index = selectedMetrics.firstIndex(of: metric) ?? 0
        return (index, count)
    }

    private func currentMetricPosition(_ metric: ShareMetricOption) -> CGPoint {
        let context = metricContext(for: metric)
        return metricPosition(for: metric, index: context.index, count: context.count, size: exportCanvasSize)
    }

    private func metricScale(for metric: ShareMetricOption) -> CGFloat {
        min(max(metricScales[metric] ?? 1, 0.84), 1.45)
    }

    private func setMetricScale(_ scale: CGFloat, for metric: ShareMetricOption) {
        let clampedScale = min(max(scale, 0.84), 1.45)
        metricScales[metric] = clampedScale
        metricPlacements[metric] = clampedMetricPosition(currentMetricPosition(metric), scale: clampedScale)
    }

    private func snapMetric(_ metric: ShareMetricOption, x: CGFloat? = nil, y: CGFloat? = nil) {
        let current = currentMetricPosition(metric)
        metricPlacements[metric] = clampedMetricPosition(
            CGPoint(x: x ?? current.x, y: y ?? current.y),
            scale: metricScale(for: metric)
        )
    }

    private func resetMetricTransform(_ metric: ShareMetricOption) {
        metricPlacements[metric] = nil
        metricScales[metric] = nil
    }

    private var mapSnapshotRequestKey: String {
        [
            backgroundOption.rawValue,
            selectedCanvasRatio.rawValue,
            selectedStyle.rawValue,
            String(record.routePoints.count)
        ].joined(separator: "-")
    }

    @MainActor
    private func refreshMapSnapshotIfNeeded() async {
        guard backgroundOption == .map else { return }
        guard record.routePoints.count >= 1 else {
            mapSnapshot = nil
            return
        }

        mapSnapshot = await makeMapSnapshot(
            size: exportCanvasSize,
            useDarkTheme: selectedStyle == .dark || selectedStyle == .routeOnly || backgroundOption == .photo
        )
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhotoImage = image
        resetPhotoTransform()
        if backgroundOption == .white || backgroundOption == .map {
            backgroundOption = .photo
        }
    }

    private func removePhoto() {
        selectedPhotoItem = nil
        selectedPhotoImage = nil
        resetPhotoTransform()
        if backgroundOption == .photo {
            backgroundOption = .map
        }
    }

    private func resetPhotoTransform() {
        photoScale = 1
        photoScaleOrigin = 1
        photoOffset = .zero
        photoOffsetOrigin = .zero
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
            content: sharePreviewCard(size: exportCanvasSize, isExport: true)
                .frame(width: exportCanvasSize.width, height: exportCanvasSize.height)
        )
        renderer.scale = 1
        renderer.isOpaque = backgroundOption != .transparent
        return renderer.uiImage
    }

    private func sharePreviewCard(size: CGSize, isExport: Bool) -> some View {
        let routeFrame = routeFrame(for: size)
        let foreground = foregroundColor
        let secondary = secondaryColor
        let metricDisplays = selectedMetricDisplays

        return SharePreviewCard(
            size: size,
            isExport: isExport,
            borderOpacity: backgroundOption == .transparent ? 0.96 : 0.88
        ) {
            ZStack(alignment: .topLeading) {
                previewBackground(size: size, isExport: isExport)
                photoEditingLayer(size: size, isExport: isExport)

                routeGraphic(frame: routeFrame)

                if selectedStyle != .routeOnly {
                    shareCardHeader(size: size, foreground: foreground, secondary: secondary)
                        .padding(.horizontal, size.width * 0.08)
                        .padding(.top, size.height * 0.07)

                    metricStickerLayer(
                        metricDisplays,
                        size: size,
                        foreground: foreground,
                        secondary: secondary,
                        isExport: isExport
                    )
                }
            }
        }
    }

    private func routeFrame(for size: CGSize) -> CGRect {
        if backgroundOption == .map {
            return CGRect(
                x: size.width * 0.02,
                y: size.height * 0.02,
                width: size.width * 0.96,
                height: size.height * 0.96
            )
        }

        if selectedStyle == .routeOnly {
            return CGRect(
                x: size.width * 0.10,
                y: size.height * 0.12,
                width: size.width * 0.80,
                height: size.height * 0.74
            )
        }

        let isSquare = size.height / max(size.width, 1) < 1.12
        let topInset = size.height * (isSquare ? 0.22 : 0.20)
        let bottomInset = size.height * (isSquare ? 0.24 : 0.22)
        return CGRect(
            x: size.width * 0.10,
            y: topInset,
            width: size.width * 0.80,
            height: size.height - topInset - bottomInset
        )
    }

    private func shareCardHeader(size: CGSize, foreground: Color, secondary: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(shareAccent)
                        .frame(width: 8, height: 8)
                    Text("BEAMCHASER")
                        .font(AppFontPreset.current.titleFont(size: size.width * 0.032, weight: .bold))
                        .foregroundStyle(foreground)
                        .tracking(1)
                }

                Text(record.startDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(AppFontPreset.current.bodyFont(size: size.width * 0.028, weight: .medium))
                    .foregroundStyle(secondary)
            }

            Spacer()

            Text(shareStyleBadge)
                .font(AppFontPreset.current.bodyFont(size: size.width * 0.026, weight: .semibold))
                .foregroundStyle(secondary)
                .padding(.horizontal, size.width * 0.024)
                .frame(height: size.height * 0.042)
                .background(secondary.opacity(backgroundOption == .gradient ? 0.16 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func metricStickerLayer(
        _ metrics: [ShareMetricDisplay],
        size: CGSize,
        foreground: Color,
        secondary: Color,
        isExport: Bool
    ) -> some View {
        ZStack {
            ForEach(Array(metrics.enumerated()), id: \.element.metric) { index, metric in
                positionedMetricSticker(
                    metric,
                    index: index,
                    count: metrics.count,
                    size: size,
                    foreground: foreground,
                    secondary: secondary,
                    isExport: isExport
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func positionedMetricSticker(
        _ metric: ShareMetricDisplay,
        index: Int,
        count: Int,
        size: CGSize,
        foreground: Color,
        secondary: Color,
        isExport: Bool
    ) -> some View {
        let normalizedPosition = metricPosition(for: metric.metric, index: index, count: count, size: size)
        let scale = metricScale(for: metric.metric)
        let sticker = metricSticker(metric, size: size, foreground: foreground, secondary: secondary)
            .scaleEffect(scale)
            .position(
                x: normalizedPosition.x * size.width,
                y: normalizedPosition.y * size.height
            )

        if isExport {
            sticker
        } else {
            sticker
                .gesture(metricDragGesture(for: metric.metric, index: index, count: count, size: size))
                .simultaneousGesture(metricScaleGesture(for: metric.metric))
                .onTapGesture {
                    selectedMetricForPlacement = metric.metric
                }
                .onTapGesture(count: 2) {
                    resetMetricTransform(metric.metric)
                }
        }
    }

    private func metricSticker(
        _ metric: ShareMetricDisplay,
        size: CGSize,
        foreground: Color,
        secondary: Color
    ) -> some View {
        return VStack(alignment: .leading, spacing: size.width * 0.010) {
            Text(metric.label(appLanguage).uppercased())
                .font(AppFontPreset.current.bodyFont(size: size.width * 0.024, weight: .semibold))
                .foregroundStyle(secondary)
                .tracking(0.55)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: size.width * 0.010) {
                Text(metric.main)
                    .font(AppFontPreset.current.titleFont(size: size.width * 0.060, weight: .bold))
                    .foregroundStyle(foreground)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let unit = metric.unit {
                    Text(unit)
                        .font(AppFontPreset.current.bodyFont(size: size.width * 0.024, weight: .medium))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selectedMetricForPlacement == metric.metric ? Color.white.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selectedMetricForPlacement == metric.metric ? Color.white.opacity(0.54) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .shadow(
            color: selectedMetricForPlacement == metric.metric ? shareAccent.opacity(0.22) : Color.black.opacity(0.18),
            radius: selectedMetricForPlacement == metric.metric ? 12 : 8,
            y: 4
        )
    }

    private func metricPosition(for metric: ShareMetricOption, index: Int, count: Int, size: CGSize) -> CGPoint {
        if let placement = metricPlacements[metric] {
            return clampedMetricPosition(placement, scale: metricScale(for: metric))
        }
        return defaultMetricPosition(index: index, count: count, size: size)
    }

    private func defaultMetricPosition(index: Int, count: Int, size: CGSize) -> CGPoint {
        let isSquare = size.height / max(size.width, 1) < 1.12
        let columns = min(max(count, 1), 3)
        let column = index % columns
        let row = index / columns
        let xPositions: [[CGFloat]] = [
            [0.50],
            [0.32, 0.68],
            [0.20, 0.50, 0.80]
        ]
        let x = xPositions[columns - 1][column]
        let firstRowY: CGFloat = backgroundOption == .map
            ? (isSquare ? 0.28 : 0.24)
            : (isSquare ? 0.24 : 0.20)
        return clampedMetricPosition(CGPoint(x: x, y: firstRowY + CGFloat(row) * 0.118))
    }

    private func clampedMetricPosition(_ point: CGPoint, scale: CGFloat = 1) -> CGPoint {
        let scaleOffset = max(scale - 1, 0)
        let xInset = min(0.22, 0.14 + scaleOffset * 0.06)
        let yInset = min(0.28, 0.22 + scaleOffset * 0.05)

        return CGPoint(
            x: min(max(point.x, xInset), 1 - xInset),
            y: min(max(point.y, yInset), 0.88)
        )
    }

    private func metricDragGesture(for metric: ShareMetricOption, index: Int, count: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let origin = metricDragOrigins[metric] ?? metricPosition(for: metric, index: index, count: count, size: size)
                if metricDragOrigins[metric] == nil {
                    metricDragOrigins[metric] = origin
                }

                metricPlacements[metric] = clampedMetricPosition(
                    CGPoint(
                        x: origin.x + value.translation.width / max(size.width, 1),
                        y: origin.y + value.translation.height / max(size.height, 1)
                    ),
                    scale: metricScale(for: metric)
                )
            }
            .onEnded { _ in
                metricDragOrigins[metric] = nil
            }
    }

    private func metricScaleGesture(for metric: ShareMetricOption) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let origin = metricScaleOrigins[metric] ?? metricScale(for: metric)
                if metricScaleOrigins[metric] == nil {
                    metricScaleOrigins[metric] = origin
                }

                let updatedScale = min(max(origin * value, 0.84), 1.45)
                metricScales[metric] = updatedScale
                metricPlacements[metric] = clampedMetricPosition(currentMetricPosition(metric), scale: updatedScale)
            }
            .onEnded { _ in
                metricScaleOrigins[metric] = nil
            }
    }

    private func metricFooter(_ metrics: [ShareMetricDisplay], size: CGSize, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: size.height * 0.018) {
            if metrics.count <= 1, let metric = metrics.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.label(appLanguage).uppercased())
                        .font(.system(size: size.width * 0.030, weight: .semibold, design: .default))
                        .foregroundStyle(secondary)
                        .tracking(0.8)

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(metric.main)
                            .font(.system(size: size.width * 0.128, weight: .bold, design: .default))
                            .foregroundStyle(foreground)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if let unit = metric.unit {
                            Text(unit)
                                .font(.system(size: size.width * 0.040, weight: .medium, design: .default))
                                .foregroundStyle(secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: size.width * 0.038) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        if index > 0 {
                            Rectangle()
                                .fill(secondary.opacity(0.22))
                                .frame(width: 1)
                                .padding(.vertical, 6)
                        }

                        metricBlock(metric, size: size, foreground: foreground, secondary: secondary)
                    }
                }
            }
        }
        .padding(.horizontal, size.width * 0.032)
        .padding(.vertical, size.width * 0.026)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(metricFooterBackground)
        .overlay(
            RoundedRectangle(cornerRadius: size.width * 0.030, style: .continuous)
                .stroke(secondary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: size.width * 0.030, style: .continuous))
    }

    private func metricBlock(_ metric: ShareMetricDisplay, size: CGSize, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label(appLanguage).uppercased())
                .font(.system(size: size.width * 0.025, weight: .semibold, design: .default))
                .foregroundStyle(secondary)
                .tracking(0.6)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metric.main)
                    .font(.system(size: size.width * 0.060, weight: .bold, design: .default))
                    .foregroundStyle(foreground)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let unit = metric.unit {
                    Text(unit)
                        .font(.system(size: size.width * 0.028, weight: .medium, design: .default))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewBackground(size: CGSize, isExport: Bool) -> some View {
        ZStack {
            switch backgroundOption {
            case .map:
                shareMapBackground(size: size)
            case .white:
                selectedStyle == .routeOnly ? Color.black : Color.white
            case .photo:
                photoBackground(size: size)
            case .gradient:
                LinearGradient(
                    colors: [shareAccent, shareAccentDeep, Color(red: 0.08, green: 0.10, blue: 0.15)],
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

    @ViewBuilder
    private func photoEditingLayer(size: CGSize, isExport: Bool) -> some View {
        if backgroundOption == .photo && !isExport {
            Color.clear
                .contentShape(Rectangle())
                .gesture(photoDragGesture(size: size))
                .simultaneousGesture(photoScaleGesture(size: size))
                .onTapGesture(count: 2) {
                    resetPhotoTransform()
                }
        }
    }

    private func photoBackground(size: CGSize) -> some View {
        Group {
            if let selectedPhotoImage {
                ZStack {
                    Image(uiImage: selectedPhotoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(photoScale)
                        .offset(photoOffset)
                        .clipped()

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            } else {
                LinearGradient(
                    colors: [shareAccentMist, Color(red: 0.76, green: 0.81, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func photoDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                photoOffset = clampedPhotoOffset(
                    CGSize(
                        width: photoOffsetOrigin.width + value.translation.width,
                        height: photoOffsetOrigin.height + value.translation.height
                    ),
                    scale: photoScale,
                    size: size
                )
            }
            .onEnded { _ in
                photoOffsetOrigin = photoOffset
            }
    }

    private func photoScaleGesture(size: CGSize) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                photoScale = min(max(photoScaleOrigin * value, 1), 2.6)
                photoOffset = clampedPhotoOffset(photoOffset, scale: photoScale, size: size)
            }
            .onEnded { _ in
                photoScaleOrigin = photoScale
                photoOffset = clampedPhotoOffset(photoOffset, scale: photoScale, size: size)
                photoOffsetOrigin = photoOffset
            }
    }

    private func clampedPhotoOffset(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let horizontalLimit = max((size.width * scale - size.width) * 0.5, 0) + 24
        let verticalLimit = max((size.height * scale - size.height) * 0.5, 0) + 24

        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private func shareMapBackground(size: CGSize) -> some View {
        ZStack {
            if let mapSnapshot {
                Image(uiImage: mapSnapshot.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                ZStack {
                    Color(red: 0.930, green: 0.928, blue: 0.895)

                    Path { path in
                        path.move(to: CGPoint(x: size.width * -0.08, y: size.height * 0.28))
                        path.addCurve(
                            to: CGPoint(x: size.width * 1.08, y: size.height * 0.18),
                            control1: CGPoint(x: size.width * 0.22, y: size.height * 0.18),
                            control2: CGPoint(x: size.width * 0.70, y: size.height * 0.32)
                        )
                        path.move(to: CGPoint(x: size.width * 0.18, y: size.height * -0.08))
                        path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 1.08))
                        path.move(to: CGPoint(x: size.width * -0.04, y: size.height * 0.72))
                        path.addLine(to: CGPoint(x: size.width * 1.06, y: size.height * 0.82))
                    }
                    .stroke(Color.white.opacity(0.82), style: StrokeStyle(lineWidth: size.width * 0.055, lineCap: .round, lineJoin: .round))

                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.48))
                        path.addLine(to: CGPoint(x: size.width * 0.94, y: size.height * 0.42))
                        path.move(to: CGPoint(x: size.width * 0.72, y: size.height * -0.02))
                        path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.98))
                    }
                    .stroke(Color(red: 0.78, green: 0.80, blue: 0.78).opacity(0.55), style: StrokeStyle(lineWidth: size.width * 0.010, lineCap: .round))

                    Circle()
                        .fill(Color(red: 0.74, green: 0.86, blue: 0.60).opacity(0.72))
                        .frame(width: size.width * 0.34, height: size.width * 0.34)
                        .position(x: size.width * 0.76, y: size.height * 0.72)
                }
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(selectedStyle == .dark ? 0.02 : 0.12),
                    Color.black.opacity(selectedStyle == .dark ? 0.18 : 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var styleOverlay: some View {
        Group {
            switch selectedStyle {
            case .light:
                Color.white.opacity(backgroundOption == .photo ? 0.12 : backgroundOption == .map ? 0.05 : 0)
            case .dark:
                Color.black.opacity(backgroundOption == .transparent ? 0.12 : 0.28)
            case .gradient:
                LinearGradient(
                    colors: [shareAccentMist.opacity(0.14), shareAccentDeep.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .minimal:
                Color.clear
            case .routeOnly:
                LinearGradient(
                    colors: [Color.white.opacity(0.02), shareAccent.opacity(backgroundOption == .photo ? 0.22 : 0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var foregroundColor: Color {
        if backgroundOption == .photo {
            return .white
        }

        switch selectedStyle {
        case .dark, .gradient, .routeOnly:
            return .white
        case .minimal:
            return backgroundOption == .gradient ? .white : .black
        case .light:
            return backgroundOption == .gradient ? .white : .black
        }
    }

    private var metricFooterBackground: Color {
        if backgroundOption == .photo {
            return Color.black.opacity(0.34)
        }

        switch selectedStyle {
        case .dark, .gradient, .routeOnly:
            return Color.black.opacity(0.26)
        case .minimal:
            return backgroundOption == .gradient ? Color.black.opacity(0.24) : Color.white.opacity(0.84)
        case .light:
            return backgroundOption == .gradient ? Color.black.opacity(0.22) : Color.white.opacity(0.86)
        }
    }

    private var secondaryColor: Color {
        if backgroundOption == .photo {
            return Color.white.opacity(0.92)
        }

        switch selectedStyle {
        case .dark, .gradient:
            return Color.white.opacity(0.76)
        case .routeOnly:
            return Color.white.opacity(0.72)
        case .minimal:
            return backgroundOption == .gradient ? Color.white.opacity(0.72) : Color.black.opacity(0.52)
        case .light:
            return backgroundOption == .gradient ? Color.white.opacity(0.76) : Color.black.opacity(0.58)
        }
    }

    private var shareStyleBadge: String {
        if backgroundOption == .map {
            return appLanguage.text("MAP", "MAP")
        }

        switch selectedStyle {
        case .routeOnly:
            return appLanguage.text("ROUTE ONLY", "ROUTE ONLY")
        case .gradient:
            return appLanguage.text("GRADIENT", "GRADIENT")
        case .dark:
            return appLanguage.text("PHOTO", "PHOTO")
        case .light, .minimal:
            return appLanguage.text("CLEAN", "CLEAN")
        }
    }

    private var routeColors: [Color] {
        switch selectedStyle {
        case .light:
            return [shareAccentDeep, shareAccent]
        case .dark:
            return [shareAccent.opacity(0.92), Color.white.opacity(0.92)]
        case .gradient:
            return [shareAccentMist, shareAccent, shareAccentDeep]
        case .minimal:
            return backgroundOption == .gradient ? [.white, .white.opacity(0.82)] : [.black, .black.opacity(0.82)]
        case .routeOnly:
            return [Color.white.opacity(0.92), shareAccent, shareAccentDeep]
        }
    }

    private var routeGlowOpacity: Double {
        switch selectedStyle {
        case .routeOnly:
            return 0.18
        case .gradient:
            return 0.16
        case .dark:
            return 0.14
        case .light:
            return 0.08
        case .minimal:
            return 0.02
        }
    }

    private func routeGraphic(frame: CGRect) -> some View {
        let drawingRect = backgroundOption == .map
            ? CGRect(origin: .zero, size: frame.size)
            : CGRect(origin: .zero, size: frame.size).insetBy(dx: 10, dy: 10)
        let points = previewRoutePoints(in: drawingRect)
        let path = smoothedPath(points)
        let paceSegments = pacedRouteSegments(in: drawingRect)
        let kilometerMarkers = routeKilometerMarkers(in: drawingRect)
        let showsPaceMap = selectedStyle == .routeOnly && !paceSegments.isEmpty
        let showsMarkers = selectedStyle == .routeOnly

        return ZStack {
            if showsPaceMap {
                ForEach(Array(paceSegments.enumerated()), id: \.offset) { _, segment in
                    Path { pacePath in
                        pacePath.move(to: segment.start)
                        pacePath.addLine(to: segment.end)
                    }
                    .stroke(segment.color.opacity(0.16), style: StrokeStyle(lineWidth: shareRouteLineWidth + 2.6, lineCap: .round, lineJoin: .round))
                    .blur(radius: 2.4)

                    Path { pacePath in
                        pacePath.move(to: segment.start)
                        pacePath.addLine(to: segment.end)
                    }
                    .stroke(segment.color, style: StrokeStyle(lineWidth: shareRouteLineWidth, lineCap: .round, lineJoin: .round))
                }
            } else {
                path
                    .stroke(
                        LinearGradient(colors: routeColors.map { $0.opacity(routeGlowOpacity) }, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: shareRouteLineWidth + 2.8, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: selectedStyle == .minimal ? 0 : 2.2)

                path
                    .stroke(
                        LinearGradient(colors: routeColors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: shareRouteLineWidth, lineCap: .round, lineJoin: .round)
                    )
            }

            if let start = points.first {
                routeMarker(at: start, isStart: true)
            }

            if let end = points.last {
                routeMarker(at: end, isStart: false)
            }

            if showsMarkers {
                ForEach(Array(kilometerMarkers.enumerated()), id: \.offset) { _, marker in
                    Text("\(marker.kilometer)")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(Color.black.opacity(0.56))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .position(marker.point)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }

    private func routeMarker(at point: CGPoint, isStart: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isStart ? Color.white.opacity(0.88) : shareAccent.opacity(0.52))
                .frame(width: isStart ? 12 : 14, height: isStart ? 12 : 14)

            Circle()
                .stroke(isStart ? shareAccent.opacity(0.62) : Color.white.opacity(0.78), lineWidth: 2.5)
                .frame(width: isStart ? 12 : 14, height: isStart ? 12 : 14)

            if !isStart {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 4, height: 4)
            }
        }
        .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
        .position(point)
    }

    private func pacedRouteSegments(in rect: CGRect) -> [(start: CGPoint, end: CGPoint, color: Color)] {
        let actualPoints = normalizedRoutePoints(in: rect)
        guard actualPoints.count >= 2, actualPoints.count == record.routePoints.count else { return [] }

        return (1..<actualPoints.count).map { index in
            let previous = record.routePoints[index - 1]
            let current = record.routePoints[index]
            let segmentSpeed = [previous.speed, current.speed].filter { $0 > 0 }.reduce(0, +) / max(1, Double([previous.speed, current.speed].filter { $0 > 0 }.count))

            return (
                start: actualPoints[index - 1],
                end: actualPoints[index],
                color: paceColor(forSpeed: segmentSpeed)
            )
        }
    }

    private func paceColor(forSpeed speed: Double) -> Color {
        guard speed > 0 else { return RBColor.paceSlow }
        let secondsPerKm = 1000.0 / speed

        switch secondsPerKm {
        case ..<300:
            return RBColor.paceFast
        case ..<390:
            return RBColor.paceSteady
        default:
            return RBColor.paceSlow
        }
    }

    private func routeKilometerMarkers(in rect: CGRect) -> [(kilometer: Int, point: CGPoint)] {
        let actualPoints = normalizedRoutePoints(in: rect)
        guard actualPoints.count >= 2, actualPoints.count == record.routePoints.count else { return [] }

        var markers: [(Int, CGPoint)] = []
        var cumulativeDistance: Double = 0
        var nextMarkerDistance: Double = 1000

        for index in 1..<record.routePoints.count {
            let previous = CLLocation(latitude: record.routePoints[index - 1].latitude, longitude: record.routePoints[index - 1].longitude)
            let current = CLLocation(latitude: record.routePoints[index].latitude, longitude: record.routePoints[index].longitude)
            cumulativeDistance += current.distance(from: previous)

            while cumulativeDistance >= nextMarkerDistance {
                markers.append((Int(nextMarkerDistance / 1000), actualPoints[index]))
                nextMarkerDistance += 1000
            }
        }

        return markers
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
        if backgroundOption == .map, let normalizedPoints = mapSnapshot?.normalizedRoutePoints, normalizedPoints.count >= 2 {
            return normalizedPoints.map { point in
                CGPoint(
                    x: rect.minX + rect.width * point.x,
                    y: rect.minY + rect.height * point.y
                )
            }
        }

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

    private func makeMapSnapshot(size: CGSize, useDarkTheme: Bool) async -> ShareMapSnapshot? {
        let routePoints = record.routePoints
        guard !routePoints.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = 1
        options.mapType = .mutedStandard
        options.showsBuildings = true
        if #available(iOS 16.0, *) {
            options.pointOfInterestFilter = .excludingAll
        }
        options.traitCollection = UITraitCollection(userInterfaceStyle: useDarkTheme ? .dark : .light)
        options.region = snapshotRegion(for: routePoints)

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }

                let normalizedPoints = routePoints.map { point -> CGPoint in
                    let resolvedPoint = snapshot.point(for: point.coordinate)
                    return CGPoint(
                        x: min(max(resolvedPoint.x / max(size.width, 1), 0), 1),
                        y: min(max(resolvedPoint.y / max(size.height, 1), 0), 1)
                    )
                }

                continuation.resume(
                    returning: ShareMapSnapshot(
                        image: snapshot.image,
                        normalizedRoutePoints: normalizedPoints
                    )
                )
            }
        }
    }

    private func snapshotRegion(for routePoints: [RoutePoint]) -> MKCoordinateRegion {
        if routePoints.count == 1, let coordinate = routePoints.first?.coordinate {
            return MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
        }

        var mapRect = MKMapRect.null
        for coordinate in routePoints.map(\.coordinate) {
            let mapPoint = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0)
            mapRect = mapRect.isNull ? pointRect : mapRect.union(pointRect)
        }

        let paddedRect = mapRect.insetBy(
            dx: -max(mapRect.size.width * 0.38, 900),
            dy: -max(mapRect.size.height * 0.38, 900)
        )
        return MKCoordinateRegion(paddedRect)
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
    case photo
    case layout
    case data
    case style

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .photo:
            return appLanguage.text("사진", "Photo")
        case .layout:
            return appLanguage.text("레이아웃", "Layout")
        case .data:
            return appLanguage.text("데이터", "Data")
        case .style:
            return appLanguage.text("스타일", "Style")
        }
    }

    var symbolName: String {
        switch self {
        case .layout:
            return "square.on.square"
        case .data:
            return "number"
        case .style:
            return "paintpalette"
        case .photo:
            return "photo"
        }
    }
}

enum ShareLayoutPreset: String, CaseIterable, Identifiable {
    case routeOnly
    case photoRoute
    case routeStats
    case minimalStats

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .routeOnly:
            return "map"
        case .photoRoute:
            return "photo"
        case .routeStats:
            return "chart.bar"
        case .minimalStats:
            return "number"
        }
    }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .routeOnly:
            return appLanguage.text("경로만", "Route Only")
        case .photoRoute:
            return appLanguage.text("사진 + 경로", "Photo + Route")
        case .routeStats:
            return appLanguage.text("경로 + 기록", "Route + Stats")
        case .minimalStats:
            return appLanguage.text("미니멀 기록", "Minimal Stats")
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
        let priority: [ShareMetricOption] = [.distance, .time, .pace, .heartRate, .cadence, .calories, .elevation]
        let available = priority.filter { $0.display(from: record) != nil }
        return Array(available.prefix(3)).nonEmpty(or: [.time])
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

enum ShareCanvasRatio: String, CaseIterable, Identifiable {
    case post
    case story
    case square

    var id: String { rawValue }

    var exportSize: CGSize {
        switch self {
        case .post:
            return shareCardExportSize
        case .story:
            return CGSize(width: 1080, height: 1920)
        case .square:
            return CGSize(width: 1080, height: 1080)
        }
    }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .post:
            return appLanguage.text("4:5", "4:5")
        case .story:
            return appLanguage.text("9:16", "9:16")
        case .square:
            return appLanguage.text("1:1", "1:1")
        }
    }
}

enum ShareRoutePalette: String, CaseIterable, Identifiable {
    case beam
    case ember
    case sand
    case dusk

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .beam:
            return appLanguage.text("빔", "Beam")
        case .ember:
            return appLanguage.text("엠버", "Ember")
        case .sand:
            return appLanguage.text("샌드", "Sand")
        case .dusk:
            return appLanguage.text("더스크", "Dusk")
        }
    }

    var primary: Color {
        switch self {
        case .beam:
            return sharePrimaryColor
        case .ember:
            return Color(red: 0.98, green: 0.42, blue: 0.30)
        case .sand:
            return Color(red: 0.72, green: 0.56, blue: 0.18)
        case .dusk:
            return Color(red: 0.43, green: 0.36, blue: 0.85)
        }
    }

    var deep: Color {
        switch self {
        case .beam:
            return sharePrimaryDeepColor
        case .ember:
            return Color(red: 0.76, green: 0.23, blue: 0.17)
        case .sand:
            return Color(red: 0.47, green: 0.33, blue: 0.10)
        case .dusk:
            return Color(red: 0.24, green: 0.18, blue: 0.56)
        }
    }

    var mist: Color {
        switch self {
        case .beam:
            return sharePrimaryMistColor
        case .ember:
            return Color(red: 1.0, green: 0.94, blue: 0.92)
        case .sand:
            return Color(red: 0.97, green: 0.94, blue: 0.88)
        case .dusk:
            return Color(red: 0.94, green: 0.92, blue: 1.0)
        }
    }

    var swatch: LinearGradient {
        LinearGradient(
            colors: [mist, primary, deep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum ShareVisualStyle: String, CaseIterable, Identifiable {
    case light
    case dark
    case gradient
    case minimal
    case routeOnly

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
        case .routeOnly:
            return appLanguage.text("경로만", "Route Only")
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
        case .routeOnly:
            return LinearGradient(colors: [Color.black, sharePrimaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

enum ShareBackgroundOption: String, CaseIterable, Identifiable {
    case map
    case white
    case photo
    case gradient
    case transparent

    var id: String { rawValue }

    func title(_ appLanguage: AppLanguage) -> String {
        switch self {
        case .map:
            return appLanguage.text("지도", "Map")
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

    var swatch: AnyShapeStyle {
        switch self {
        case .map:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.92, blue: 0.88),
                        Color(red: 0.70, green: 0.82, blue: 0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .white:
            return AnyShapeStyle(Color.white)
        case .photo:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.64, green: 0.70, blue: 0.78), Color(red: 0.24, green: 0.26, blue: 0.30)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .gradient:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [sharePrimaryColor, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .transparent:
            return AnyShapeStyle(Color.clear)
        }
    }
}

private struct ShareMapSnapshot {
    let image: UIImage
    let normalizedRoutePoints: [CGPoint]
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
