import SwiftUI

struct DeviceCalibrationView: View {
    @EnvironmentObject var bleService: BLEService
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("gimbalSensitivity") private var sensitivity: Double = 128
    @AppStorage("gimbalOffset") private var calibrationOffset: Double = 0
    
    @State private var bubbleOpacity: Double = 1.0

    @State private var show3DModel = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // 1. 시뮬레이션 실험실 (1인칭 POV 또는 3D 모델)
                    VStack(spacing: 12) {
                        HStack {
                            sectionHeader(show3DModel ? appLanguage.localized("3D 러너 모델") : appLanguage.localized("1인칭 러닝 시야"))
                            Spacer()
                            Button {
                                withAnimation(.spring()) { show3DModel.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: show3DModel ? "eye" : "figure.run")
                                    Text(show3DModel ? appLanguage.localized("POV로 전환") : appLanguage.localized("3D 모델로 전환"))
                                }
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.accent)
                            }
                        }
                        
                        ZStack {
                            if show3DModel {
                                RunnerSimulationView()
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                RunnerPOVView()
                                    .transition(.opacity)
                            }
                        }
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(RBColor.divider, lineWidth: 1)
                        )
                    }
                    .padding(.top, 10)

                    // 2. 짐벌 감도 설정 (기존 섹션 2)
                    VStack(spacing: 12) {
                        sectionHeader(appLanguage.localized("짐벌 반응 감도"))
                        
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "gauge.with.needle")
                                    .foregroundStyle(RBColor.accent)
                                Text(sensitivityLabel)
                                    .font(RBFont.label(15))
                                Spacer()
                                Text("\(Int(sensitivity))")
                                    .font(RBFont.metric(16))
                                    .foregroundStyle(RBColor.accent)
                            }
                            
                            Slider(value: $sensitivity, in: 0...255, step: 1)
                                .tint(RBColor.accent)
                                .onChange(of: sensitivity) { _, newValue in
                                    bleService.setSensitivity(Int(newValue))
                                }
                            
                            Text(appLanguage.localized("감도가 높을수록 몸의 흔들림에 레이저가 더 민감하게 반응하여 수평을 유지합니다."))
                                .font(RBFont.caption(12))
                                .foregroundStyle(RBColor.textTertiary)
                        }
                        .padding(20)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // 3. 영점 조절 (오프셋)
                    VStack(spacing: 12) {
                        sectionHeader(appLanguage.localized("레이저 영점 조절"))
                        
                        VStack(spacing: 20) {
                            Text(appLanguage.localized("러닝 자세에서 레이저가 지면의 원하는 위치에 오도록 미세하게 조정하세요."))
                                .font(RBFont.caption(12))
                                .foregroundStyle(RBColor.textSecondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 30) {
                                Button {
                                    calibrationOffset -= 1
                                    updateOffset()
                                } label: {
                                    calibrationControlButton(icon: "minus.circle.fill", label: appLanguage.localized("낮게"))
                                }

                                VStack(spacing: 4) {
                                    Text(String(format: "%+.0f°", calibrationOffset))
                                        .font(RBFont.metric(32))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text(appLanguage.localized("오프셋"))
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(RBColor.textTertiary)
                                }

                                Button {
                                    calibrationOffset += 1
                                    updateOffset()
                                } label: {
                                    calibrationControlButton(icon: "plus.circle.fill", label: appLanguage.localized("높게"))
                                }
                            }
                            
                            Button {
                                calibrationOffset = 0
                                updateOffset()
                            } label: {
                                Text(appLanguage.localized("영점 초기화"))
                                    .font(RBFont.label(13))
                                    .foregroundStyle(RBColor.textTertiary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(RBColor.cardBgLight)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(20)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 16)
            }
            .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
        }
        .navigationTitle(appLanguage.localized("짐벌 설정"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 진입 시 현재 설정값을 기기로 다시 전송
            bleService.setSensitivity(Int(sensitivity))
            bleService.setCalibration(Int(calibrationOffset))
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
    }

    private func calibrationControlButton(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(RBColor.accent)
            Text(label)
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
        }
    }
    
    private var sensitivityLabel: String {
        if sensitivity < 50 { return appLanguage.localized("매우 부드러움") }
        if sensitivity < 100 { return appLanguage.localized("부드러움") }
        if sensitivity < 160 { return appLanguage.localized("적정 감도") }
        if sensitivity < 220 { return appLanguage.localized("민감함") }
        return appLanguage.localized("매우 민감함")
    }
    
    private func updateOffset() {
        bleService.setCalibration(Int(calibrationOffset))
    }
}

#Preview {
    NavigationStack {
        DeviceCalibrationView()
            .environmentObject(MockBLEService())
    }
}
