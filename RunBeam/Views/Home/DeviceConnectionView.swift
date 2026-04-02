import SwiftUI

struct DeviceConnectionView: View {
    @EnvironmentObject var bleService: BLEService
    @Environment(\.dismiss) private var dismiss
    @State private var manualAngle: Double = 85

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 연결된 장치
                    if bleService.isConnected {
                        connectedCard

                        // 서보 각도 조절
                        servoControlCard

                        // 레이저 테스트
                        laserTestCard
                    }

                    // 에러 메시지
                    if let error = bleService.connectionError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(RBColor.danger)
                            Text(error)
                                .font(RBFont.caption(13))
                                .foregroundStyle(RBColor.danger)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RBColor.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // 검색 헤더
                    HStack {
                        Text("검색된 장치")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textTertiary)
                            .textCase(.uppercase)
                            .tracking(1)
                        Spacer()
                        if bleService.isScanning {
                            ProgressView()
                                .tint(RBColor.accent)
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 4)

                    if bleService.discoveredDevices.isEmpty && !bleService.isScanning {
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 40))
                                .foregroundStyle(RBColor.textTertiary)
                            Text("장치를 검색해주세요")
                                .font(RBFont.label(15))
                                .foregroundStyle(RBColor.textSecondary)
                            Text("HM-10 BLE 모듈이 켜져 있는지 확인하세요")
                                .font(RBFont.caption(12))
                                .foregroundStyle(RBColor.textTertiary)
                        }
                        .padding(.vertical, 40)
                    }

                    // 장치 목록
                    VStack(spacing: 0) {
                        ForEach(Array(bleService.discoveredDevices.enumerated()), id: \.element.identifier) { index, device in
                            if index > 0 {
                                Divider().padding(.leading, 54).overlay(RBColor.divider)
                            }
                            Button {
                                bleService.connect(to: device)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "wave.3.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RBColor.accent)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? "알 수 없는 장치")
                                            .font(RBFont.label(15))
                                            .foregroundStyle(RBColor.textPrimary)
                                        Text(String(device.identifier.uuidString.prefix(8)) + "...")
                                            .font(RBFont.caption(11))
                                            .foregroundStyle(RBColor.textTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                            }
                        }
                    }
                    .background(RBColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("장치 연결")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if bleService.isConnected {
                    Button("연결 해제") {
                        bleService.disconnect()
                    }
                    .foregroundStyle(RBColor.danger)
                } else {
                    Menu {
                        Button {
                            bleService.startScanning()
                        } label: {
                            Label("RunBeam 검색", systemImage: "magnifyingglass")
                        }
                        Button {
                            bleService.startScanningAll()
                        } label: {
                            Label("모든 BLE 장치 검색", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    } label: {
                        Label("검색", systemImage: "magnifyingglass")
                    }
                    .tint(RBColor.accent)
                    .disabled(bleService.isScanning)
                }
            }
        }
    }

    // MARK: - 연결된 장치 카드

    private var connectedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(RBColor.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(bleService.connectedDeviceName ?? "RunBeam")
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Text("연결됨")
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.success)
            }

            Spacer()

            if let status = bleService.deviceStatus {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("배터리 \(status.batteryPercent)%")
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(zoneColor(status.zone))
                            .frame(width: 8, height: 8)
                        Text(status.zone.label)
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    Text("레이저 \(status.isLaserActive ? "ON" : "OFF")")
                        .font(RBFont.caption(11))
                        .foregroundStyle(status.isLaserActive ? RBColor.accent : RBColor.textTertiary)
                }
            }
        }
        .padding(16)
        .background(RBColor.success.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RBColor.success.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 서보 제어 카드

    private var servoControlCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "angle")
                    .foregroundStyle(RBColor.accent)
                Text("서보 각도")
                    .font(RBFont.label(15))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                Text("\(Int(manualAngle))°")
                    .font(RBFont.metric(18))
                    .foregroundStyle(RBColor.accent)
            }

            Slider(value: $manualAngle, in: 60...110, step: 1)
                .tint(RBColor.accent)
                .onChange(of: manualAngle) { _, newValue in
                    bleService.setServoAngle(Int(newValue))
                }

            HStack(spacing: 12) {
                ForEach([60, 75, 85, 95, 110], id: \.self) { angle in
                    Button {
                        manualAngle = Double(angle)
                        bleService.setServoAngle(angle)
                    } label: {
                        Text("\(angle)°")
                            .font(RBFont.label(12))
                            .foregroundStyle(Int(manualAngle) == angle ? .white : RBColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Int(manualAngle) == angle ? RBColor.accent.opacity(0.3) : RBColor.cardBgLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 레이저 테스트 카드

    private var laserTestCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "light.max")
                    .foregroundStyle(RBColor.accent)
                Text("레이저 테스트")
                    .font(RBFont.label(15))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    bleService.setZone(.blue)
                } label: {
                    Text("파랑")
                        .font(RBFont.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    bleService.setZone(.green)
                } label: {
                    Text("초록")
                        .font(RBFont.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    bleService.setZone(.red)
                } label: {
                    Text("빨강")
                        .font(RBFont.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            HStack(spacing: 12) {
                Button {
                    bleService.turnLaserOn()
                } label: {
                    Text("레이저 ON")
                        .font(RBFont.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RBColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    bleService.turnLaserOff()
                } label: {
                    Text("레이저 OFF")
                        .font(RBFont.label(13))
                        .foregroundStyle(RBColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RBColor.cardBgLight)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func zoneColor(_ zone: DeviceZone) -> Color {
        switch zone {
        case .none:  return .gray
        case .blue:  return .blue
        case .green: return .green
        case .red:   return .red
        }
    }
}

#Preview {
    NavigationStack {
        DeviceConnectionView()
            .environmentObject(BLEService())
    }
}
