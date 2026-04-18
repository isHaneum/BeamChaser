import SwiftUI
import CoreLocation
import UIKit

// MARK: - 온보딩 뷰 (최초 실행 시 1회만 노출)

struct OnboardingView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var healthKit: HealthKitService
    @Environment(\.openURL) private var openURL

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // MARK: - 페이지 상태

    @State private var page: OnboardingPage = .welcome

    // MARK: - 법적 동의 상태

    @State private var agreePrivacy    = false
    @State private var agreeLocation   = false
    @State private var agreeHealth     = false
    @State private var agreeMarketing  = false
    @State private var showPrivacyDetail  = false
    @State private var showLocationDetail = false
    @State private var showHealthDetail   = false

    // MARK: - 권한 요청 상태

    @State private var locationRequested = false
    @State private var healthRequested   = false

    // MARK: - 페이지 정의

    enum OnboardingPage: Int, CaseIterable {
        case welcome = 0
        case featureGPS
        case featureLaser
        case featureCommunity
        case legal
        case permissions

        var isFeaturePage: Bool {
            self == .featureGPS || self == .featureLaser || self == .featureCommunity
        }
    }

    // MARK: - 필수 동의 여부

    private var requiredConsentsGiven: Bool {
        agreePrivacy && agreeLocation && agreeHealth
    }

    private var allConsentsGiven: Bool {
        agreePrivacy && agreeLocation && agreeHealth && agreeMarketing
    }

    private let onboardingCardBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    private let onboardingCardHighlight = Color(red: 0.17, green: 0.17, blue: 0.20)
    private let onboardingStroke = Color.white.opacity(0.10)
    private let onboardingTextPrimary = Color.white
    private let onboardingTextSecondary = Color(white: 0.84)
    private let onboardingTextMuted = Color(white: 0.62)

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 건너뛰기 (기능 소개 페이지에서만)
                HStack {
                    Spacer()
                    if page.isFeaturePage {
                        Button("건너뛰기") {
                            withAnimation(.easeInOut(duration: 0.3)) { page = .legal }
                        }
                        .font(RBFont.caption(13))
                        .foregroundStyle(RBColor.textTertiary)
                        .padding(.trailing, 24)
                    }
                }
                .frame(height: 44)

                // 페이지 내용
                pageContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 페이지 인디케이터
                if page != .welcome {
                    pageIndicator
                        .padding(.bottom, 16)
                }

                // CTA 버튼
                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
    }

    // MARK: - 페이지 라우터

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome:
            welcomePage
        case .featureGPS:
            featurePage(
                icon: "location.fill",
                color: Color(red: 0.2, green: 0.8, blue: 0.5),
                title: "GPS 스마트 트래킹",
                body: "실시간으로 경로·페이스·거리를 자동 기록합니다.\nCoreLocation과 보수계 센서를 융합한 정밀 측정 기술로 더 정확한 러닝 데이터를 제공합니다."
            )
        case .featureLaser:
            featurePage(
                icon: "waveform.path.ecg",
                color: Color(red: 1.0, green: 0.3, blue: 0.3),
                title: "레이저 페이스메이커",
                body: "Bluetooth로 연결된 RunBeam 장치가 목표 페이스에 맞춰 레이저 마커를 실시간으로 조절합니다.\n앞으로 나아가야 할 거리를 눈으로 직접 확인하세요."
            )
        case .featureCommunity:
            featurePage(
                icon: "person.2.fill",
                color: RBColor.accent,
                title: "러닝 커뮤니티",
                body: "같은 목표를 가진 러너와 메이트를 구하고,\n나의 러닝 기록을 피드에 공유해보세요.\n함께 뛰면 더 멀리 갈 수 있습니다."
            )
        case .legal:
            legalPage
        case .permissions:
            permissionsPage
        }
    }

    // MARK: - Welcome 페이지

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            // 앱 아이콘 영역
            ZStack {
                Circle()
                    .fill(RBColor.accent.opacity(0.08))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(RBColor.accent.opacity(0.14))
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(RBColor.accent.opacity(0.22))
                    .frame(width: 90, height: 90)
                Image(systemName: "figure.run")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(RBColor.accent)
            }

            VStack(spacing: 10) {
                Text("RunBeam")
                    .font(RBFont.hero(42))
                    .foregroundStyle(.white)
                Text("러닝의 새로운 기준")
                    .font(RBFont.label(17))
                    .foregroundStyle(RBColor.textSecondary)
            }

            VStack(spacing: 8) {
                featurePill(icon: "location.fill",  text: "GPS 스마트 트래킹")
                featurePill(icon: "waveform.path.ecg", text: "레이저 페이스메이커")
                featurePill(icon: "person.2.fill",  text: "러닝 커뮤니티")
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(RBColor.accent)
                .frame(width: 24)
            Text(text)
                .font(RBFont.caption(14))
                .foregroundStyle(onboardingTextSecondary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RBColor.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(onboardingCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingStroke, lineWidth: 1)
        )
    }

    // MARK: - Feature 페이지 (공통)

    private func featurePage(icon: String, color: Color, title: String, body: String) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 90, height: 90)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(spacing: 14) {
                Text(title)
                    .font(RBFont.hero(26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(body)
                    .font(RBFont.caption(15))
                    .foregroundStyle(onboardingTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: - 법적 동의 페이지

    private var legalPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // 제목
                VStack(alignment: .leading, spacing: 6) {
                    Text("서비스 이용 약관")
                        .font(RBFont.hero(24))
                        .foregroundStyle(.white)
                    Text("RunBeam 서비스 이용을 위해 아래 약관에 동의해주세요.\n필수 항목 전체 동의 후 다음 단계로 진행할 수 있습니다.")
                        .font(RBFont.caption(12))
                        .foregroundStyle(onboardingTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 전체 동의 버튼
                Button {
                    let target = !allConsentsGiven
                    agreePrivacy   = target
                    agreeLocation  = target
                    agreeHealth    = target
                    agreeMarketing = target
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            checkIcon(allConsentsGiven)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("전체 동의 (선택 포함)")
                                    .font(RBFont.label(16))
                                    .foregroundStyle(onboardingTextPrimary)
                                Text("필수 3개와 선택 1개를 한 번에 설정합니다.")
                                    .font(RBFont.caption(12))
                                    .foregroundStyle(onboardingTextSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            consentCountBadge(label: "필수", value: "3")
                            consentCountBadge(label: "선택", value: "1")
                        }
                    }
                    .padding(16)
                    .background(allConsentsGiven ? onboardingCardHighlight : onboardingCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(allConsentsGiven ? RBColor.accent.opacity(0.45) : onboardingStroke, lineWidth: 1)
                    )
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                // 항목별 동의
                VStack(spacing: 10) {
                    legalItem(
                        agreed: $agreePrivacy,
                        required: true,
                        title: "개인정보 처리방침 동의",
                        summary: "회원가입 및 서비스 제공을 위해 성명, 이메일, 운동 기록 등 개인정보를 수집·이용합니다.",
                        detail: privacyPolicyText,
                        showDetail: $showPrivacyDetail
                    )

                    legalItem(
                        agreed: $agreeLocation,
                        required: true,
                        title: "위치정보 수집·이용 동의",
                        summary: "러닝 경로 추적, 지도 표시, 러닝 메이트 찾기를 위해 위치 정보를 수집합니다. 백그라운드에서도 사용될 수 있습니다.",
                        detail: locationPolicyText,
                        showDetail: $showLocationDetail
                    )

                    legalItem(
                        agreed: $agreeHealth,
                        required: true,
                        title: "건강 데이터 수집·이용 동의",
                        summary: "운동 기록(거리, 칼로리, 심박수 등)을 Apple 건강 앱에 저장하고 읽기 위해 HealthKit 접근 권한이 필요합니다.",
                        detail: healthPolicyText,
                        showDetail: $showHealthDetail
                    )

                    legalItem(
                        agreed: $agreeMarketing,
                        required: false,
                        title: "마케팅 정보 수신 동의",
                        summary: "RunBeam의 새 기능, 이벤트, 업데이트 정보를 알림으로 받을 수 있습니다.",
                        detail: nil,
                        showDetail: .constant(false)
                    )
                }

                // 미동의 안내
                if !requiredConsentsGiven {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(RBColor.accent)
                        Text("필수 항목에 모두 동의해야 서비스를 이용할 수 있습니다.")
                            .font(RBFont.caption(11))
                            .foregroundStyle(onboardingTextMuted)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 44)
        }
    }

    private func legalItem(
        agreed: Binding<Bool>,
        required: Bool,
        title: String,
        summary: String,
        detail: String?,
        showDetail: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button { agreed.wrappedValue.toggle() } label: {
                    checkIcon(agreed.wrappedValue)
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(RBFont.label(14))
                            .foregroundStyle(onboardingTextPrimary)
                        requiredBadge(required)
                    }
                    Text(summary)
                        .font(RBFont.caption(12))
                        .foregroundStyle(onboardingTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if detail != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDetail.wrappedValue.toggle()
                        }
                    } label: {
                        Image(systemName: showDetail.wrappedValue ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(onboardingTextSecondary)
                    }
                }
            }
            .padding(16)

            // 전문 펼치기
            if showDetail.wrappedValue, let detail {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                ScrollView(showsIndicators: false) {
                    Text(detail)
                        .font(RBFont.caption(11))
                        .foregroundStyle(onboardingTextMuted)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(onboardingCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(onboardingStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func requiredBadge(_ required: Bool) -> some View {
        if required {
            Text("필수")
                .font(RBFont.caption(9))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RBColor.accent)
                .clipShape(Capsule())
        } else {
            Text("선택")
                .font(RBFont.caption(9))
                .foregroundStyle(onboardingTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(onboardingCardHighlight)
                .clipShape(Capsule())
        }
    }

    private func consentCountBadge(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(RBFont.caption(10))
            Text(value)
                .font(RBFont.label(11))
        }
        .foregroundStyle(onboardingTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func checkIcon(_ checked: Bool) -> some View {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .foregroundStyle(checked ? RBColor.accent : onboardingTextMuted)
    }

    // MARK: - 권한 요청 페이지

    private var permissionsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("권한 설정")
                        .font(RBFont.hero(26))
                        .foregroundStyle(.white)
                    Text("RunBeam이 제대로 동작하려면\n아래 권한이 필요합니다.")
                        .font(RBFont.caption(14))
                        .foregroundStyle(onboardingTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(spacing: 12) {
                    permissionCard(
                        icon: "location.fill",
                        color: Color(red: 0.2, green: 0.6, blue: 1.0),
                        title: "위치 권한",
                        description: "러닝 경로를 기록하고 근처 러너를 찾기 위해 필요합니다.\n백그라운드 기록은 iOS에서 별도 허용한 경우에만 사용됩니다.",
                        isGranted: locationService.authorizationStatus == .authorizedWhenInUse
                                  || locationService.authorizationStatus == .authorizedAlways,
                        buttonTitle: locationPermissionButtonTitle,
                        buttonEmphasis: locationPermissionButtonEmphasis
                    ) {
                        handleLocationPermission()
                    }

                    permissionCard(
                        icon: "heart.fill",
                        color: Color(red: 1.0, green: 0.25, blue: 0.35),
                        title: "건강 데이터 권한",
                        description: "운동 기록(거리, 칼로리, 심박수)을 Apple 건강 앱에 저장하고 불러오기 위해 필요합니다.",
                        isGranted: healthKit.isAuthorized,
                        buttonTitle: healthPermissionButtonTitle,
                        buttonEmphasis: healthPermissionButtonEmphasis
                    ) {
                        handleHealthPermission()
                    }
                }

                if let authorizationError = healthKit.authorizationError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.accent)
                        Text(authorizationError)
                            .font(RBFont.caption(12))
                            .foregroundStyle(onboardingTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(14)
                    .background(onboardingCardHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(onboardingStroke, lineWidth: 1)
                    )
                }

                Text("권한은 나중에 설정 앱 → RunBeam에서 변경할 수 있습니다.")
                    .font(RBFont.caption(12))
                    .foregroundStyle(onboardingTextMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 56)
        }
    }

    private func permissionCard(
        icon: String,
        color: Color,
        title: String,
        description: String,
        isGranted: Bool,
        buttonTitle: String,
        buttonEmphasis: Bool,
        onRequest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(RBFont.label(15))
                        .foregroundStyle(onboardingTextPrimary)
                    Text(description)
                        .font(RBFont.caption(13))
                        .foregroundStyle(onboardingTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                permissionStatusPill(isGranted: isGranted)
                Spacer()
                Button(buttonTitle) { onRequest() }
                    .font(RBFont.label(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        buttonEmphasis
                            ? AnyShapeStyle(RBColor.accentGradient)
                            : AnyShapeStyle(onboardingCardHighlight)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(buttonEmphasis ? Color.white.opacity(0.08) : onboardingStroke, lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .background(onboardingCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(onboardingStroke, lineWidth: 1)
        )
    }

    private func permissionStatusPill(isGranted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGranted ? RBColor.success : onboardingTextMuted)
                .frame(width: 8, height: 8)
            Text(isGranted ? "ON" : "OFF")
                .font(RBFont.label(12))
        }
        .foregroundStyle(isGranted ? RBColor.success : onboardingTextSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isGranted ? RBColor.success.opacity(0.10) : Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    private var locationPermissionButtonTitle: String {
        let status = locationService.authorizationStatus
        if status == .authorizedAlways {
            return "설정"
        }
        if status == .authorizedWhenInUse {
            return "백그라운드 허용"
        }
        if status == .denied || status == .restricted {
            return "설정 열기"
        }
        return locationRequested ? "다시 요청" : "켜기"
    }

    private var locationPermissionButtonEmphasis: Bool {
        let status = locationService.authorizationStatus
        return !(status == .authorizedAlways || status == .authorizedWhenInUse)
    }

    private var healthPermissionButtonTitle: String {
        if healthKit.isAuthorized {
            return "설정"
        }
        return (healthRequested || healthKit.authorizationError != nil) ? "설정 열기" : "켜기"
    }

    private var healthPermissionButtonEmphasis: Bool {
        !healthKit.isAuthorized
    }

    private func handleLocationPermission() {
        let status = locationService.authorizationStatus
        if status == .denied || status == .restricted || status == .authorizedAlways {
            openAppSettings()
            return
        }
        locationService.requestPermission()
        locationRequested = true
    }

    private func handleHealthPermission() {
        if healthRequested || healthKit.authorizationError != nil || healthKit.isAuthorized {
            openAppSettings()
            return
        }
        Task {
            await healthKit.requestAuthorization()
            healthRequested = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - 페이지 인디케이터

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            // welcome 이후 페이지부터 표시 (index 1 ~ 5)
            ForEach(1..<OnboardingPage.allCases.count, id: \.self) { idx in
                let isActive = page.rawValue == idx
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? RBColor.accent : RBColor.textTertiary.opacity(0.35))
                    .frame(width: isActive ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }

    // MARK: - CTA 버튼

    @ViewBuilder
    private var ctaButton: some View {
        switch page {
        case .welcome:
            primaryButton("시작하기", icon: "arrow.right") {
                withAnimation(.easeInOut(duration: 0.3)) { page = .featureGPS }
            }

        case .featureGPS:
            primaryButton("다음") {
                withAnimation(.easeInOut(duration: 0.3)) { page = .featureLaser }
            }

        case .featureLaser:
            primaryButton("다음") {
                withAnimation(.easeInOut(duration: 0.3)) { page = .featureCommunity }
            }

        case .featureCommunity:
            primaryButton("약관 동의하기") {
                withAnimation(.easeInOut(duration: 0.3)) { page = .legal }
            }

        case .legal:
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { page = .permissions }
            } label: {
                Text("다음")
                    .font(RBFont.label(17))
                    .foregroundStyle(requiredConsentsGiven ? .white : onboardingTextMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        requiredConsentsGiven
                            ? AnyShapeStyle(RBColor.accentGradient)
                            : AnyShapeStyle(onboardingCardHighlight)
                    )
                    .clipShape(Capsule())
            }
            .disabled(!requiredConsentsGiven)

        case .permissions:
            primaryButton("RunBeam 시작하기") {
                // 마케팅 동의 저장
                UserDefaults.standard.set(agreeMarketing, forKey: "agreedMarketing")
                hasCompletedOnboarding = true
            }
        }
    }

    private func primaryButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(RBFont.label(17))
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RBColor.accentGradient)
            .clipShape(Capsule())
        }
    }

    // MARK: - 법률 전문 텍스트

    private var privacyPolicyText: String {
        LegalContent.privacyPolicy
    }

    private var locationPolicyText: String {
        LegalContent.locationPolicy
    }

    private var healthPolicyText: String {
        LegalContent.healthPolicy
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(LocationService())
        .environmentObject(HealthKitService())
}
