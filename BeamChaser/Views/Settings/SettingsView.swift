import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var runSession: RunSessionManager
    @EnvironmentObject var voiceGuideService: VoiceGuideService
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("laserBrightness") private var laserBrightness: Double = 0.8
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("autoPause") private var autoPause = true
    @AppStorage("voiceGuide") private var voiceGuide = false
    @AppStorage("voiceDistanceInterval") private var voiceDistanceInterval: Double = 1.0
    @AppStorage("voicePaceAlertThreshold") private var voicePaceAlertThreshold: Double = 15.0
    @AppStorage("voiceCountdownAlert") private var voiceCountdownAlert = true
    @AppStorage("userHeightCm") private var userHeightCm: Int = 170
    @AppStorage("mountPosition") private var mountPositionRaw: String = LaserCalibration.MountPosition.chest.rawValue
    @AppStorage("laserAngleOffset") private var laserAngleOffset: Double = 0.0
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("appFontPreset") private var appFontPresetRaw: String = AppFontPreset.modern.rawValue
    @AppStorage("appColorTheme") private var appColorThemeRaw: String = AppColorTheme.beam.rawValue
    @AppStorage("dayMode") private var dayMode: Bool = false
    @AppStorage("reviewCheckBLEDevice") private var reviewCheckBLEDevice = false
    @AppStorage("reviewCheckLocationDevice") private var reviewCheckLocationDevice = false
    @AppStorage("reviewCheckHealthKitDevice") private var reviewCheckHealthKitDevice = false
    @AppStorage("reviewCheckPrivacyURL") private var reviewCheckPrivacyURL = false
    @AppStorage("reviewCheckAppPrivacyForm") private var reviewCheckAppPrivacyForm = false
    @State private var showHealthSetupGuide = false
    @State private var selectedLegalDocument: LegalDocumentKind?
    @State private var showDeleteAccountAlert = false
    @State private var showReviewChecklist = false
    @State private var isDeletingAccount = false
    @State private var accountNoticeMessage: String?
    @State private var deviceExpanded = true
    @State private var calibrationExpanded = false
    @State private var runningExpanded = false
    @State private var voiceExpanded = false
    @State private var healthExpanded = true
    @State private var privacyExpanded = false
    @State private var displayExpanded = false
    @State private var infoExpanded = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var isHealthDataAvailable: Bool {
        HealthKitService.isAvailable
    }

    private var permissionCopyConfigured: Bool {
        [
            "NSBluetoothAlwaysUsageDescription",
            "NSContactsUsageDescription",
            "NSHealthShareUsageDescription",
            "NSHealthUpdateUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
            "NSLocationWhenInUseUsageDescription",
            "NSMotionUsageDescription",
            "NSPhotoLibraryUsageDescription"
        ].allSatisfy { key in
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var googleURLSchemeConfigured: Bool {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = urlTypes?
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        return schemes.contains { $0.contains("com.googleusercontent.apps") }
    }

    private var policyDocumentsReady: Bool {
        LegalDocumentKind.allCases.count >= 4
    }

    private var automaticReviewChecks: [Bool] {
        [
            policyDocumentsReady,
            true,
            permissionCopyConfigured,
            googleURLSchemeConfigured
        ]
    }

    private var manualReviewChecks: [Bool] {
        [
            reviewCheckBLEDevice,
            reviewCheckLocationDevice,
            reviewCheckHealthKitDevice,
            reviewCheckPrivacyURL,
            reviewCheckAppPrivacyForm
        ]
    }

    private var reviewCompletionCount: Int {
        automaticReviewChecks.filter { $0 }.count + manualReviewChecks.filter { $0 }.count
    }

    private var reviewTotalCount: Int {
        automaticReviewChecks.count + manualReviewChecks.count
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    expandableSection(title: appLanguage.localized("BeamChaser 장치"), isExpanded: $deviceExpanded) {
                        VStack(spacing: 0) {
                            NavigationLink(destination: DeviceConnectionView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(bleService.isConnected ? RBColor.success : RBColor.accent)
                                        .frame(width: 32)
                                    Text(
                                        bleService.isConnected
                                        ? appLanguage.text(
                                            "연결됨: \(bleService.connectedDeviceName ?? "")",
                                            "Connected: \(bleService.connectedDeviceName ?? "")"
                                        )
                                        : appLanguage.text("장치 연결", "Connect Device")
                                    )
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(RBColor.textTertiary)
                                }
                                .padding(14)
                            }

                            // 배터리 상태 표시
                            if bleService.isConnected {
                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                HStack(spacing: 12) {
                                    Image(systemName: batteryIconName)
                                        .font(.system(size: 16))
                                        .foregroundStyle(batteryStatusColor)
                                        .frame(width: 32)
                                    Text(appLanguage.localized("배터리"))
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    if let status = bleService.deviceStatus {
                                        HStack(spacing: 6) {
                                            if status.isCharging {
                                                Image(systemName: "bolt.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(RBColor.success)
                                                Text(appLanguage.localized("충전 중"))
                                                    .font(RBFont.caption(12))
                                                    .foregroundStyle(RBColor.success)
                                            }
                                            // 배터리 바
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(width: 50, height: 8)
                                                Capsule()
                                                    .fill(batteryStatusColor)
                                                    .frame(width: max(4, 50 * CGFloat(status.batteryPercent) / 100), height: 8)
                                            }
                                            Text("\(status.batteryPercent)%")
                                                .font(RBFont.metric(14))
                                                .foregroundStyle(batteryStatusColor)
                                        }
                                    } else {
                                        Text(appLanguage.localized("불러오는 중..."))
                                            .font(RBFont.caption(12))
                                            .foregroundStyle(RBColor.textTertiary)
                                    }
                                }
                                .padding(14)
                            }

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            // 낮 점멸 모드: 10Hz 깜빡임으로 주간 레이저 가시성 향상
                            HStack(spacing: 12) {
                                Image(systemName: dayMode ? "sun.max.fill" : "moon.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(dayMode ? Color.yellow : RBColor.textSecondary)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appLanguage.localized("주간 모드 (레이저 점멸)"))
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text(appLanguage.localized("밝은 곳에서 레이저를 10Hz로 깜빡여 가시성 향상"))
                                        .font(RBFont.caption(12))
                                        .foregroundStyle(RBColor.textSecondary)
                                }
                                Spacer()
                                RBBarToggle(
                                    title: nil,
                                    isOn: $dayMode,
                                    tint: RBColor.warning,
                                    height: 32,
                                    onChange: { newValue in
                                        bleService.setDayMode(newValue)
                                    }
                                )
                                .frame(width: 86)
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("레이저 캘리브레이션"), isExpanded: $calibrationExpanded) {
                        VStack(spacing: 0) {
                            // 짐벌 설정 및 실시간 수평계 (신규)
                            NavigationLink(destination: DeviceCalibrationView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "gyroscope")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appLanguage.localized("짐벌 및 수평 조절"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Text(appLanguage.localized("실시간 수평계 및 감도 설정"))
                                            .font(RBFont.caption(12))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(RBColor.textTertiary)
                                }
                                .padding(14)
                            }

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            // 사용자 키
                            HStack(spacing: 12) {
                                Image(systemName: "figure.stand")
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.accent)
                                    .frame(width: 32)
                                Text(appLanguage.localized("키"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Button {
                                        if userHeightCm > 120 { userHeightCm -= 1 }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Text("\(userHeightCm)")
                                        .font(RBFont.metric(16))
                                        .foregroundStyle(RBColor.textPrimary)
                                        .frame(width: 40)
                                    Text("cm")
                                        .font(RBFont.caption(12))
                                        .foregroundStyle(RBColor.textSecondary)
                                    Button {
                                        if userHeightCm < 220 { userHeightCm += 1 }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                }
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            // 장착 위치
                            HStack(spacing: 12) {
                                Image(systemName: "tshirt.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.accent)
                                    .frame(width: 32)
                                Text(appLanguage.localized("장착 위치"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(LaserCalibration.MountPosition.chest.displayName(appLanguage))
                                    .font(RBFont.label(14))
                                    .foregroundStyle(RBColor.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RBColor.cardBgLight)
                                    .clipShape(Capsule())
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            // 레이저 각도 미세 조절
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "angle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    Text(appLanguage.localized("레이저 각도 미세조절"))
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    Text(String(format: "%+.1f°", laserAngleOffset))
                                        .font(RBFont.metric(14))
                                        .foregroundStyle(RBColor.accent)
                                }
                                Slider(value: $laserAngleOffset, in: -5.0...5.0, step: 0.5)
                                    .tint(RBColor.accent)
                                    .padding(.leading, 44)
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            // 예상 투사 거리
                            HStack(spacing: 12) {
                                Image(systemName: "ruler")
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.textSecondary)
                                    .frame(width: 32)
                                Text(appLanguage.localized("예상 투사 거리"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(String(format: "약 %.1fm", currentCalibration.estimatedProjectionDistance))
                                    .font(RBFont.metric(14))
                                    .foregroundStyle(RBColor.accent)
                            }
                            .padding(14)

                            // 캘리브레이션 전송 버튼
                            if bleService.isConnected {
                                Divider().padding(.leading, 58).overlay(RBColor.divider)
                                Button {
                                    let cal = currentCalibration
                                    bleService.setServoAngle(Int(cal.laserAngleOffset + 85)) // 보정값을 중앙(85도) 기준으로 적용
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 16))
                                            .foregroundStyle(RBColor.accent)
                                            .frame(width: 32)
                                        Text(appLanguage.localized("기기에 캘리브레이션 전송"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.accent)
                                        Spacer()
                                    }
                                    .padding(14)
                                }
                            }
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("러닝"), isExpanded: $runningExpanded) {
                        VStack(spacing: 0) {
                            settingsToggle("자동 일시정지", icon: "pause.circle", isOn: $autoPause)
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            settingsToggle("햅틱 피드백", icon: "iphone.radiowaves.left.and.right", isOn: $hapticFeedback)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("음성 안내"), isExpanded: $voiceExpanded) {
                        VStack(spacing: 0) {
                            settingsToggle("음성 안내", icon: "speaker.wave.2", isOn: $voiceGuide)

                            if voiceGuide {
                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                // 거리 안내 주기
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "ruler")
                                            .font(.system(size: 16))
                                            .foregroundStyle(RBColor.accent)
                                            .frame(width: 32)
                                        Text(appLanguage.localized("거리별 안내 주기"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Spacer()
                                        Text(voiceDistanceInterval > 0 ? String(format: "%.1fkm", voiceDistanceInterval) : appLanguage.text("끔", "Off"))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Slider(value: $voiceDistanceInterval, in: 0...5.0, step: 0.5)
                                        .tint(RBColor.accent)
                                        .padding(.leading, 44)
                                }
                                .padding(14)

                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                // 페이스 이탈 경고
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.system(size: 16))
                                            .foregroundStyle(RBColor.accent)
                                            .frame(width: 32)
                                        Text(appLanguage.localized("페이스 이탈 경고"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Spacer()
                                        Text(String(format: "%.0fm", voicePaceAlertThreshold))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Slider(value: $voicePaceAlertThreshold, in: 5...50, step: 5)
                                        .tint(RBColor.accent)
                                        .padding(.leading, 44)
                                }
                                .padding(14)

                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                settingsToggle("카운트다운 음성", icon: "timer", isOn: $voiceCountdownAlert)

                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                Button {
                                    voiceGuideService.previewCurrentVoice()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 16))
                                            .foregroundStyle(RBColor.accent)
                                            .frame(width: 32)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(appLanguage.localized("현재 시스템 음성 미리 듣기"))
                                                .font(RBFont.label(15))
                                                .foregroundStyle(RBColor.textPrimary)
                                            Text(appLanguage.localized("설치된 고품질 음성이 있으면 자동으로 우선 사용합니다"))
                                                .font(RBFont.caption(11))
                                                .foregroundStyle(RBColor.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(RBColor.accent)
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("건강 & 운동"), isExpanded: $healthExpanded) {
                        VStack(spacing: 0) {
                            Button {
                                Task { await healthKit.requestAuthorization() }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(
                                            healthKit.isAuthorized
                                                ? RBColor.success
                                                : (isHealthDataAvailable ? RBColor.accent : RBColor.textTertiary)
                                        )
                                        .frame(width: 32)
                                    Text(appLanguage.localized("Apple 건강 앱 연동"))
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    if healthKit.isAuthorized {
                                        Text(appLanguage.localized("연동됨"))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.success)
                                    } else if !isHealthDataAvailable {
                                        Text(appLanguage.text("지원 안 됨", "Unavailable"))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.textTertiary)
                                    } else {
                                        Text(appLanguage.localized("권한 요청"))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.accent)
                                    }
                                }
                                .padding(14)
                            }
                            .disabled(!isHealthDataAvailable)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            Button {
                                showHealthSetupGuide = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "list.bullet.clipboard")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appLanguage.localized("연동 설정 가이드"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Text(appLanguage.localized("iPhone + Apple Watch 설정 순서 보기"))
                                            .font(RBFont.caption(12))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(RBColor.textTertiary)
                                }
                                .padding(14)
                            }

                            if let authorizationError = healthKit.authorizationError {
                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.danger)
                                        .frame(width: 32)
                                    Text(authorizationError)
                                        .font(RBFont.caption(12))
                                        .foregroundStyle(RBColor.danger)
                                    Spacer()
                                }
                                .padding(14)
                            }

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            HStack(spacing: 12) {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.textSecondary)
                                    .frame(width: 32)
                                Text(appLanguage.localized("운동 자동 저장"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(healthKit.isAuthorized ? appLanguage.text("활성", "On") : appLanguage.text("비활성", "Off"))
                                    .font(RBFont.caption(13))
                                    .foregroundStyle(healthKit.isAuthorized ? RBColor.success : RBColor.textTertiary)
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            HStack(spacing: 12) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.red.opacity(0.8))
                                    .frame(width: 32)
                                Text(appLanguage.localized("심박수 모니터링"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(healthKit.isAuthorized ? appLanguage.text("Apple Watch 필요", "Apple Watch Required") : appLanguage.text("비활성", "Off"))
                                    .font(RBFont.caption(13))
                                    .foregroundStyle(RBColor.textTertiary)
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("개인정보 & 계정"), isExpanded: $privacyExpanded) {
                        VStack(spacing: 0) {
                            legalRow(kind: .privacy, icon: "lock.doc", tint: RBColor.accent)
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            legalRow(kind: .terms, icon: "doc.text", tint: Color(red: 0.92, green: 0.68, blue: 0.22))
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            legalRow(kind: .location, icon: "location.circle", tint: Color(red: 0.2, green: 0.6, blue: 1.0))
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            legalRow(kind: .health, icon: "heart.circle", tint: .red.opacity(0.85))
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            Button {
                                showDeleteAccountAlert = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.badge.minus")
                                        .font(.system(size: 16))
                                        .foregroundStyle(authService.isSignedIn ? RBColor.danger : RBColor.textTertiary)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appLanguage.localized("계정 삭제"))
                                            .font(RBFont.label(15))
                                            .foregroundStyle(authService.isSignedIn ? RBColor.textPrimary : RBColor.textSecondary)
                                        Text(authService.isSignedIn ? appLanguage.text("삭제 후 복구할 수 없습니다.", "This cannot be undone.") : appLanguage.text("로그인 후 사용할 수 있습니다.", "Available after sign-in."))
                                            .font(RBFont.caption(12))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Spacer()
                                    if isDeletingAccount {
                                        ProgressView()
                                            .tint(RBColor.danger)
                                    } else {
                                        Text(appLanguage.localized("삭제"))
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(authService.isSignedIn ? RBColor.danger : RBColor.textTertiary)
                                    }
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeletingAccount || !authService.isSignedIn)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("화면"), isExpanded: $displayExpanded) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.accent)
                                    .frame(width: 32)
                                Text(appLanguage.localized("외관 모드"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Picker("", selection: $appearanceModeRaw) {
                                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                                        Text(mode.displayName(appLanguage)).tag(mode.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.accent)
                                    .frame(width: 32)
                                Text(appLanguage.localized("언어"))
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Picker("", selection: $appLanguageRaw) {
                                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                                        Text(language.displayName).tag(language.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }
                            .padding(14)

                            Divider().padding(.leading, 58).overlay(RBColor.divider)

                            VStack(alignment: .leading, spacing: 14) {
                                selectionSectionHeader(
                                    icon: (AppFontPreset(rawValue: appFontPresetRaw) ?? .modern).icon,
                                    title: appLanguage.localized("글꼴 스타일"),
                                    subtitle: appLanguage.text("앱 전체에 바로 반영됩니다.", "Applies across the app.")
                                )

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(AppFontPreset.allCases, id: \.rawValue) { preset in
                                            fontPresetButton(preset)
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }

                                Divider().overlay(RBColor.divider)

                                selectionSectionHeader(
                                    icon: currentAppColorTheme.icon,
                                    title: appLanguage.text("앱 색상", "App Color"),
                                    subtitle: appLanguage.text("버튼과 강조색에 적용됩니다.", "Used for buttons and highlights.")
                                )

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(AppColorTheme.allCases, id: \.rawValue) { theme in
                                            colorThemeButton(theme)
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }

                                fontPreviewCard
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        expandableSection(title: appLanguage.localized("정보"), isExpanded: $infoExpanded) {
                        VStack(spacing: 0) {
                            settingsRow("버전", value: "1.0.0")
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            settingsRow("개발", value: "Haneum Yu")
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
            }
            .navigationTitle(appLanguage.text("설정", "Settings"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                mountPositionRaw = LaserCalibration.MountPosition.chest.rawValue
            }
            .sheet(isPresented: $showHealthSetupGuide) {
                HealthSetupGuideSheet(appLanguage: appLanguage)
            }
            .sheet(item: $selectedLegalDocument) { documentKind in
                LegalDocumentSheet(kind: documentKind, appLanguage: appLanguage)
            }
            .confirmationDialog(appLanguage.localized("계정을 삭제할까요?"), isPresented: $showDeleteAccountAlert, titleVisibility: .visible) {
                Button(appLanguage.localized("삭제"), role: .destructive) {
                    deleteCurrentAccount()
                }
                Button(appLanguage.localized("취소"), role: .cancel) {}
            }
            .alert(
                appLanguage.localized("계정 안내"),
                isPresented: Binding(
                    get: { accountNoticeMessage != nil },
                    set: { if !$0 { accountNoticeMessage = nil } }
                )
            ) {
                Button(appLanguage.localized("확인"), role: .cancel) {}
            } message: {
                Text(accountNoticeMessage ?? "")
            }
    }

    private func expandableSection<Content: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(appLanguage.localized(title))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RBColor.textTertiary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded.wrappedValue)
    }

    private func settingsToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(RBColor.accent)
                .frame(width: 32)
            Text(appLanguage.localized(title))
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
            RBBarToggle(title: nil, isOn: isOn, height: 32)
                .frame(width: 86)
        }
        .padding(14)
    }

    private func legalRow(kind: LegalDocumentKind, icon: String, tint: Color) -> some View {
        let document = LegalContent.document(for: kind, language: appLanguage)
        return Button {
            selectedLegalDocument = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(document.summary)
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RBColor.textTertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(RBColor.textSecondary)
                .frame(width: 32)
            Text(appLanguage.localized(title))
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
            Text(value)
                .font(RBFont.caption(14))
                .foregroundStyle(RBColor.textSecondary)
        }
        .padding(14)
    }

    private func selectionSectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(RBColor.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RBFont.label(15))
                    .foregroundStyle(RBColor.textPrimary)

                Text(subtitle)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func fontPresetButton(_ preset: AppFontPreset) -> some View {
        let isSelected = preset.rawValue == appFontPresetRaw

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                appFontPresetRaw = preset.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(preset.displayName(appLanguage))
                        .font(preset.bodyFont(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                Text(appLanguage.text("BeamChaser", "BeamChaser"))
                    .font(preset.titleFont(size: 20, weight: .bold))
                    .lineLimit(1)

                Text(appLanguage.text("5.24 km   4'32\"/km", "5.24 km   4'32\"/km"))
                    .font(preset.bodyFont(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? RBColor.textPrimary : RBColor.textSecondary)
                    .lineLimit(1)

                Text(preset.description(appLanguage))
                    .font(preset.bodyFont(size: 11, weight: .medium))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? RBColor.textPrimary : RBColor.textSecondary)
            .frame(width: 168, height: 128, alignment: .leading)
            .padding(14)
            .background(isSelected ? RBColor.accent.opacity(0.18) : RBColor.cardBgLight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? RBColor.accent : RBColor.divider.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var fontPreviewCard: some View {
        let preset = AppFontPreset(rawValue: appFontPresetRaw) ?? .modern

        return VStack(alignment: .leading, spacing: 12) {
            Text(appLanguage.localized("미리보기"))
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLanguage.localized("오늘 페이스는 가볍게, 리듬은 선명하게"))
                        .font(preset.titleFont(size: 20, weight: .bold))
                        .foregroundStyle(RBColor.textPrimary)

                    Text(appLanguage.text("주요 화면의 숫자와 버튼 강조색에 함께 적용됩니다.", "Applies to key text and button accents across the app."))
                        .font(preset.bodyFont(size: 12, weight: .medium))
                        .foregroundStyle(RBColor.textSecondary)
                        .lineLimit(1)
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(currentAppColorTheme.primary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: currentAppColorTheme.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(currentAppColorTheme.accentSurfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func colorThemeButton(_ theme: AppColorTheme) -> some View {
        let isSelected = theme.rawValue == appColorThemeRaw

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                appColorThemeRaw = theme.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                LinearGradient(
                    colors: [theme.primary, theme.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 104, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )

                Text(theme.displayName(appLanguage))
                    .font(RBFont.label(13))
                    .lineLimit(1)

                Text(appLanguage.text("브랜드 강조색", "Brand accent"))
                    .font(RBFont.caption(11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.84) : RBColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : RBColor.textPrimary)
            .padding(12)
            .frame(width: 128, height: 114, alignment: .leading)
            .background(isSelected ? theme.primary : RBColor.cardBgLight)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.primary : RBColor.divider.opacity(0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var currentAppColorTheme: AppColorTheme {
        AppColorTheme(rawValue: appColorThemeRaw) ?? .beam
    }

    // MARK: - Battery Helpers

    private var batteryIconName: String {
        guard let status = bleService.deviceStatus else { return "battery.50percent" }
        if status.isCharging { return "battery.100percent.bolt" }
        if status.batteryPercent > 75 { return "battery.100percent" }
        if status.batteryPercent > 50 { return "battery.75percent" }
        if status.batteryPercent > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private var batteryStatusColor: Color {
        guard let status = bleService.deviceStatus else { return RBColor.textTertiary }
        if status.batteryPercent > 50 { return RBColor.success }
        if status.batteryPercent > 20 { return .yellow }
        return RBColor.danger
    }

    // MARK: - Calibration Helper

    private var currentCalibration: LaserCalibration {
        let mount = LaserCalibration.MountPosition(rawValue: mountPositionRaw) ?? .chest
        return LaserCalibration(
            userHeightCm: userHeightCm,
            mountPosition: mount,
            laserAngleOffset: laserAngleOffset,
            projectionDistanceM: 2.0
        )
    }

    private func deleteCurrentAccount() {
        guard authService.isSignedIn else {
            accountNoticeMessage = appLanguage.localized("로그인된 계정이 없어요.")
            return
        }

        isDeletingAccount = true

        Task {
            defer { isDeletingAccount = false }

            do {
                try await backendService.deleteCurrentAccount()
                runSession.clearAllSavedRecords()
                profileService.resetLocalProfile()
                authService.clearLocalSession()
                accountNoticeMessage = appLanguage.localized("계정과 관련된 앱 내 데이터를 삭제했어요.")
            } catch {
                let nsError = error as NSError
                if AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
                    accountNoticeMessage = appLanguage.localized("보안을 위해 다시 로그인한 뒤 계정 삭제를 진행해주세요.")
                } else {
                    accountNoticeMessage = backendService.error ?? appLanguage.text("계정 삭제에 실패했어요: \(error.localizedDescription)", "Account deletion failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

private struct ReviewChecklistSheet: View {
    @Environment(\.dismiss) private var dismiss

    let appLanguage: AppLanguage
    let policyDocumentsReady: Bool
    let permissionCopyConfigured: Bool
    let googleURLSchemeConfigured: Bool
    @Binding var reviewCheckBLEDevice: Bool
    @Binding var reviewCheckLocationDevice: Bool
    @Binding var reviewCheckHealthKitDevice: Bool
    @Binding var reviewCheckPrivacyURL: Bool
    @Binding var reviewCheckAppPrivacyForm: Bool

    private var completionCount: Int {
        [
            policyDocumentsReady,
            true,
            permissionCopyConfigured,
            googleURLSchemeConfigured,
            reviewCheckBLEDevice,
            reviewCheckLocationDevice,
            reviewCheckHealthKitDevice,
            reviewCheckPrivacyURL,
            reviewCheckAppPrivacyForm
        ].filter { $0 }.count
    }

    private var totalCount: Int { 9 }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appLanguage.text("심사 준비 현황", "Review Readiness"))
                                .font(RBFont.hero(24))
                                .foregroundStyle(RBColor.textPrimary)
                            Text(appLanguage.text("자동 검출 가능한 항목과 실기기에서 직접 확인해야 하는 항목을 함께 관리합니다.", "Track both automatically-detected items and the checks you still need to verify on a real device."))
                                .font(RBFont.caption(13))
                                .foregroundStyle(RBColor.textSecondary)
                            Text("\(completionCount)/\(totalCount)")
                                .font(RBFont.metric(18))
                                .foregroundStyle(RBColor.accent)
                        }
                        .padding(18)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        checklistCard(title: appLanguage.text("자동 확인", "Automatic Checks")) {
                            automaticRow(
                                title: appLanguage.text("인앱 정책 문서 4종", "Four in-app policy documents"),
                                subtitle: appLanguage.text("개인정보 처리방침, 이용약관, 위치, 건강 정책 노출", "Privacy, terms, location, and health policies are exposed in-app"),
                                isReady: policyDocumentsReady
                            )
                            automaticRow(
                                title: appLanguage.text("계정 삭제 경로", "Account deletion entry"),
                                subtitle: appLanguage.text("설정 > 개인정보 & 계정에서 바로 진입 가능", "Available directly from Settings > Privacy & Account"),
                                isReady: true
                            )
                            automaticRow(
                                title: appLanguage.text("권한 안내 문구", "Permission copy"),
                                subtitle: appLanguage.text("위치, 건강, 블루투스, 연락처, 사진 설명 등록", "Location, health, Bluetooth, contacts, and photo descriptions are present"),
                                isReady: permissionCopyConfigured
                            )
                            automaticRow(
                                title: appLanguage.text("Google URL 스킴", "Google URL scheme"),
                                subtitle: appLanguage.text("Google 로그인 리디렉션 스킴 등록", "Google sign-in redirect scheme is configured"),
                                isReady: googleURLSchemeConfigured
                            )
                        }

                        checklistCard(title: appLanguage.text("실기기 및 콘솔 수동 체크", "Manual Device and Console Checks")) {
                            manualRow(
                                title: appLanguage.text("BLE 실기기 연결 확인", "Verify BLE connection on device"),
                                subtitle: appLanguage.text("장치 검색, 연결, 배터리 상태 노출까지 점검", "Check scanning, connection, and battery status on a device"),
                                isOn: $reviewCheckBLEDevice
                            )
                            manualRow(
                                title: appLanguage.text("위치 경로 저장 확인", "Verify route tracking"),
                                subtitle: appLanguage.text("러닝 종료 후 경로와 지도 저장 결과 확인", "Confirm route capture and map persistence after a run"),
                                isOn: $reviewCheckLocationDevice
                            )
                            manualRow(
                                title: appLanguage.text("HealthKit 저장 확인", "Verify HealthKit save"),
                                subtitle: appLanguage.text("실기기에서 운동, 경로, 심박 저장 결과 확인", "Confirm workout, route, and heart-rate writes on a real device"),
                                isOn: $reviewCheckHealthKitDevice
                            )
                            manualRow(
                                title: appLanguage.text("개인정보 처리방침 URL 입력", "Privacy policy URL entered"),
                                subtitle: appLanguage.text("App Store Connect 메타데이터 등록 여부", "Confirm the metadata is filled in App Store Connect"),
                                isOn: $reviewCheckPrivacyURL
                            )
                            manualRow(
                                title: appLanguage.text("App Privacy 폼 작성", "App Privacy form completed"),
                                subtitle: appLanguage.text("수집 데이터 항목을 스토어 폼에 반영했는지 확인", "Confirm the store privacy form matches collected data"),
                                isOn: $reviewCheckAppPrivacyForm
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(appLanguage.text("심사 체크", "Review Checks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLanguage.text("닫기", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func checklistCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)

            VStack(spacing: 0) {
                content()
            }
            .background(RBColor.cardBgLight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func automaticRow(title: String, subtitle: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.seal.fill" : "xmark.seal")
                .font(.system(size: 16))
                .foregroundStyle(isReady ? RBColor.success : RBColor.danger)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textPrimary)
                Text(subtitle)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
    }

    private func manualRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? RBColor.accent : RBColor.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RBFont.label(14))
                    .foregroundStyle(RBColor.textPrimary)
                Text(subtitle)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            RBBarToggle(title: nil, isOn: isOn, height: 32)
                .frame(width: 86)
        }
        .padding(14)
    }
}

private struct LegalDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: LegalDocumentKind
    let appLanguage: AppLanguage

    private var document: LegalDocumentDescriptor {
        LegalContent.document(for: kind, language: appLanguage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(document.title)
                            .font(RBFont.hero(24))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(document.summary)
                            .font(RBFont.caption(13))
                            .foregroundStyle(RBColor.textSecondary)
                        Text(document.body)
                            .font(RBFont.caption(13))
                            .foregroundStyle(RBColor.textPrimary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLanguage.text("닫기", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HealthSetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appLanguage: AppLanguage

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        guideCard(
                            title: appLanguage.text("1. iPhone에서 건강 권한 허용", "1. Allow Health access on iPhone"),
                            body: appLanguage.text("설정 > 앱 > 건강 > 데이터 접근 및 기기에서 BeamChaser를 열고 운동, 경로, 심박수 읽기/쓰기 권한을 허용하세요.", "Open Settings > Apps > Health > Data Access & Devices > BeamChaser and allow workout, route, and heart-rate permissions.")
                        )

                        guideCard(
                            title: appLanguage.text("2. Apple Watch 권한 확인", "2. Check Apple Watch permissions"),
                            body: appLanguage.text("iPhone의 Watch 앱 > 개인 정보 보호에서 심박수와 피트니스 추적이 켜져 있어야 하고, 건강 앱에서 Apple Watch가 데이터 소스로 활성화되어 있어야 합니다.", "In the Watch app on iPhone, keep Heart Rate and Fitness Tracking enabled, and make sure Apple Watch is active as a data source in Health.")
                        )

                        guideCard(
                            title: appLanguage.text("3. 러닝 시작 전 체크", "3. Before starting a run"),
                            body: appLanguage.text("BeamChaser 설정에서 Apple 건강 앱 연동을 눌러 권한을 요청하고, 워치를 착용한 상태에서 러닝을 시작하세요. 러닝 종료 시 운동 기록과 경로가 건강 앱에 저장됩니다.", "Tap Apple Health sync inside BeamChaser Settings, wear your watch, and start the run. When you finish, the workout and route are saved to Health.")
                        )

                        guideCard(
                            title: appLanguage.text("4. 심박수 실시간 반영 팁", "4. Tip for live heart-rate syncing"),
                            body: appLanguage.text("실시간 심박수는 Apple Watch 착용 상태가 가장 안정적입니다. 권한을 준 뒤 워치 연결 상태를 유지하면 러닝 화면과 건강 데이터 동기화가 더 정확해집니다.", "Live heart-rate data works best while wearing Apple Watch. Keep permissions granted and the watch connected for more reliable workout syncing.")
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle(appLanguage.text("연동 설정 가이드", "Setup Guide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLanguage.text("닫기", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func guideCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)
            Text(body)
                .font(RBFont.caption(13))
                .foregroundStyle(RBColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    SettingsView()
        .environmentObject(BLEService())
        .environmentObject(HealthKitService())
        .environmentObject(AuthService())
        .environmentObject(BackendService())
        .environmentObject(ProfileService())
        .environmentObject(RunSessionManager())
}
