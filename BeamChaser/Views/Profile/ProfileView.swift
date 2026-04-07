import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var healthKit: HealthKitService
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if authService.isSignedIn {
                            profileHeader
                        } else {
                            signInSection
                        }
                        levelCard
                        monthlyGoalCard
                        badgeGrid
                        cumulativeStats
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                profileService.evaluateAfterRun(records: runSession.savedRecords)
                // HealthKit에서 키 자동 가져오기
                if healthKit.isAuthorized, let hkHeight = healthKit.userHeightCm {
                    let stored = UserDefaults.standard.integer(forKey: "userHeightCm")
                    if stored == 0 || stored == 170 {
                        UserDefaults.standard.set(hkHeight, forKey: "userHeightCm")
                    }
                }
            }
        }
    }

    // MARK: - Apple 로그인 섹션

    private var signInSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(RBColor.textTertiary)
            }

            Text("로그인하고 기록을 저장하세요")
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textSecondary)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                authService.handleSignInResult(result)
                if let name = authService.userName {
                    profileService.nickname = name
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 에러 메시지
            if let error = authService.signInError {
                Text(error)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            #if targetEnvironment(simulator)
            Button {
                authService.simulatorSignIn()
                profileService.nickname = authService.userName ?? "테스트"
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 13))
                    Text("시뮬레이터 테스트 로그인")
                        .font(RBFont.label(13))
                }
                .foregroundStyle(RBColor.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RBColor.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(RBColor.accent.opacity(0.3), lineWidth: 1)
                )
            }
            #endif
        }
        .padding(.top, 8)
    }

    // MARK: - 프로필 헤더

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [RBColor.accent, RBColor.accent.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Text(String((authService.userName ?? profileService.nickname).prefix(1)))
                    .font(RBFont.hero(32))
                    .foregroundStyle(RBColor.textPrimary)
            }

            Text(authService.userName ?? profileService.nickname)
                .font(RBFont.label(20))
                .foregroundStyle(RBColor.textPrimary)

            if let email = authService.userEmail {
                Text(email)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textTertiary)
            }

            // 스트릭
            if profileService.currentStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("\(profileService.currentStreak)일 연속")
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(RBColor.accent.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 레벨 카드

    private var levelCard: some View {
        let current = profileService.level
        let nextLevel = current.next
        let totalDist = runSession.savedRecords
            .filter { $0.totalDistanceMeters > 100 }
            .reduce(0.0) { $0 + $1.totalDistanceMeters / 1000.0 }

        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("러너 등급")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1)
                    Text(current.rawValue)
                        .font(RBFont.hero(24))
                        .foregroundStyle(levelColor(current))
                }

                Spacer()

                Image(systemName: current.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(levelColor(current))
                    .shadow(color: levelColor(current).opacity(0.5), radius: 8)
            }

            // 진행 바
            if let next = nextLevel {
                VStack(spacing: 6) {
                    HStack {
                        Text(String(format: "%.1f km", totalDist))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f km", next.requiredDistanceKm))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textTertiary)
                    }

                    GeometryReader { geo in
                        let progress = min(1.0, (totalDist - current.requiredDistanceKm) / (next.requiredDistanceKm - current.requiredDistanceKm))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 8)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [levelColor(current), levelColor(current).opacity(0.7)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * progress), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("다음 등급: \(next.rawValue)")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }
            } else {
                Text("최고 등급 달성! 🏆")
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.accent)
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 월간 목표

    private var monthlyGoalCard: some View {
        let progress = profileService.monthlyProgress(records: runSession.savedRecords)
        let goal = profileService.monthlyGoal

        return VStack(spacing: 14) {
            HStack {
                Text("이번 달 목표".uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()

                let month = Calendar.current.component(.month, from: Date())
                Text("\(month)월")
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 20) {
                // 러닝 횟수
                goalRing(
                    current: Double(progress.runs),
                    target: Double(goal.targetRunCount),
                    label: "러닝",
                    valueText: "\(progress.runs)/\(goal.targetRunCount)회",
                    color: RBColor.accent
                )

                // 거리
                goalRing(
                    current: progress.distanceKm,
                    target: goal.targetDistanceKm,
                    label: "거리",
                    valueText: String(format: "%.1f/%.0fkm", progress.distanceKm, goal.targetDistanceKm),
                    color: RBColor.success
                )
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func goalRing(current: Double, target: Double, label: String, valueText: String, color: Color) -> some View {
        let progress = target > 0 ? min(1.0, current / target) : 0

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))%")
                    .font(RBFont.metric(16))
                    .foregroundStyle(RBColor.textPrimary)
            }
            Text(label)
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
            Text(valueText)
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 뱃지 그리드

    private var badgeGrid: some View {
        let earnedBadges = profileService.badges.filter(\.isEarned)
        let allBadgeTypes = BadgeType.allCases

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("뱃지 컬렉션".uppercased())
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()
                Text("\(earnedBadges.count)/\(allBadgeTypes.count)")
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(allBadgeTypes, id: \.rawValue) { type in
                    let isEarned = earnedBadges.contains { $0.id == type.rawValue }
                    badgeCell(type: type, isEarned: isEarned)
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func badgeCell(type: BadgeType, isEarned: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isEarned ? RBColor.accent.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 52, height: 52)

                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isEarned ? RBColor.accent : RBColor.textTertiary.opacity(0.4))
            }
            Text(type.name)
                .font(RBFont.caption(9))
                .foregroundStyle(isEarned ? .white : RBColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - 누적 통계

    private var cumulativeStats: some View {
        let records = runSession.savedRecords.filter { $0.totalDistanceMeters > 100 }
        let totalDist = records.reduce(0.0) { $0 + $1.totalDistanceMeters / 1000.0 }
        let totalTime = records.reduce(0.0) { $0 + $1.elapsedSeconds }
        let avgPace = records.isEmpty ? 0 : records.map(\.averagePaceSecondsPerKm).reduce(0, +) / Double(records.count)
        let bestPace = records.map(\.averagePaceSecondsPerKm).filter { $0 > 0 }.min() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("누적 통계".uppercased())
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)

            HStack(spacing: 0) {
                statBlock(label: "총 러닝", value: "\(records.count)", unit: "회")
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statBlock(label: "총 거리", value: String(format: "%.1f", totalDist), unit: "km")
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statBlock(label: "총 시간", value: RunRecord.formatDuration(totalTime), unit: "")
            }

            Divider().overlay(RBColor.divider)

            HStack(spacing: 0) {
                statBlock(label: "평균 페이스", value: RunRecord.formatPace(avgPace), unit: "")
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statBlock(label: "최고 페이스", value: RunRecord.formatPace(bestPace), unit: "")
                Rectangle().fill(RBColor.divider).frame(width: 1, height: 36)
                statBlock(label: "연속 일수", value: "\(profileService.currentStreak)", unit: "일")
            }

            // 로그아웃
            if authService.isSignedIn {
                Divider().overlay(RBColor.divider)
                Button {
                    authService.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 13))
                        Text("로그아웃")
                            .font(RBFont.caption(12))
                    }
                    .foregroundStyle(RBColor.textTertiary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statBlock(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(0.5)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(RBFont.metric(16))
                    .foregroundStyle(RBColor.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(RBFont.caption(9))
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func levelColor(_ level: RunnerLevel) -> Color {
        switch level {
        case .starter: return .gray
        case .bronze: return Color(red: 0.72, green: 0.45, blue: 0.2)
        case .silver: return Color(white: 0.75)
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .laser: return RBColor.laserRed
        case .beam: return RBColor.accent
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileService())
        .environmentObject(RunSessionManager())
        .environmentObject(AuthService())
        .environmentObject(HealthKitService())
}
