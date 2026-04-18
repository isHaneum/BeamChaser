import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var profileService: ProfileService
    @EnvironmentObject var runSession: RunSessionManager
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
    @AppStorage("dayMode") private var dayMode: Bool = false
    @State private var showHealthSetupGuide = false
    @State private var selectedLegalDocument: LegalDocumentKind?
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var accountNoticeMessage: String?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                        // 장치 섹션
                        sectionHeader("런빔 장치")
                        VStack(spacing: 0) {
                            NavigationLink(destination: DeviceConnectionView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(bleService.isConnected ? RBColor.success : RBColor.accent)
                                        .frame(width: 32)
                                    Text(bleService.isConnected ? "연결됨: \(bleService.connectedDeviceName ?? "")" : "장치 연결")
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
                                    Text("배터리")
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    if let status = bleService.deviceStatus {
                                        HStack(spacing: 6) {
                                            if status.isCharging {
                                                Image(systemName: "bolt.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(RBColor.success)
                                                Text("충전 중")
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
                                        Text("불러오는 중...")
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
                                    Text("주간 모드 (레이저 점멸)")
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text("밝은 곳에서 레이저를 10Hz로 깜빡여 가시성 향상")
                                        .font(RBFont.caption(12))
                                        .foregroundStyle(RBColor.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $dayMode)
                                    .tint(Color.yellow)
                                    .onChange(of: dayMode) { _, newValue in
                                        bleService.setDayMode(newValue)
                                    }
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // 레이저 캘리브레이션 섹션
                        sectionHeader("레이저 캘리브레이션")
                        VStack(spacing: 0) {
                            // 짐벌 설정 및 실시간 수평계 (신규)
                            NavigationLink(destination: DeviceCalibrationView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "gyroscope")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("짐벌 및 수평 조절")
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Text("실시간 수평계 및 감도 설정")
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
                                Text("키")
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
                                Text("장착 위치")
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Picker("", selection: $mountPositionRaw) {
                                    ForEach(LaserCalibration.MountPosition.allCases, id: \.rawValue) { pos in
                                        Text(pos.rawValue).tag(pos.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
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
                                    Text("레이저 각도 미세조절")
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
                                Text("예상 투사 거리")
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
                                        Text("기기에 캘리브레이션 전송")
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

                        // 러닝 섹션
                        sectionHeader("러닝")
                        VStack(spacing: 0) {
                            settingsToggle("자동 일시정지", icon: "pause.circle", isOn: $autoPause)
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            settingsToggle("햅틱 피드백", icon: "iphone.radiowaves.left.and.right", isOn: $hapticFeedback)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // 음성 안내 섹션
                        sectionHeader("음성 안내")
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
                                        Text("거리별 안내 주기")
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Spacer()
                                        Text(voiceDistanceInterval > 0 ? String(format: "%.1fkm", voiceDistanceInterval) : "끔")
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Slider(value: $voiceDistanceInterval, in: 0...5.0, step: 0.5)
                                        .tint(RBColor.accent)
                                        .padding(.leading, 44)
                                    Text("설정 거리마다 페이스, 거리, 시간 안내")
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(RBColor.textTertiary)
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
                                        Text("페이스 이탈 경고")
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
                                    Text("레이저와 설정 거리 이상 벌어지면 경고음")
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(RBColor.textTertiary)
                                        .padding(.leading, 44)
                                }
                                .padding(14)

                                Divider().padding(.leading, 58).overlay(RBColor.divider)

                                settingsToggle("카운트다운 음성", icon: "timer", isOn: $voiceCountdownAlert)
                            }
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // 건강 앱 연동 섹션
                        sectionHeader("건강 & 운동")
                        VStack(spacing: 0) {
                            Button {
                                Task { await healthKit.requestAuthorization() }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(healthKit.isAuthorized ? RBColor.success : RBColor.accent)
                                        .frame(width: 32)
                                    Text("Apple 건강 앱 연동")
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    if healthKit.isAuthorized {
                                        Text("연동됨")
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.success)
                                    } else {
                                        Text("권한 요청")
                                            .font(RBFont.caption(13))
                                            .foregroundStyle(RBColor.accent)
                                    }
                                }
                                .padding(14)
                            }

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
                                        Text("연동 설정 가이드")
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Text("iPhone + Apple Watch 설정 순서 보기")
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
                                Text("운동 자동 저장")
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(healthKit.isAuthorized ? "활성" : "비활성")
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
                                Text("심박수 모니터링")
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(healthKit.isAuthorized ? "Apple Watch 필요" : "비활성")
                                    .font(RBFont.caption(13))
                                    .foregroundStyle(RBColor.textTertiary)
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        sectionHeader("개인정보 & 계정")
                        VStack(spacing: 0) {
                            legalRow(kind: .privacy, icon: "lock.doc", tint: RBColor.accent)
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
                                        Text("계정 삭제")
                                            .font(RBFont.label(15))
                                            .foregroundStyle(authService.isSignedIn ? RBColor.textPrimary : RBColor.textSecondary)
                                        Text(authService.isSignedIn ? "서버 데이터와 로컬 기록을 함께 삭제합니다." : "로그인 후 사용할 수 있습니다.")
                                            .font(RBFont.caption(12))
                                            .foregroundStyle(RBColor.textSecondary)
                                    }
                                    Spacer()
                                    if isDeletingAccount {
                                        ProgressView()
                                            .tint(RBColor.danger)
                                    } else {
                                        Text("삭제")
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

                        // 화면 모드 섹션
                        sectionHeader("화면")
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(RBColor.accent)
                                    .frame(width: 32)
                                Text("외관 모드")
                                    .font(RBFont.label(15))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Picker("", selection: $appearanceModeRaw) {
                                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                                        Text(mode.rawValue).tag(mode.rawValue)
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
                                Text("언어")
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
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // 정보 섹션
                        sectionHeader("정보")
                        VStack(spacing: 0) {
                            settingsRow("버전", value: "1.0.0")
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            settingsRow("개발", value: "Haneum Yu")
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                }
                .contentMargins(.bottom, 130, for: .scrollContent)
            }
            .navigationTitle(appLanguage.text("설정", "Settings"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showHealthSetupGuide) {
                HealthSetupGuideSheet(appLanguage: appLanguage)
            }
            .sheet(item: $selectedLegalDocument) { documentKind in
                LegalDocumentSheet(kind: documentKind)
            }
            .confirmationDialog("계정을 삭제할까요?", isPresented: $showDeleteAccountAlert, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    deleteCurrentAccount()
                }
                Button("취소", role: .cancel) {}
            }
            .alert(
                "계정 안내",
                isPresented: Binding(
                    get: { accountNoticeMessage != nil },
                    set: { if !$0 { accountNoticeMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(accountNoticeMessage ?? "")
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func settingsToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(RBColor.accent)
                .frame(width: 32)
            Text(title)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(RBColor.accent)
                .labelsHidden()
        }
        .padding(14)
    }

    private func legalRow(kind: LegalDocumentKind, icon: String, tint: Color) -> some View {
        let document = LegalContent.document(for: kind)
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
            Text(title)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
            Text(value)
                .font(RBFont.caption(14))
                .foregroundStyle(RBColor.textSecondary)
        }
        .padding(14)
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
            accountNoticeMessage = "로그인된 계정이 없어요."
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
                accountNoticeMessage = "계정과 관련된 앱 내 데이터를 삭제했어요."
            } catch {
                let nsError = error as NSError
                if AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
                    accountNoticeMessage = "보안을 위해 다시 로그인한 뒤 계정 삭제를 진행해주세요."
                } else {
                    accountNoticeMessage = backendService.error ?? "계정 삭제에 실패했어요: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct LegalDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: LegalDocumentKind

    private var document: LegalDocumentDescriptor {
        LegalContent.document(for: kind)
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
                    Button("닫기") {
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
                            body: appLanguage.text("설정 > 앱 > 건강 > 데이터 접근 및 기기에서 RunBeam을 열고 운동, 경로, 심박수 읽기/쓰기 권한을 허용하세요.", "Open Settings > Apps > Health > Data Access & Devices > RunBeam and allow workout, route, and heart-rate permissions.")
                        )

                        guideCard(
                            title: appLanguage.text("2. Apple Watch 권한 확인", "2. Check Apple Watch permissions"),
                            body: appLanguage.text("iPhone의 Watch 앱 > 개인 정보 보호에서 심박수와 피트니스 추적이 켜져 있어야 하고, 건강 앱에서 Apple Watch가 데이터 소스로 활성화되어 있어야 합니다.", "In the Watch app on iPhone, keep Heart Rate and Fitness Tracking enabled, and make sure Apple Watch is active as a data source in Health.")
                        )

                        guideCard(
                            title: appLanguage.text("3. 러닝 시작 전 체크", "3. Before starting a run"),
                            body: appLanguage.text("RunBeam 설정에서 Apple 건강 앱 연동을 눌러 권한을 요청하고, 워치를 착용한 상태에서 러닝을 시작하세요. 러닝 종료 시 운동 기록과 경로가 건강 앱에 저장됩니다.", "Tap Apple Health sync inside RunBeam Settings, wear your watch, and start the run. When you finish, the workout and route are saved to Health.")
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
