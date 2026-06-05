import SwiftUI

struct RunHistoryView: View {
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject private var appNavigation: AppNavigationModel
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @State private var visibleMonth = Date()
    @State private var selectedDate: Date?
    @State private var monthSlideDirection = 1
    @State private var didSeedVisibleMonth = false
    @State private var navigationPath: [UUID] = []
    @State private var finishToastText: String?
    @State private var finishToastTask: Task<Void, Never>?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var sortedRecords: [RunRecord] {
        runSession.savedRecords.sorted { $0.startDate > $1.startDate }
    }

    private var visibleRecords: [RunRecord] {
        guard let selectedDate else { return sortedRecords }
        return sortedRecords.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDate) }
    }

    private var visibleMonthStart: Date {
        startOfMonth(for: visibleMonth)
    }

    private var visibleMonthKey: TimeInterval {
        visibleMonthStart.timeIntervalSinceReferenceDate
    }

    private var weekdayLabels: [String] {
        appLanguage.isEnglish
            ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            : ["월", "화", "수", "목", "금", "토", "일"]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                if runSession.savedRecords.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard
                                .padding(.horizontal, 16)

                            calendarCard
                                .padding(.horizontal, 16)

                            recordsSection
                        }
                        .padding(.top, 8)
                    }
                    .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
                }
            }
            .navigationTitle(appLanguage.localized("러닝 기록"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { recordId in
                if let record = record(for: recordId) {
                    RunDetailView(record: record)
                } else {
                    missingDetailView
                }
            }
            .overlay(alignment: .top) {
                if let finishToastText {
                    finishToastView(text: finishToastText)
                        .padding(.top, 8)
                }
            }
            .onAppear {
                seedVisibleMonthIfNeeded()
                handlePendingRunNavigation()
            }
            .onChange(of: runSession.savedRecords.count) { _, _ in
                seedVisibleMonthIfNeeded()
                handlePendingRunNavigation()
            }
            .onChange(of: appNavigation.pendingRunRecordId) { _, _ in
                handlePendingRunNavigation()
            }
        }
    }

    // MARK: - 통계 요약

    private var summaryCard: some View {
        let records = runSession.savedRecords.filter { $0.totalDistanceMeters > 100 }
        let totalDistance = records.map(\.totalDistanceMeters).reduce(0, +)
        let totalTime = records.map(\.elapsedSeconds).reduce(0, +)
        let avgPace = records.isEmpty ? 0 : records.map(\.averagePaceSecondsPerKm).reduce(0, +) / Double(records.count)
        let bestPace = records.map(\.averagePaceSecondsPerKm).filter { $0 > 0 }.min() ?? 0

        return VStack(spacing: 12) {
            HStack {
                Text(appLanguage.localized("전체 통계").uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()
                Text(appLanguage.text("\(records.count)회 러닝", "\(records.count) runs"))
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                summaryMetricTile(
                    title: appLanguage.localized("총 거리"),
                    value: String(format: "%.1f", totalDistance / 1000.0),
                    unit: "km"
                )
                summaryMetricTile(
                    title: appLanguage.localized("총 시간"),
                    value: RunRecord.formatDuration(totalTime),
                    unit: nil
                )
                summaryMetricTile(
                    title: appLanguage.localized("평균 페이스"),
                    value: RunRecord.formatPace(avgPace),
                    unit: "/km"
                )
                summaryMetricTile(
                    title: appLanguage.localized("최고 페이스"),
                    value: RunRecord.formatPace(bestPace),
                    unit: "/km",
                    valueColor: RBColor.success
                )
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    private func summaryMetricTile(
        title: String,
        value: String,
        unit: String?,
        valueColor: Color = RBColor.textPrimary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(RBFont.metric(21))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if let unit {
                    Text(unit)
                        .font(RBFont.unit(10))
                        .foregroundStyle(RBColor.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RBColor.cardBgLight.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous))
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        let records = sortedRecords
        let daySummaries = buildCalendarMap(from: records)
        let cells = monthCells(for: visibleMonthStart)
        let monthSummary = summaryForMonth(records: records, monthStart: visibleMonthStart)
        let streak = currentStreak(from: records)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage.text("달력", "Calendar"))
                        .font(RBFont.title(18))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(monthSummaryText(monthSummary))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Text(appLanguage.text("연속 \(streak)일", "\(streak)d streak"))
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.warning)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(RBColor.warning.opacity(0.12))
                    )
            }

            HStack(spacing: 10) {
                monthButton(systemName: "chevron.left", direction: -1)

                Text(monthLabel(for: visibleMonthStart))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                monthButton(systemName: "chevron.right", direction: 1)
            }

            HStack(spacing: 1) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            ZStack {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7),
                    spacing: 5
                ) {
                    ForEach(cells) { cell in
                        calendarDayButton(cell, summary: daySummaries[cell.dayStart])
                    }
                }
                .id(visibleMonthKey)
                .transition(monthTransition)
            }
            .animation(.easeInOut(duration: 0.24), value: visibleMonthKey)
            .clipped()

            if let selectedDate {
                selectedDateSummary(selectedDate, daySummaries: daySummaries)
            }
        }
        .padding(14)
        .background(RBColor.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(RBColor.divider.opacity(0.82), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
        .gesture(monthSwipeGesture)
    }

    private func monthButton(systemName: String, direction: Int) -> some View {
        Button {
            changeMonth(by: direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RBColor.warning)
                .frame(width: 40, height: 40)
                .background(RBColor.cardBgLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(RBColor.divider.opacity(0.95), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func calendarDayButton(_ cell: HistoryMonthCell, summary: HistoryCalendarDaySummary?) -> some View {
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: cell.dayStart) } ?? false
        let isToday = calendar.isDateInToday(cell.dayStart)
        let hasRun = summary != nil

        return Button {
            selectDate(cell.dayStart)
        } label: {
            VStack(spacing: 4) {
                Text(String(calendar.component(.day, from: cell.dayStart)))
                    .font(RBFont.label(14))
                    .foregroundStyle(dayTextColor(isCurrentMonth: cell.isCurrentMonth, isSelected: isSelected, hasRun: hasRun))
                    .monospacedDigit()

                calendarDots(summary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dayBackgroundColor(isSelected: isSelected, hasRun: hasRun))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dayBorderColor(isSelected: isSelected, isToday: isToday), lineWidth: isSelected ? 2 : 1)
            )
            .opacity(cell.isCurrentMonth ? 1 : 0.42)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: cell.dayStart, summary: summary))
    }

    @ViewBuilder
    private func calendarDots(_ summary: HistoryCalendarDaySummary?) -> some View {
        HStack(spacing: 3) {
            if let summary {
                Circle()
                    .fill(intensityColor(for: summary.totalDistanceMeters))
                    .frame(width: 5, height: 5)

                if summary.count > 1 {
                    Circle()
                        .fill(RBColor.warning)
                        .frame(width: 5, height: 5)
                }
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 8)
    }

    private func selectedDateSummary(_ date: Date, daySummaries: [Date: HistoryCalendarDaySummary]) -> some View {
        let summary = daySummaries[calendar.startOfDay(for: date)] ?? .empty

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLabel(for: date))
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(appLanguage.text(
                    "\(summary.count)회 · \(distanceText(summary.totalDistanceMeters)) · \(RunRecord.formatDuration(summary.elapsedSeconds))",
                    "\(summary.count) runs · \(distanceText(summary.totalDistanceMeters)) · \(RunRecord.formatDuration(summary.elapsedSeconds))"
                ))
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RBColor.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: RBRadius.button, style: .continuous)
                .fill(RBColor.cardBgLight.opacity(0.75))
        )
    }

    private var recordsSection: some View {
        let records = visibleRecords

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate == nil
                         ? appLanguage.text("기록 리스트", "Run list")
                         : appLanguage.text("선택한 날짜", "Selected day"))
                    .font(RBFont.title(20))
                    .foregroundStyle(RBColor.textPrimary)

                    Text(selectedDate.map(dateLabel(for:)) ?? appLanguage.text("최신 순", "Newest first"))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textTertiary)
                }

                Spacer()

                Text(appLanguage.text("\(records.count)개", "\(records.count)"))
                    .font(RBFont.caption(13))
                    .foregroundStyle(RBColor.warning)
            }

            if records.isEmpty {
                emptySelectionCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(records) { record in
                        NavigationLink(value: record.id) {
                            runRecordCard(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptySelectionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appLanguage.text("이 날짜에는 러닝이 없습니다", "No runs on this day"))
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)
            Text(selectedDate.map(dateLabel(for:)) ?? "")
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RBColor.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .stroke(RBColor.divider.opacity(0.82), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundStyle(RBColor.textTertiary)
            Text(appLanguage.localized("러닝 기록이 없습니다"))
                .font(RBFont.label(17))
                .foregroundStyle(RBColor.textSecondary)
            Text(appLanguage.localized("첫 러닝을 시작해보세요!"))
                .font(RBFont.caption(14))
                .foregroundStyle(RBColor.textTertiary)
        }
    }

    private var missingDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(RBColor.textTertiary)
            Text(appLanguage.text("러닝 상세를 불러오지 못했어요", "Couldn't open the run detail"))
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RBColor.bg.ignoresSafeArea())
    }

    private func handlePendingRunNavigation() {
        guard let recordId = appNavigation.pendingRunRecordId,
              record(for: recordId) != nil else { return }

        navigationPath = [recordId]
        appNavigation.consumePendingRunRecordId()
        presentFinishToast()
    }

    private func presentFinishToast() {
        finishToastTask?.cancel()
        finishToastText = appLanguage.text("러닝 기록이 저장됐어요.", "Run saved.")

        finishToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            finishToastText = nil
        }
    }

    private func finishToastView(text: String) -> some View {
        Text(text)
            .font(RBFont.label(13))
            .foregroundStyle(RBColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(RBColor.warning.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
    }

    private func record(for id: UUID) -> RunRecord? {
        runSession.savedRecords.first { $0.id == id }
    }

    private func runRecordCard(_ record: RunRecord) -> some View {
        HStack(spacing: 14) {
            // 날짜 뱃지
            VStack(spacing: 2) {
                Text(record.startDate.formatted(.dateTime.month(.abbreviated)))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .textCase(.uppercase)
                Text(record.startDate.formatted(.dateTime.day()))
                    .font(RBFont.metric(22))
                    .foregroundStyle(RBColor.textPrimary)
            }
            .frame(width: 48)

            // 구분선
            Rectangle()
                .fill(RBColor.divider)
                .frame(width: 1, height: 40)

            // 데이터
            VStack(alignment: .leading, spacing: 6) {
                Text(record.formattedDistance)
                    .font(RBFont.metric(20))
                    .foregroundStyle(RBColor.textPrimary)
                HStack(spacing: 14) {
                    Label(record.formattedPace, systemImage: "speedometer")
                    Label(record.formattedDuration, systemImage: "clock")
                }
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textSecondary)
            }

            Spacer()

            if record.targetPace != nil {
                LaserDot(size: 10, glowRadius: 6)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RBColor.textTertiary)
        }
        .padding(14)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Calendar Data

    private func seedVisibleMonthIfNeeded() {
        guard !didSeedVisibleMonth, let latestDate = sortedRecords.first?.startDate else { return }
        visibleMonth = startOfMonth(for: latestDate)
        didSeedVisibleMonth = true
    }

    private func buildCalendarMap(from records: [RunRecord]) -> [Date: HistoryCalendarDaySummary] {
        records.reduce(into: [:]) { map, record in
            let key = calendar.startOfDay(for: record.startDate)
            var summary = map[key, default: .empty]
            summary.count += 1
            summary.totalDistanceMeters += record.totalDistanceMeters
            summary.elapsedSeconds += record.elapsedSeconds
            map[key] = summary
        }
    }

    private func monthCells(for monthStart: Date) -> [HistoryMonthCell] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let mondayOffset = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -mondayOffset, to: monthStart) else {
            return []
        }

        return (0..<42).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            return HistoryMonthCell(
                dayStart: dayStart,
                isCurrentMonth: calendar.isDate(dayStart, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    private func summaryForMonth(records: [RunRecord], monthStart: Date) -> HistoryCalendarDaySummary {
        records.reduce(into: .empty) { summary, record in
            guard calendar.isDate(record.startDate, equalTo: monthStart, toGranularity: .month) else { return }
            summary.count += 1
            summary.totalDistanceMeters += record.totalDistanceMeters
            summary.elapsedSeconds += record.elapsedSeconds
        }
    }

    private func currentStreak(from records: [RunRecord]) -> Int {
        let uniqueDates = Array(Set(records.map { calendar.startOfDay(for: $0.startDate) })).sorted(by: >)
        guard !uniqueDates.isEmpty else { return 0 }

        var streak = 1
        for index in 1..<uniqueDates.count {
            let previous = uniqueDates[index - 1]
            let current = uniqueDates[index]
            let diff = calendar.dateComponents([.day], from: current, to: previous).day ?? 0
            if diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    private func changeMonth(by amount: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: amount, to: visibleMonthStart) else { return }
        monthSlideDirection = amount >= 0 ? 1 : -1

        withAnimation(.easeInOut(duration: 0.24)) {
            visibleMonth = nextMonth
            selectedDate = nil
        }
    }

    private func selectDate(_ date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        let isOutsideVisibleMonth = !calendar.isDate(dayStart, equalTo: visibleMonthStart, toGranularity: .month)

        if isOutsideVisibleMonth {
            monthSlideDirection = dayStart > visibleMonthStart ? 1 : -1
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            if isOutsideVisibleMonth {
                visibleMonth = startOfMonth(for: dayStart)
            }

            if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: dayStart) {
                self.selectedDate = nil
            } else {
                self.selectedDate = dayStart
            }
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 48, abs(horizontal) > abs(vertical) else { return }
                changeMonth(by: horizontal < 0 ? 1 : -1)
            }
    }

    private var monthTransition: AnyTransition {
        let insertion: Edge = monthSlideDirection >= 0 ? .trailing : .leading
        let removal: Edge = monthSlideDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    // MARK: - Formatting

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLanguage.locale
        formatter.dateFormat = appLanguage.isEnglish ? "MMMM yyyy" : "yyyy년 M월"
        return formatter.string(from: date)
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLanguage.locale
        formatter.dateFormat = appLanguage.isEnglish ? "MMM d, EEE" : "M월 d일 EEE"
        return formatter.string(from: date)
    }

    private func monthSummaryText(_ summary: HistoryCalendarDaySummary) -> String {
        appLanguage.text(
            "월간 \(distanceText(summary.totalDistanceMeters)) · \(summary.count)회",
            "\(distanceText(summary.totalDistanceMeters)) · \(summary.count) runs"
        )
    }

    private func distanceText(_ meters: Double) -> String {
        String(format: "%.1fkm", meters / 1000.0)
    }

    private func accessibilityLabel(for date: Date, summary: HistoryCalendarDaySummary?) -> String {
        guard let summary else { return dateLabel(for: date) }
        return appLanguage.text(
            "\(dateLabel(for: date)), \(summary.count)회, \(distanceText(summary.totalDistanceMeters))",
            "\(dateLabel(for: date)), \(summary.count) runs, \(distanceText(summary.totalDistanceMeters))"
        )
    }

    // MARK: - Styling

    private func dayTextColor(isCurrentMonth: Bool, isSelected: Bool, hasRun: Bool) -> Color {
        if isSelected {
            return RBColor.warning
        }
        if hasRun {
            return RBColor.textPrimary
        }
        return isCurrentMonth ? RBColor.textSecondary : RBColor.textTertiary
    }

    private func dayBackgroundColor(isSelected: Bool, hasRun: Bool) -> Color {
        if isSelected {
            return RBColor.warning.opacity(0.12)
        }
        return hasRun ? RBColor.warning.opacity(0.045) : Color.clear
    }

    private func dayBorderColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return RBColor.warning
        }
        if isToday {
            return RBColor.textTertiary.opacity(0.42)
        }
        return Color.clear
    }

    private func intensityColor(for totalDistanceMeters: Double) -> Color {
        if totalDistanceMeters >= 10_000 {
            return Color(red: 1.0, green: 0.36, blue: 0.05)
        }
        if totalDistanceMeters >= 5_000 {
            return Color(red: 1.0, green: 0.54, blue: 0.12)
        }
        return Color(red: 1.0, green: 0.70, blue: 0.42)
    }
}

private struct HistoryCalendarDaySummary {
    var count: Int
    var totalDistanceMeters: Double
    var elapsedSeconds: TimeInterval

    static let empty = HistoryCalendarDaySummary(count: 0, totalDistanceMeters: 0, elapsedSeconds: 0)
}

private struct HistoryMonthCell: Identifiable {
    let dayStart: Date
    let isCurrentMonth: Bool

    var id: Date {
        dayStart
    }
}

#Preview {
    RunHistoryView()
        .environmentObject(RunSessionManager())
}
