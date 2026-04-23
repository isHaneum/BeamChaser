import SwiftUI
import PhotosUI

struct BackgroundEditScreen: View {
    let appLanguage: AppLanguage
    @Binding var backgroundOption: ShareBackgroundOption
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var selectedPhotoImage: UIImage?

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(appLanguage.text("배경 편집", "Background"))
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(Color.black.opacity(0.88))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(appLanguage.text("완료", "Done"))
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(sharePrimaryColor)
                        .frame(width: 46, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    backgroundTile(option: .white)
                    photoTile
                    backgroundTile(option: .gradient)
                    backgroundTile(option: .transparent)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.95).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private func backgroundTile(option: ShareBackgroundOption) -> some View {
        let selected = backgroundOption == option

        return Button {
            backgroundOption = option
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                backgroundPreview(for: option)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(option.title(appLanguage))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(Color.black.opacity(0.76))
            }
            .padding(12)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(selected ? sharePrimaryColor : Color.black.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var photoTile: some View {
        let selected = backgroundOption == .photo

        return PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            VStack(alignment: .leading, spacing: 12) {
                backgroundPreview(for: .photo)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .opacity(selectedPhotoImage == nil ? 0.65 : 1)

                Text(ShareBackgroundOption.photo.title(appLanguage))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(Color.black.opacity(0.76))
            }
            .padding(12)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(selected ? sharePrimaryColor : Color.black.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .onChange(of: selectedPhotoItem) { _, _ in
            backgroundOption = .photo
        }
    }

    private func backgroundPreview(for option: ShareBackgroundOption) -> some View {
        ZStack {
            switch option {
            case .white:
                Color.white
            case .photo:
                if let selectedPhotoImage {
                    Image(uiImage: selectedPhotoImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.92, green: 0.91, blue: 0.89), Color(red: 0.82, green: 0.81, blue: 0.79)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .gradient:
                LinearGradient(
                    colors: [sharePrimaryColor, Color.black.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .transparent:
                checkerboardPreview
            }

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var checkerboardPreview: some View {
        GeometryReader { geometry in
            let columns = 4
            let rows = 6
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            ZStack {
                Color.white
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? Color.black.opacity(0.06) : Color.clear)
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: cellWidth * (CGFloat(column) + 0.5),
                                y: cellHeight * (CGFloat(row) + 0.5)
                            )
                    }
                }
            }
        }
    }
}
