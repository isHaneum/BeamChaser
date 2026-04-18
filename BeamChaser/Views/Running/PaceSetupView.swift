import SwiftUI

struct PaceSetupView: View {
    @EnvironmentObject var runSession: RunSessionManager
    @State private var paceMinutes: Int = 5
    @State private var paceSeconds: Int = 30
    @State private var navigateToRun = false

    // 독립적 목표 토글
    @State private var distanceGoalEnabled = false
    @State private var timeGoalEnabled = false
    @State private var paceGoalEnabled = true
    @State private var targetDistanceKm: Double = 5.0
    @State private var targetTimeMinutes: Int = 30

    // 어떤 카드가 열려있는지 (아코디언)
    @State private var expandedCard: GoalCard?

    enum GoalCard { case distance, time, pace }

    // 인터벌 모드
    @State private var isIntervalMode = false
    @State private var selectedInterval: IntervalProgram?

    // 커스텀 인터벌
    @State private var showCreateInterval = false
    @State private var customSegments: [IntervalSegment] = [
        IntervalSegment(name: "웜업", distanceKm: 1.0, paceMinutes: 6, paceSeconds: 30),
        IntervalSegment(name: "본운동", distanceKm: 2.0, paceMinutes: 5, paceSeconds: 0),
        IntervalSegment(name: "쿨다운", distanceKm: 1.0, paceMinutes: 7, paceSeconds: 0),
    ]
    @State private var customIntervalName: String = ""

    // 탭 전환 (일반 / 인터벌)
    @State private var setupTab: SetupTab = .normal

    enum SetupTab: String, CaseIterable {
        case normal = "일반"
        case interval = "인터벌"
    }

    private let presets: [(String, Int, Int)] = [
        ("초급", 7, 0), ("중급", 5, 30), ("고급", 4, 30), ("엘리트", 3, 30),
    ]

    private let distancePresets: [Double] = [3.0, 5.0, 10.0, 21.1]
    private let secondsPresets: [Int] = [0, 10, 20, 30, 40, 50]

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // 탭 선택 (일반 / 인터벌) — 맨 위
                    Picker("", selection: $setupTab) {
                        ForEach(SetupTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if setupTab == .normal {
                        // 목표 토글 박스 3개
                        goalToggleBoxes
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // 선택된 카드의 설정 패널
                        if let card = expandedCard {
                            expandedCardContent(for: card)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .transition(.opacity)
                        }

                        normalSetupContent
                    } else {
                        intervalSetupContent
                    }

                    Spacer(minLength: 20)
                }
                .padding(.bottom, 28)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [RBColor.bg.opacity(0), RBColor.bg.opacity(0.92), RBColor.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(setupTab == .interval ? "인터벌 준비" : "러닝 준비 완료")
                            .font(RBFont.caption(10))
                            .foregroundStyle(RBColor.textTertiary)
                            .tracking(1)

                        Text(startSummaryTitle)
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)

                        if !startSummaryItems.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(startSummaryItems, id: \.self) { item in
                                        Text(item)
                                            .font(RBFont.caption(11))
                                            .foregroundStyle(RBColor.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(RBColor.cardBgLight)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(RBColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    RBPrimaryButton(canStartRun ? "이 설정으로 시작" : "인터벌을 선택하세요", icon: "figure.run") {
                        startRun()
                    }
                    .opacity(canStartRun ? 1 : 0.5)
                    .disabled(!canStartRun)
                }
                .navigationDestination(isPresented: $navigateToRun) {
                    RunActiveView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(RBColor.bg)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - 일반 설정 — 펼쳐진 설정 패널만 (토글 박스 아래)

    private var normalSetupContent: some View {
        EmptyView()  // 설정 패널은 expandedCardContent에서 표시
    }

    // MARK: - 목표 토글 박스 3개 (정사각형, 1/3 화면 너비)

    private var goalToggleBoxes: some View {
        GeometryReader { geo in
            let boxSize = (geo.size.width - 16) / 3  // 3등분, 간격 고려
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    goalBox(
                        icon: "flag.checkered",
                        label: "거리",
                        value: distanceGoalEnabled ? String(format: "%.1f", targetDistanceKm) : "-",
                        unit: "km",
                        isOn: distanceGoalEnabled,
                        card: .distance,
                        size: boxSize
                    )
                    goalBox(
                        icon: "clock",
                        label: "시간",
                        value: timeGoalEnabled ? "\(targetTimeMinutes)" : "-",
                        unit: "분",
                        isOn: timeGoalEnabled,
                        card: .time,
                        size: boxSize
                    )
                    goalBox(
                        icon: "speedometer",
                        label: "페이스",
                        value: paceGoalEnabled ? "\(paceMinutes)'\(String(format: "%02d", paceSeconds))\"" : "-",
                        unit: "/km",
                        isOn: paceGoalEnabled,
                        card: .pace,
                        size: boxSize
                    )
                }
                // OFF 버튼 행
                HStack(spacing: 8) {
                    goalStateButton(card: .distance, isOn: distanceGoalEnabled, width: boxSize)
                    goalStateButton(card: .time, isOn: timeGoalEnabled, width: boxSize)
                    goalStateButton(card: .pace, isOn: paceGoalEnabled, width: boxSize)
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width - 56) / 3 + 42)  // 정사각형 + 상태 버튼 높이
        .animation(.spring(response: 0.3), value: expandedCard)
    }

    private func goalStateButton(card: GoalCard, isOn: Bool, width: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                toggleGoal(card)
            }
        } label: {
            Text(isOn ? "ON" : "OFF")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? .white : RBColor.textSecondary)
                .frame(width: width, height: 34)
                .background(isOn ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBgLight))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isOn ? Color.white.opacity(0.08) : RBColor.divider.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func goalBox(icon: String, label: String, value: String, unit: String, isOn: Bool, card: GoalCard, size: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                switch card {
                case .distance:
                    if distanceGoalEnabled {
                        if expandedCard == card {
                            expandedCard = nil
                        } else {
                            expandedCard = card
                        }
                    } else {
                        distanceGoalEnabled = true
                        expandedCard = card
                    }
                case .time:
                    if timeGoalEnabled {
                        if expandedCard == card {
                            expandedCard = nil
                        } else {
                            expandedCard = card
                        }
                    } else {
                        timeGoalEnabled = true
                        expandedCard = card
                    }
                case .pace:
                    if paceGoalEnabled {
                        if expandedCard == card {
                            expandedCard = nil
                        } else {
                            expandedCard = card
                        }
                    } else {
                        paceGoalEnabled = true
                        expandedCard = card
                    }
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? RBColor.accent : RBColor.textTertiary)

                Text(value)
                    .font(RBFont.metric(20))
                    .foregroundStyle(isOn ? RBColor.textPrimary : RBColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(RBFont.caption(11))
                    .foregroundStyle(isOn ? RBColor.textSecondary : RBColor.textTertiary)

                Text(label)
                    .font(RBFont.caption(10))
                    .foregroundStyle(isOn ? RBColor.accent : RBColor.textTertiary)
            }
            .frame(width: size, height: size)
            .background(isOn ? RBColor.accent.opacity(0.1) : RBColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        expandedCard == card ? RBColor.accent : (isOn ? RBColor.accent.opacity(0.4) : .clear),
                        lineWidth: expandedCard == card ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleGoal(_ card: GoalCard) {
        switch card {
        case .distance:
            distanceGoalEnabled.toggle()
            if distanceGoalEnabled {
                expandedCard = .distance
            } else if expandedCard == .distance {
                expandedCard = nil
            }
        case .time:
            timeGoalEnabled.toggle()
            if timeGoalEnabled {
                expandedCard = .time
            } else if expandedCard == .time {
                expandedCard = nil
            }
        case .pace:
            paceGoalEnabled.toggle()
            if paceGoalEnabled {
                expandedCard = .pace
            } else if expandedCard == .pace {
                expandedCard = nil
            }
        }
    }

    // MARK: - 펼쳐진 설정 패널

    @ViewBuilder
    private func expandedCardContent(for card: GoalCard) -> some View {
        VStack(spacing: 0) {
            switch card {
            case .distance:
                distanceSettingsPanel
            case .time:
                timeSettingsPanel
            case .pace:
                paceSettingsPanel
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RBColor.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private var distanceSettingsPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", targetDistanceKm))
                    .font(RBFont.metric(32))
                    .foregroundStyle(RBColor.textPrimary)
                Text("km")
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach(distancePresets, id: \.self) { dist in
                    Button {
                        withAnimation { targetDistanceKm = dist }
                    } label: {
                        Text(dist == 21.1 ? "하프" : "\(Int(dist))km")
                            .font(RBFont.label(12))
                            .foregroundStyle(targetDistanceKm == dist ? RBColor.textPrimary : RBColor.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(targetDistanceKm == dist ? RBColor.accent.opacity(0.3) : RBColor.cardBgLight)
                            .clipShape(Capsule())
                    }
                }
            }

            Slider(value: $targetDistanceKm, in: 1.0...42.2, step: 0.5)
                .tint(RBColor.accent)

            goalResetButton(card: .distance)
        }
    }

    private var timeSettingsPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(targetTimeMinutes)")
                    .font(RBFont.metric(32))
                    .foregroundStyle(RBColor.textPrimary)
                Text("분")
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach([15, 20, 30, 45, 60], id: \.self) { mins in
                    Button {
                        withAnimation { targetTimeMinutes = mins }
                    } label: {
                        Text("\(mins)분")
                            .font(RBFont.label(12))
                            .foregroundStyle(targetTimeMinutes == mins ? RBColor.textPrimary : RBColor.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(targetTimeMinutes == mins ? RBColor.accent.opacity(0.3) : RBColor.cardBgLight)
                            .clipShape(Capsule())
                    }
                }
            }

            paceAdjuster(label: "분", value: $targetTimeMinutes, range: 5...180)

            goalResetButton(card: .time)
        }
    }

    private var paceSettingsPanel: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(String(format: "%d", paceMinutes))
                    .font(RBFont.metric(52))
                    .foregroundStyle(RBColor.textPrimary)
                Text("'")
                    .font(RBFont.metric(28))
                    .foregroundStyle(RBColor.accent)
                Text(String(format: "%02d", paceSeconds))
                    .font(RBFont.metric(52))
                    .foregroundStyle(RBColor.textPrimary)
                Text("\"")
                    .font(RBFont.metric(28))
                    .foregroundStyle(RBColor.accent)
            }

            Text("/ km")
                .font(RBFont.label(14))
                .foregroundStyle(RBColor.textSecondary)

            HStack(spacing: 8) {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            paceMinutes = preset.1
                            paceSeconds = preset.2
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(preset.0)
                                .font(RBFont.label(11))
                            Text("\(preset.1)'\(String(format: "%02d", preset.2))\"")
                                .font(RBFont.caption(10))
                                .foregroundStyle(RBColor.textSecondary)
                        }
                        .foregroundStyle(
                            paceMinutes == preset.1 && paceSeconds == preset.2
                                ? RBColor.textPrimary : RBColor.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            paceMinutes == preset.1 && paceSeconds == preset.2
                                ? RBColor.accent.opacity(0.3) : RBColor.cardBgLight
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.top, 4)

            paceAdjuster(label: "분", value: $paceMinutes, range: 2...12)
                .padding(.top, 4)

            paceAdjuster(label: "초", value: $paceSeconds, range: 0...55, step: 5)

            HStack(spacing: 8) {
                ForEach(secondsPresets, id: \.self) { sec in
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            paceSeconds = sec
                        }
                    } label: {
                        Text("\(sec)")
                            .font(RBFont.label(13))
                            .foregroundStyle(paceSeconds == sec ? RBColor.textPrimary : RBColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(paceSeconds == sec ? RBColor.accent.opacity(0.3) : RBColor.cardBgLight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.top, 2)

            goalResetButton(card: .pace)
        }
    }

    private func goalResetButton(card: GoalCard) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                switch card {
                case .distance: distanceGoalEnabled = false
                case .time: timeGoalEnabled = false
                case .pace: paceGoalEnabled = false
                }
                expandedCard = nil
            }
        } label: {
            Text("미설정")
                .font(RBFont.label(13))
                .foregroundStyle(RBColor.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - 인터벌 설정

    private var intervalSetupContent: some View {
        VStack(spacing: 16) {
            // 커스텀 생성 버튼
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showCreateInterval.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text("직접 만들기")
                        .font(RBFont.label(15))
                    Spacer()
                    Image(systemName: showCreateInterval ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(RBColor.accent)
                .padding(14)
                .background(RBColor.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(RBColor.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            if showCreateInterval {
                customIntervalBuilder
            }

            Text("프리셋")
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textSecondary)
                .tracking(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            ForEach(IntervalProgram.presets, id: \.name) { program in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedInterval = program
                        showCreateInterval = false
                    }
                } label: {
                    intervalCard(program)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 커스텀 인터벌 빌더

    private var customIntervalBuilder: some View {
        VStack(spacing: 12) {
            // 이름
            TextField("인터벌 이름", text: $customIntervalName)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
                .padding(12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 구간 리스트
            ForEach(Array(customSegments.enumerated()), id: \.element.id) { index, segment in
                customSegmentRow(index: index, segment: segment)
            }

            // 구간 추가
            Button {
                withAnimation {
                    customSegments.append(
                        IntervalSegment(name: "구간 \(customSegments.count + 1)", distanceKm: 1.0, paceMinutes: 5, paceSeconds: 30)
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("구간 추가")
                        .font(RBFont.label(13))
                }
                .foregroundStyle(RBColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // 총 거리 요약
            HStack {
                Text("총 거리")
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textSecondary)
                Spacer()
                Text(String(format: "%.1fkm", customSegments.reduce(0) { $0 + $1.distanceKm }))
                    .font(RBFont.metric(16))
                    .foregroundStyle(RBColor.accent)
            }
            .padding(.horizontal, 4)

            // 적용
            Button {
                let name = customIntervalName.isEmpty ? "커스텀 인터벌" : customIntervalName
                let program = IntervalProgram(name: name, segments: customSegments)
                withAnimation(.spring(response: 0.3)) {
                    selectedInterval = program
                    showCreateInterval = false
                }
            } label: {
                Text("이 인터벌로 설정")
                    .font(RBFont.label(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RBColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.opacity)
    }

    @ViewBuilder
    private func customSegmentRow(index: Int, segment: IntervalSegment) -> some View {
        let segColor = segmentColor(segment)

        HStack(spacing: 10) {
            segmentNameMenu(index: index, name: segment.name, color: segColor)
            Spacer()
            customSegmentDistanceControl(index: index, segment: segment)
            Text("km")
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
            customSegmentPaceControl(index: index, segment: segment)
            segmentDeleteButton(index: index)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func segmentNameMenu(index: Int, name: String, color: Color) -> some View {
        Menu {
            ForEach(["웜업", "본운동", "빠르게", "회복", "쿨다운", "1단계", "2단계", "3단계"], id: \.self) { newName in
                Button(newName) {
                    let s = customSegments[index]
                    customSegments[index] = IntervalSegment(
                        name: newName, distanceKm: s.distanceKm,
                        paceMinutes: s.paceMinutes, paceSeconds: s.paceSeconds
                    )
                }
            }
        } label: {
            Text(name)
                .font(RBFont.label(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.3))
                .clipShape(Capsule())
        }
    }

    private func segmentDeleteButton(index: Int) -> some View {
        Group {
            if customSegments.count > 1 {
                Button {
                    withAnimation { _ = customSegments.remove(at: index) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RBColor.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(RBColor.cardBgLight)
                        .clipShape(Circle())
                }
            }
        }
    }

    private func customSegmentDistanceControl(index: Int, segment: IntervalSegment) -> some View {
        HStack(spacing: 4) {
            Button {
                let new = max(0.5, customSegments[index].distanceKm - 0.5)
                let s = customSegments[index]
                customSegments[index] = IntervalSegment(name: s.name, distanceKm: new, paceMinutes: s.paceMinutes, paceSeconds: s.paceSeconds)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(RBColor.cardBgLight)
                    .clipShape(Circle())
            }
            Text(String(format: "%.1f", segment.distanceKm))
                .font(RBFont.metric(13))
                .foregroundStyle(.white)
                .frame(width: 32)
            Button {
                let new = min(10.0, customSegments[index].distanceKm + 0.5)
                let s = customSegments[index]
                customSegments[index] = IntervalSegment(name: s.name, distanceKm: new, paceMinutes: s.paceMinutes, paceSeconds: s.paceSeconds)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(RBColor.cardBgLight)
                    .clipShape(Circle())
            }
        }
        .foregroundStyle(RBColor.textPrimary)
    }

    private func customSegmentPaceControl(index: Int, segment: IntervalSegment) -> some View {
        Menu {
            ForEach(3...9, id: \.self) { min in
                ForEach([0, 30], id: \.self) { sec in
                    Button("\(min)'\(String(format: "%02d", sec))\"") {
                        let s = customSegments[index]
                        customSegments[index] = IntervalSegment(name: s.name, distanceKm: s.distanceKm, paceMinutes: min, paceSeconds: sec)
                    }
                }
            }
        } label: {
            Text(segment.formattedPace)
                .font(RBFont.metric(12))
                .foregroundStyle(RBColor.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RBColor.cardBgLight)
                .clipShape(Capsule())
        }
    }

    private func intervalCard(_ program: IntervalProgram) -> some View {
        let isSelected = selectedInterval?.name == program.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(program.name)
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                Text(String(format: "%.1fkm", program.totalDistanceKm))
                    .font(RBFont.metric(14))
                    .foregroundStyle(RBColor.accent)
            }

            // 구간 시각화
            HStack(spacing: 2) {
                ForEach(program.segments) { segment in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segmentColor(segment))
                            .frame(height: 6)
                        Text(segment.name)
                            .font(RBFont.caption(8))
                            .foregroundStyle(RBColor.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // 상세 구간 (선택 시)
            if isSelected {
                VStack(spacing: 4) {
                    ForEach(program.segments) { segment in
                        HStack {
                            Circle()
                                .fill(segmentColor(segment))
                                .frame(width: 6, height: 6)
                            Text(segment.name)
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textSecondary)
                            Spacer()
                            Text(String(format: "%.1fkm", segment.distanceKm))
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textSecondary)
                            Text(segment.formattedPace)
                                .font(RBFont.metric(12))
                                .foregroundStyle(RBColor.accent)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(isSelected ? RBColor.accent.opacity(0.1) : RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? RBColor.accent : .clear, lineWidth: 1)
        )
    }

    private func segmentColor(_ segment: IntervalSegment) -> Color {
        let pace = segment.totalSecondsPerKm
        if pace < 270 { return RBColor.danger }       // < 4:30
        if pace < 330 { return RBColor.accent }        // < 5:30
        return RBColor.success                          // 쉬운 페이스
    }

    private var canStartRun: Bool {
        if setupTab == .interval {
            return selectedInterval != nil
        }
        return true
    }

    private var startSummaryTitle: String {
        if setupTab == .interval {
            return selectedInterval?.name ?? "시작할 인터벌 프로그램을 선택해 주세요"
        }

        if !distanceGoalEnabled && !timeGoalEnabled && !paceGoalEnabled {
            return "자유 러닝으로 바로 시작합니다"
        }

        return "선택한 목표와 페이스로 러닝을 시작합니다"
    }

    private var startSummaryItems: [String] {
        if setupTab == .interval {
            guard let selectedInterval else { return [] }
            return [
                String(format: "%.1fkm", selectedInterval.totalDistanceKm),
                "\(selectedInterval.segments.count)개 구간",
            ]
        }

        var items: [String] = []
        if distanceGoalEnabled {
            items.append(String(format: "거리 %.1fkm", targetDistanceKm))
        }
        if timeGoalEnabled {
            items.append("시간 \(targetTimeMinutes)분")
        }
        if paceGoalEnabled {
            items.append("페이스 \(paceMinutes)'\(String(format: "%02d", paceSeconds))\"/km")
        }
        if items.isEmpty {
            items.append("자유 러닝")
        }
        return items
    }

    // MARK: - Start Run

    private func startRun() {
        guard canStartRun else { return }

        if setupTab == .interval, let interval = selectedInterval {
            guard let first = interval.segments.first else { return }
            let target = PaceTarget(minutesPerKm: first.paceMinutes, secondsPerKm: first.paceSeconds)
            let goal = RunGoal(type: .distance, targetDistanceKm: interval.totalDistanceKm, targetTimeMinutes: nil)
            runSession.startRun(target: target, goal: goal, intervalProgram: interval)
        } else {
            let target: PaceTarget
            if paceGoalEnabled {
                target = PaceTarget(minutesPerKm: paceMinutes, secondsPerKm: paceSeconds)
            } else {
                target = PaceTarget(minutesPerKm: 5, secondsPerKm: 30)
            }
            let goal: RunGoal
            if distanceGoalEnabled {
                if timeGoalEnabled {
                    goal = RunGoal(type: .combined, targetDistanceKm: targetDistanceKm, targetTimeMinutes: targetTimeMinutes)
                } else {
                    goal = RunGoal(type: .distance, targetDistanceKm: targetDistanceKm, targetTimeMinutes: nil)
                }
            } else if timeGoalEnabled {
                goal = RunGoal(type: .time, targetDistanceKm: nil, targetTimeMinutes: targetTimeMinutes)
            } else {
                goal = .none
            }
            runSession.startRun(target: target, goal: goal, intervalProgram: nil)
        }
        navigateToRun = true
    }

    // MARK: - 페이스 조절기

    private func paceAdjuster(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(RBFont.label(14))
                .foregroundStyle(RBColor.textSecondary)
                .frame(width: 28)

            Button {
                withAnimation(.spring(response: 0.2)) {
                    let newVal = value.wrappedValue - step
                    if newVal >= range.lowerBound { value.wrappedValue = newVal }
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RBColor.cardBgLight)
                    .clipShape(Circle())
            }

            Spacer()

            Text("\(value.wrappedValue)")
                .font(RBFont.metric(28))
                .foregroundStyle(RBColor.textPrimary)
                .frame(width: 50)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.2)) {
                    let newVal = value.wrappedValue + step
                    if newVal <= range.upperBound { value.wrappedValue = newVal }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RBColor.cardBgLight)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        PaceSetupView()
            .environmentObject(RunSessionManager())
    }
}
