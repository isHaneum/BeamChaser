import SwiftUI
import MapKit
import PhotosUI

// MARK: - 러닝 공유 카드

struct RunShareCardView: View {
    let record: RunRecord
    @Environment(\.dismiss) private var dismiss
    @State private var mapSnapshot: UIImage?
    @State private var selectedPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("러닝 카드 공유")
                    .font(RBFont.label(17))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 카드 프리뷰
                        cardContent
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [RBColor.accent, RBColor.laserRed, RBColor.accent.opacity(0.3)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )

                        // 인증 사진 추가
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedPhoto != nil ? "photo.fill" : "camera.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(selectedPhoto != nil ? "사진 변경" : "인증 사진 추가")
                                    .font(RBFont.label(13))
                            }
                            .foregroundStyle(RBColor.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 32)

                // 공유 버튼
                HStack(spacing: 16) {
                    Button {
                        shareCard()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .bold))
                            Text("공유하기")
                                .font(RBFont.label(15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RBColor.accentGradient)
                        .clipShape(Capsule())
                    }

                    Button {
                        saveToPhotos()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 16, weight: .bold))
                            Text("저장")
                                .font(RBFont.label(15))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 100)
                        .frame(height: 50)
                        .background(RBColor.cardBgLight)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)

                Button("닫기") {
                    dismiss()
                }
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textSecondary)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { generateMapSnapshot() }
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedPhoto = uiImage
                }
            }
        }
    }

    // MARK: - 카드 내용

    private var cardContent: some View {
        VStack(spacing: 0) {
            // 상단 그라데이션 헤더
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.05, blue: 0.0),
                        Color(red: 0.1, green: 0.02, blue: 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 레이저 라인 이펙트
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height * 0.6))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.3))
                    }
                    .stroke(
                        RBColor.laserRed.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5)
                    )
                    .shadow(color: RBColor.laserRed.opacity(0.6), radius: 6)

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height * 0.7))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.4))
                    }
                    .stroke(
                        RBColor.accent.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1)
                    )
                    .shadow(color: RBColor.accent.opacity(0.4), radius: 4)
                }

                VStack(spacing: 4) {
                    HStack {
                        LaserDot(size: 8, glowRadius: 4)
                        Text("BEAMCHASER")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(RBColor.accent)
                            .tracking(3)
                        Spacer()
                        Text(record.startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(RBFont.caption(10))
                            .foregroundStyle(RBColor.textTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Spacer()
                }
            }
            .frame(height: 60)

            // 경로 지도
            if let mapSnapshot {
                Image(uiImage: mapSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
            }

            // 메인 수치
            VStack(spacing: 16) {
                // 거리 (대형)
                VStack(spacing: 2) {
                    Text("DISTANCE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(2)
                    Text(record.formattedDistance)
                        .font(RBFont.hero(48))
                        .foregroundStyle(.white)
                }
                .padding(.top, 16)

                // 3칸 메트릭
                HStack(spacing: 0) {
                    shareMetric(label: "시간", value: record.formattedDuration)
                    Rectangle().fill(RBColor.divider).frame(width: 1, height: 32)
                    shareMetric(label: "평균 페이스", value: record.formattedPace)
                    if record.targetPace != nil {
                        Rectangle().fill(RBColor.divider).frame(width: 1, height: 32)
                        shareMetric(label: "일치율", value: paceMatchRate)
                    }
                }
                .padding(.horizontal, 16)

                // 목표 페이스 달성 배지
                if let target = record.targetPace {
                    let diff = record.averagePaceSecondsPerKm - target.totalSecondsPerKm
                    let achieved = diff <= 0

                    HStack(spacing: 8) {
                        Image(systemName: achieved ? "checkmark.seal.fill" : "xmark.seal")
                            .font(.system(size: 14))
                            .foregroundStyle(achieved ? RBColor.success : RBColor.danger)
                        Text("목표 \(target.formatted)")
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                        Text(achieved ? "달성!" : String(format: "+%d초", Int(diff)))
                            .font(RBFont.label(12))
                            .foregroundStyle(achieved ? RBColor.success : RBColor.danger)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background((achieved ? RBColor.success : RBColor.danger).opacity(0.1))
                    .clipShape(Capsule())
                }

                // 인증 사진
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                }

                // 하단 워터마크
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        LaserDot(size: 5, glowRadius: 2)
                        Text("BeamChaser")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(RBColor.textTertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func shareMetric(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)
            Text(value)
                .font(RBFont.metric(20))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var paceMatchRate: String {
        guard let target = record.targetPace, target.totalSecondsPerKm > 0 else { return "-" }
        let ratio = min(target.totalSecondsPerKm / record.averagePaceSecondsPerKm, record.averagePaceSecondsPerKm / target.totalSecondsPerKm)
        return String(format: "%.0f%%", ratio * 100)
    }

    // MARK: - 공유 / 저장

    @MainActor
    private func shareCard() {
        let renderer = ImageRenderer(content: cardContent.frame(width: 320))
        renderer.scale = 3.0
        guard let image = renderer.uiImage else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }

    @MainActor
    private func saveToPhotos() {
        let renderer = ImageRenderer(content: cardContent.frame(width: 320))
        renderer.scale = 3.0
        guard let image = renderer.uiImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    // MARK: - 지도 스냅샷

    private func generateMapSnapshot() {
        guard record.routePoints.count >= 2 else { return }

        let coords = record.routePoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        let rect = polyline.boundingMapRect
        let insetRect = rect.insetBy(dx: -rect.size.width * 0.25, dy: -rect.size.height * 0.25)

        let options = MKMapSnapshotter.Options()
        options.mapRect = insetRect
        options.size = CGSize(width: 640, height: 240)
        options.scale = UIScreen.main.scale

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot else { return }

            let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)

                let path = UIBezierPath()
                for (i, coord) in coords.enumerated() {
                    let point = snapshot.point(for: coord)
                    if i == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
                UIColor.orange.setStroke()
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()

                // 시작점
                if let first = coords.first {
                    let p = snapshot.point(for: first)
                    UIColor.systemGreen.setFill()
                    UIBezierPath(arcCenter: p, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
                    UIColor.white.setStroke()
                    let c = UIBezierPath(arcCenter: p, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                    c.lineWidth = 2
                    c.stroke()
                }

                // 끝점
                if let last = coords.last {
                    let p = snapshot.point(for: last)
                    UIColor.systemRed.setFill()
                    UIBezierPath(arcCenter: p, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
                    UIColor.white.setStroke()
                    let c = UIBezierPath(arcCenter: p, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                    c.lineWidth = 2
                    c.stroke()
                }
            }

            DispatchQueue.main.async {
                self.mapSnapshot = image
            }
        }
    }
}
