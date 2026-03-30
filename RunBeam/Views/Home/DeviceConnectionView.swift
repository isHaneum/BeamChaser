import SwiftUI

struct DeviceConnectionView: View {
    @EnvironmentObject var bleService: BLEService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 연결된 장치
                    if bleService.isConnected {
                        connectedCard
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
                    Button {
                        bleService.startScanning()
                    } label: {
                        Label("검색", systemImage: "magnifyingglass")
                    }
                    .tint(RBColor.accent)
                    .disabled(bleService.isScanning)
                }
            }
        }
    }

    private var connectedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(RBColor.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(bleService.connectedDeviceName ?? "런빔 장치")
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
                    if status.isCharging {
                        Label("충전 중", systemImage: "bolt.fill")
                            .font(RBFont.caption(10))
                            .foregroundStyle(RBColor.success)
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
}

#Preview {
    NavigationStack {
        DeviceConnectionView()
            .environmentObject(BLEService())
    }
}
