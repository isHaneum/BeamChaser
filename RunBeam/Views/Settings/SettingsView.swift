import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleService: BLEService
    @EnvironmentObject var healthKit: HealthKitService
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

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "sun.max.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    Text("레이저 밝기")
                                        .font(RBFont.label(15))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    Text("\(Int(laserBrightness * 100))%")
                                        .font(RBFont.caption(13))
                                        .foregroundStyle(RBColor.textSecondary)
                                }
                                Slider(value: $laserBrightness, in: 0.1...1.0, step: 0.1)
                                    .tint(RBColor.accent)
                                    .padding(.leading, 44)
                            }
                            .padding(14)
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // 레이저 캘리브레이션 섹션
                        sectionHeader("레이저 캘리브레이션")
                        VStack(spacing: 0) {
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
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // 정보 섹션
                        sectionHeader("정보")
                        VStack(spacing: 0) {
                            settingsRow("버전", value: "1.0.0")
                            Divider().padding(.leading, 58).overlay(RBColor.divider)
                            settingsRow("개발", value: "금(金)조")
                        }
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
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
}

#Preview {
    SettingsView()
        .environmentObject(BLEService())
        .environmentObject(HealthKitService())
}
