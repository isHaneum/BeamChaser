import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var healthKit: HealthKitService
    @State private var showSettings = false
    @State private var showBadgeToast = false
    @State private var toastBadge: RunBadge?
    @State private var showNicknameSheet = false
    @State private var nicknameInput = ""
    @State private var showBadgeExplorer = false
    @State private var profilePhotoItem: PhotosPickerItem?
    @State private var profilePhotoUIImage: UIImage?
    @State private var remoteProfileImage: UIImage?
    @State private var isUploadingPhoto = false
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

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
                }
                .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
            }
            .navigationTitle(appLanguage.text("프로필", "Profile"))
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
            .navigationDestination(isPresented: $showBadgeExplorer) {
                BadgeCollectionView()
            }
            .sheet(isPresented: $showNicknameSheet) {
                nicknameSetupSheet
            }
            .overlay(alignment: .top) {
                if showBadgeToast, let badge = toastBadge {
                    badgeToastView(badge: badge)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .onAppear {
                authService.signInError = nil
                authService.isAuthenticating = false  // 이전 시도에서 stuck된 경우 리셋
                profileService.evaluateAfterRun(records: runSession.savedRecords)
                // HealthKit에서 키 자동 가져오기
                if healthKit.isAuthorized, let hkHeight = healthKit.userHeightCm {
                    let stored = UserDefaults.standard.integer(forKey: "userHeightCm")
                    if stored == 0 || stored == 170 {
                        UserDefaults.standard.set(hkHeight, forKey: "userHeightCm")
                    }
                }
                // 백엔드 프로필 사진 다운로드
                if let urlStr = backendService.currentUser?.photoURL,
                   let url = URL(string: urlStr) {
                    Task {
                        if let (data, _) = try? await URLSession.shared.data(from: url),
                           let img = UIImage(data: data) {
                            remoteProfileImage = img
                        }
                    }
                }
            }
            .onChange(of: profileService.newlyEarnedBadge) { _, newBadge in
                if let badge = newBadge {
                    toastBadge = badge
                    withAnimation(.spring(response: 0.5)) {
                        showBadgeToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showBadgeToast = false }
                        // 다음 뱃지가 있으면 연속 표시
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let next = profileService.pendingBadges.first {
                                profileService.pendingBadges.removeFirst()
                                profileService.newlyEarnedBadge = next
                            } else {
                                profileService.newlyEarnedBadge = nil
                            }
                        }
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

            Text(appLanguage.localized("로그인하고 기록을 저장하세요"))
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textSecondary)

            LocalizedAppleSignInButton(
                title: appLanguage.text("Apple로 로그인", "Sign in with Apple"),
                height: 50,
                cornerRadius: 12,
                isAuthenticating: authService.isAuthenticating
            ) { request in
                authService.prepareAppleSignInRequest(request)
            } onCompletion: { result in
                Task {
                    await authService.handleSignInResult(result, backendService: backendService)
                    if authService.isSignedIn {
                        if let name = authService.userName {
                            profileService.nickname = name
                        }
                        if profileService.nickname == "러너" || profileService.nickname.isEmpty {
                            nicknameInput = authService.userName ?? ""
                            showNicknameSheet = true
                        }
                    }
                }
            }

            if authService.isGoogleSignInAvailable {
                GoogleBrandedSignInButton(
                    title: appLanguage.text("Google로 로그인", "Sign in with Google"),
                    height: 50,
                    cornerRadius: 12,
                    isAuthenticating: authService.isAuthenticating
                ) {
                    Task {
                        await authService.signInWithGoogle(backendService: backendService)
                        if authService.isSignedIn {
                            if let name = authService.userName {
                                profileService.nickname = name
                            }
                            if profileService.nickname == "러너" || profileService.nickname.isEmpty {
                                nicknameInput = authService.userName ?? ""
                                showNicknameSheet = true
                            }
                        }
                    }
                }
            }

            if authService.isAuthenticating {
                ProgressView()
                    .tint(RBColor.accent)
            }

            if let error = authService.signInError {
                Text(error)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 프로필 헤더

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // 프로필 사진 + 선택기
            PhotosPicker(selection: $profilePhotoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    if let img = profilePhotoUIImage ?? remoteProfileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [RBColor.accent, RBColor.accent.opacity(0.6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(String((authService.userName ?? profileService.nickname).prefix(1)))
                                    .font(RBFont.hero(32))
                                    .foregroundStyle(RBColor.textPrimary)
                            }
                    }

                    // 업로드 스피너 or 카메라 아이콘
                    ZStack {
                        Circle()
                            .fill(RBColor.accent)
                            .frame(width: 24, height: 24)
                        if isUploadingPhoto {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .offset(x: 2, y: 2)
                }
            }
            .onChange(of: profilePhotoItem) { _, newItem in
                Task {
                    guard let data = try? await newItem?.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return }
                    profilePhotoUIImage = uiImage
                    isUploadingPhoto = true
                    _ = try? await backendService.uploadProfilePhoto(uiImage)
                    isUploadingPhoto = false
                }
            }

            Text(authService.userName ?? profileService.nickname)
                .font(RBFont.label(20))
                .foregroundStyle(RBColor.textPrimary)
                .onTapGesture {
                    nicknameInput = authService.userName ?? profileService.nickname
                    showNicknameSheet = true
                }

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
                    Text(appLanguage.text("\(profileService.currentStreak)일 연속", "\(profileService.currentStreak)-day streak"))
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
        let currentXP = profileService.experiencePoints
        let currentFloor = current.minimumXP
        let nextXP = nextLevel?.minimumXP
        let progress: Double = {
            guard let nextXP else { return 1.0 }
            let required = max(1, nextXP - currentFloor)
            return min(1.0, Double(currentXP - currentFloor) / Double(required))
        }()

        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage.text("러너 레벨", "Runner Level"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(appLanguage.text("레벨 \(current.rank)", "LV.\(current.rank)"))
                            .font(RBFont.metric(16))
                            .foregroundStyle(levelColor(current))
                        Text(current.localizedName(appLanguage))
                            .font(RBFont.hero(24))
                            .foregroundStyle(levelColor(current))
                    }
                    Text(appLanguage.text("\(currentXP) 경험치", "\(currentXP) XP"))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: current.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(levelColor(current))
                        .shadow(color: levelColor(current).opacity(0.5), radius: 8)

                    if let nextLevel, let nextXP {
                        Text(appLanguage.text("다음: \(nextLevel.localizedName(appLanguage)) · \(max(0, nextXP - currentXP)) 경험치", "Next: \(nextLevel.localizedName(appLanguage)) · \(max(0, nextXP - currentXP)) XP"))
                            .font(RBFont.caption(10))
                            .foregroundStyle(RBColor.textTertiary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text(appLanguage.text("\(currentXP) 경험치", "\(currentXP) XP"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textPrimary)
                    Spacer()
                    if let nextXP {
                        Text(appLanguage.text("\(nextXP) 경험치", "\(nextXP) XP"))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textTertiary)
                    } else {
                        Text(appLanguage.text("최고 단계", "Max"))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.accent)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 10)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [levelColor(current), levelColor(current).opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, geo.size.width * progress), height: 10)
                    }
                }
                .frame(height: 10)
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
                Text(appLanguage.text("이번 달 목표", "Monthly Goals"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()

                let month = Calendar.current.component(.month, from: Date())
                Text(appLanguage.text("\(month)월", "Month \(month)"))
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 20) {
                // 러닝 횟수
                goalRing(
                    current: Double(progress.runs),
                    target: Double(goal.targetRunCount),
                    label: "러닝",
                    valueText: appLanguage.text("\(progress.runs)/\(goal.targetRunCount)회", "\(progress.runs)/\(goal.targetRunCount) runs"),
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
            Text(appLanguage.localized(label))
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
        let featuredBadges = Array(allBadgeTypes.prefix(16))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appLanguage.text("뱃지 컬렉션", "Badge Collection"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1)
                Spacer()
                Text("\(earnedBadges.count)/\(allBadgeTypes.count)")
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(featuredBadges, id: \.rawValue) { type in
                    let isEarned = earnedBadges.contains { $0.id == type.rawValue }
                    badgeCell(type: type, isEarned: isEarned)
                }
            }

            Button {
                showBadgeExplorer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                    Text(appLanguage.localized("업적 보기"))
                        .font(RBFont.label(13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(RBColor.textPrimary)
                .padding(14)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func badgeCell(type: BadgeType, isEarned: Bool) -> some View {
        VStack(spacing: 6) {
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
            Text(appLanguage.text("누적 통계", "Lifetime Stats"))
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)

            HStack(spacing: 0) {
                statBlock(label: "총 러닝", value: "\(records.count)", unit: appLanguage.text("회", "runs"))
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
                statBlock(label: "연속 일수", value: "\(profileService.currentStreak)", unit: appLanguage.text("일", "days"))
            }

            // 로그아웃
            if authService.isSignedIn {
                Divider().overlay(RBColor.divider)
                Button {
                    authService.signOut(backendService: backendService)
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 13))
                        Text(appLanguage.localized("로그아웃"))
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
            Text(appLanguage.localized(label))
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

    // MARK: - 뱃지 획득 토스트

    private func badgeToastView(badge: RunBadge) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RBColor.accent.opacity(0.25))
                    .frame(width: 44, height: 44)
                Image(systemName: badge.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(RBColor.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appLanguage.localized("뱃지 획득!"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.accent)
                Text(badge.name)
                    .font(RBFont.label(15))
                    .foregroundStyle(.white)
                Text(badge.description)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RBColor.accent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 닉네임 설정 시트

    private var nicknameSetupSheet: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(RBColor.accent.opacity(0.2))
                                .frame(width: 80, height: 80)
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(RBColor.accent)
                        }

                        Text(appLanguage.localized("닉네임 설정"))
                            .font(RBFont.label(20))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(appLanguage.localized("다른 러너들에게 보여질 이름이에요"))
                            .font(RBFont.caption(13))
                            .foregroundStyle(RBColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField(appLanguage.localized("닉네임 입력"), text: $nicknameInput)
                            .font(RBFont.label(17))
                            .padding(14)
                            .background(RBColor.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(nicknameInput.count > 12 ? Color.red.opacity(0.5) : RBColor.divider, lineWidth: 1)
                            )

                        HStack {
                            if nicknameInput.count > 12 {
                                Text(appLanguage.localized("12자 이내로 입력해주세요"))
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.danger)
                            }
                            Spacer()
                            Text("\(nicknameInput.count)/12")
                                .font(RBFont.caption(11))
                                .foregroundStyle(nicknameInput.count > 12 ? RBColor.danger : RBColor.textTertiary)
                        }
                    }
                    .padding(.horizontal, 24)

                    Button {
                        let trimmed = nicknameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed.count <= 12 {
                            profileService.nickname = trimmed
                            authService.userName = trimmed
                            UserDefaults.standard.set(trimmed, forKey: "apple_user_name")
                            // Firebase에 동기화
                            backendService.currentUser?.displayName = trimmed
                            Task {
                                await backendService.updateUserProfile(["displayName": trimmed])
                            }
                            showNicknameSheet = false
                        }
                    } label: {
                        Text(appLanguage.localized("저장"))
                            .font(RBFont.label(16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                nicknameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nicknameInput.count > 12
                                ? RBColor.accent.opacity(0.3)
                                : RBColor.accent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(nicknameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nicknameInput.count > 12)
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLanguage.localized("취소")) { showNicknameSheet = false }
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum BadgeExplorerFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case milestone = "성장"
    case distance = "거리"
    case pace = "페이스"
    case routine = "루틴"
    case special = "스페셜"

    var id: String { rawValue }

    var category: BadgeCategory? {
        switch self {
        case .all: return nil
        case .milestone: return .milestone
        case .distance: return .distance
        case .pace: return .pace
        case .routine: return .routine
        case .special: return .special
        }
    }
}

struct BadgeCollectionView: View {
    @EnvironmentObject private var profileService: ProfileService
    @State private var selectedFilter: BadgeExplorerFilter = .all
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var earnedBadgeIds: Set<String> {
        Set(profileService.badges.filter(\.isEarned).map(\.id))
    }

    private var filteredBadges: [BadgeType] {
        guard let category = selectedFilter.category else {
            return BadgeType.allCases
        }
        return BadgeType.allCases.filter { $0.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                filterStrip
                categoryProgressStrip

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filteredBadges, id: \.rawValue) { type in
                        badgeDetailCard(type)
                    }
                }
            }
            .padding(16)
        }
        .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
        .background(RBColor.bg.ignoresSafeArea())
        .navigationTitle(appLanguage.localized("업적"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        let current = profileService.level
        let next = current.next
        let currentXP = profileService.experiencePoints
        let currentFloor = current.minimumXP
        let nextXP = next?.minimumXP
        let progress: Double = {
            guard let nextXP else { return 1.0 }
            let required = max(1, nextXP - currentFloor)
            return min(1.0, Double(currentXP - currentFloor) / Double(required))
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLanguage.text("업적", "Achievements"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1)
                    Text(appLanguage.text("레벨 \(current.rank) \(current.localizedName(appLanguage))", "LV.\(current.rank) \(current.localizedName(appLanguage))"))
                        .font(RBFont.hero(24))
                        .foregroundStyle(levelColor(current))
                    Text(appLanguage.text("업적 \(earnedBadgeIds.count)개 · \(currentXP) XP", "\(earnedBadgeIds.count) achievements · \(currentXP) XP"))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(levelColor(current).opacity(0.18))
                        .frame(width: 58, height: 58)
                    Image(systemName: current.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(levelColor(current))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 10)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [levelColor(current), levelColor(current).opacity(0.65)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * progress), height: 10)
                }
            }
            .frame(height: 10)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [RBColor.cardBg, levelColor(profileService.level).opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BadgeExplorerFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let category = filter.category {
                                Image(systemName: category.icon)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(appLanguage.localized(filter.rawValue))
                                .font(RBFont.label(12))
                        }
                        .foregroundStyle(selectedFilter == filter ? .white : RBColor.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selectedFilter == filter ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? Color.white.opacity(0.08) : RBColor.divider.opacity(0.8), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryProgressStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BadgeCategory.allCases) { category in
                    let total = BadgeType.allCases.filter { $0.category == category }.count
                    let earned = BadgeType.allCases.filter { $0.category == category && earnedBadgeIds.contains($0.rawValue) }.count

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(RBColor.accent)
                            Text(category.rawValue)
                                .font(RBFont.label(12))
                                .foregroundStyle(RBColor.textPrimary)
                        }
                        Text("\(earned)/\(total)")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    .padding(12)
                    .frame(width: 108, alignment: .leading)
                    .background(RBColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func badgeDetailCard(_ type: BadgeType) -> some View {
        let earnedBadge = profileService.badges.first(where: { $0.id == type.rawValue && $0.isEarned })
        let isEarned = earnedBadge != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(isEarned ? RBColor.accent.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 46, height: 46)

                    Image(systemName: type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isEarned ? RBColor.accent : RBColor.textTertiary.opacity(0.6))
                }

                Spacer()

                Text(isEarned ? appLanguage.localized("획득") : appLanguage.localized("잠김"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(isEarned ? RBColor.accent : RBColor.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isEarned ? RBColor.accent.opacity(0.14) : Color.white.opacity(0.06)))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(type.name)
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textPrimary)
                Text(type.description)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let earnedDate = earnedBadge?.earnedDate {
                Text(earnedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RBColor.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isEarned ? RBColor.accent.opacity(0.3) : RBColor.divider.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(isEarned ? 1.0 : 0.82)
    }

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
        .environmentObject(BackendService())
        .environmentObject(HealthKitService())
}
