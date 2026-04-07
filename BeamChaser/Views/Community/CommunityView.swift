import SwiftUI
import MapKit
import PhotosUI

// MARK: - Community Data Models

struct RunnerPost: Identifiable {
    let id = UUID()
    let authorName: String
    let authorLevel: RunnerLevel
    let content: String
    let distanceKm: Double?
    let paceFormatted: String?
    let timeAgo: String
    var likes: Int
    var comments: [PostComment]
    let type: PostType
    var isLiked: Bool = false
    var photoData: Data? = nil

    enum PostType {
        case runResult
        case mateFinding
        case freeBoard
    }
}

struct PostComment: Identifiable {
    let id = UUID()
    let authorName: String
    let authorLevel: RunnerLevel
    let content: String
    let timeAgo: String
}

struct RunMatePost: Identifiable {
    let id = UUID()
    let authorName: String
    let authorLevel: RunnerLevel
    let title: String
    let location: String
    let coordinate: CLLocationCoordinate2D
    let date: String
    let time: String
    let targetPace: String
    let targetDistance: String
    var currentMembers: Int
    let maxMembers: Int
    let description: String
    let timeAgo: String
    var isJoined: Bool = false
}

// MARK: - Community ViewModel

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var matePosts: [RunMatePost]
    @Published var feedPosts: [RunnerPost]

    init() {
        matePosts = Self.initialMatePosts
        feedPosts = Self.initialFeedPosts
    }

    func toggleLike(postId: UUID) {
        guard let idx = feedPosts.firstIndex(where: { $0.id == postId }) else { return }
        feedPosts[idx].isLiked.toggle()
        feedPosts[idx].likes += feedPosts[idx].isLiked ? 1 : -1
    }

    func addComment(postId: UUID, content: String) {
        guard let idx = feedPosts.firstIndex(where: { $0.id == postId }) else { return }
        let comment = PostComment(
            authorName: "나",
            authorLevel: .starter,
            content: content,
            timeAgo: "방금"
        )
        feedPosts[idx].comments.append(comment)
    }

    func toggleJoin(postId: UUID) {
        guard let idx = matePosts.firstIndex(where: { $0.id == postId }) else { return }
        if matePosts[idx].isJoined {
            matePosts[idx].isJoined = false
            matePosts[idx].currentMembers -= 1
        } else if matePosts[idx].currentMembers < matePosts[idx].maxMembers {
            matePosts[idx].isJoined = true
            matePosts[idx].currentMembers += 1
        }
    }

    func addMatePost(_ post: RunMatePost) {
        matePosts.insert(post, at: 0)
    }

    func addFeedPost(_ post: RunnerPost) {
        feedPosts.insert(post, at: 0)
    }

    // MARK: - Sample Data

    private static var initialMatePosts: [RunMatePost] {
        [
            RunMatePost(
                authorName: "지민", authorLevel: .gold,
                title: "한강 반포 주말 러닝 같이 하실 분!",
                location: "반포한강공원",
                coordinate: CLLocationCoordinate2D(latitude: 37.5085, longitude: 126.9960),
                date: "3/30 (일)", time: "07:00",
                targetPace: "5\'30\"/km", targetDistance: "10km",
                currentMembers: 3, maxMembers: 6,
                description: "편하게 대화하면서 달려요. 초보도 환영합니다!",
                timeAgo: "2시간 전"
            ),
            RunMatePost(
                authorName: "현우", authorLevel: .silver,
                title: "여의도 야간 러닝 크루 모집",
                location: "여의도공원",
                coordinate: CLLocationCoordinate2D(latitude: 37.5284, longitude: 126.9345),
                date: "3/29 (토)", time: "21:00",
                targetPace: "6\'00\"/km", targetDistance: "5km",
                currentMembers: 2, maxMembers: 4,
                description: "레이저 페이스메이커 보면서 같이 달려요!",
                timeAgo: "5시간 전"
            ),
            RunMatePost(
                authorName: "소연", authorLevel: .laser,
                title: "잠실 인터벌 트레이닝 파트너",
                location: "잠실종합운동장",
                coordinate: CLLocationCoordinate2D(latitude: 37.5152, longitude: 127.0735),
                date: "4/1 (화)", time: "06:30",
                targetPace: "4\'30\"/km", targetDistance: "8km",
                currentMembers: 4, maxMembers: 4,
                description: "인터벌 5세트, 중급 이상 추천합니다.",
                timeAgo: "1일 전"
            ),
        ]
    }

    private static var initialFeedPosts: [RunnerPost] {
        [
            RunnerPost(
                authorName: "지민", authorLevel: .gold,
                content: "오늘 한강에서 10K 완주! BeamChaser 레이저 덕분에 페이스 유지 성공",
                distanceKm: 10.2, paceFormatted: "5\'24\"/km",
                timeAgo: "30분 전", likes: 12,
                comments: [
                    PostComment(authorName: "현우", authorLevel: .silver, content: "축하합니다! 대단해요", timeAgo: "20분 전"),
                    PostComment(authorName: "소연", authorLevel: .laser, content: "다음엔 같이 달려요!", timeAgo: "15분 전"),
                ],
                type: .runResult
            ),
            RunnerPost(
                authorName: "현우", authorLevel: .silver,
                content: "야간 러닝 크루 첫 모임 성공적! 다음에도 같이 달려요",
                distanceKm: 5.1, paceFormatted: "6\'10\"/km",
                timeAgo: "2시간 전", likes: 8,
                comments: [
                    PostComment(authorName: "지민", authorLevel: .gold, content: "다음엔 저도 참여할게요!", timeAgo: "1시간 전"),
                ],
                type: .runResult
            ),
            RunnerPost(
                authorName: "소연", authorLevel: .laser,
                content: "인터벌 트레이닝 꿀팁: 워치 + BeamChaser 레이저 조합이 최고예요.",
                distanceKm: nil, paceFormatted: nil,
                timeAgo: "5시간 전", likes: 24,
                comments: [],
                type: .freeBoard
            ),
        ]
    }
}

// MARK: - Community View

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @State private var selectedTab: CommunityTab = .mate
    @State private var showCreateMate = false
    @State private var showCreateFeed = false
    @State private var mapSearchText = ""
    @State private var mapSearchResults: [MKMapItem] = []
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    enum CommunityTab: String, CaseIterable {
        case mate = "러닝 메이트"
        case feed = "피드"

        var icon: String {
            switch self {
            case .mate: return "person.2.fill"
            case .feed: return "text.bubble.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    tabSelector
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ScrollView {
                        LazyVStack(spacing: 14) {
                            switch selectedTab {
                            case .mate:
                                mateContent
                            case .feed:
                                feedContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("커뮤니티")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedTab == .mate {
                            showCreateMate = true
                        } else {
                            showCreateFeed = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(RBColor.accent)
                    }
                }
            }
            .sheet(isPresented: $showCreateMate) {
                CreateMatePostView(viewModel: viewModel)
            }
            .sheet(isPresented: $showCreateFeed) {
                CreateFeedPostView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(CommunityTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.rawValue)
                            .font(RBFont.label(14))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : RBColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        selectedTab == tab
                            ? AnyShapeStyle(RBColor.accent.opacity(0.3))
                            : AnyShapeStyle(RBColor.cardBg)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Mate Content

    private var mateContent: some View {
        Group {
            mateMapPreview

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.accent)
                    Text("내 근처 러닝 모집")
                        .font(RBFont.label(14))
                        .foregroundStyle(RBColor.textPrimary)
                    Spacer()
                }
            }

            ForEach(viewModel.matePosts) { post in
                mateCard(post)
            }

            if viewModel.matePosts.isEmpty {
                emptyState(
                    icon: "person.2.slash",
                    title: "아직 모집 글이 없어요",
                    subtitle: "첫 번째 러닝 메이트 모집 글을 작성해보세요!"
                )
            }
        }
    }

    // MARK: - Map Preview

    private var mateMapPreview: some View {
        VStack(spacing: 0) {
            // 검색 바
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textTertiary)
                TextField("장소 검색 (예: 한강공원, 여의도)", text: $mapSearchText)
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textPrimary)
                    .onSubmit { searchMap() }

                if !mapSearchText.isEmpty {
                    Button {
                        mapSearchText = ""
                        mapSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(RBColor.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RBColor.cardBgLight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 검색 결과 리스트
            if !mapSearchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mapSearchResults, id: \.self) { item in
                            Button {
                                if let coord = item.placemark.location?.coordinate {
                                    withAnimation(.spring(response: 0.4)) {
                                        mapCameraPosition = .camera(
                                            MapCamera(centerCoordinate: coord, distance: 3000)
                                        )
                                    }
                                }
                                mapSearchResults = []
                                mapSearchText = item.name ?? ""
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 10))
                                    Text(item.name ?? "")
                                        .font(RBFont.caption(11))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(RBColor.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RBColor.accent.opacity(0.2))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            // 지도
            Map(position: $mapCameraPosition) {
                ForEach(viewModel.matePosts) { post in
                    Annotation(post.title, coordinate: post.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(RBColor.accent)
                                .background(Circle().fill(RBColor.bg).frame(width: 28, height: 28))
                            Text(post.location)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(RBColor.textPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(RBColor.cardBg.opacity(0.9))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func searchMap() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = mapSearchText
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let items = response?.mapItems {
                mapSearchResults = Array(items.prefix(8))
            }
        }
    }

    private func mateCard(_ post: RunMatePost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(levelColor(post.authorLevel).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text(String(post.authorName.prefix(1)))
                        .font(RBFont.label(14))
                        .foregroundStyle(levelColor(post.authorLevel))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(post.authorLevel.rawValue)
                            .font(RBFont.caption(9))
                            .foregroundStyle(levelColor(post.authorLevel))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelColor(post.authorLevel).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(post.timeAgo)
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                    Text("\(post.currentMembers)/\(post.maxMembers)")
                        .font(RBFont.metric(12))
                }
                .foregroundStyle(post.currentMembers >= post.maxMembers ? RBColor.textTertiary : RBColor.accent)
            }

            Text(post.title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)

            // Mini map
            Map {
                Annotation("", coordinate: post.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(RBColor.accent)
                }
            }
            .mapStyle(.standard(emphasis: .muted))
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                infoTag(icon: "mappin", text: post.location)
                infoTag(icon: "calendar", text: post.date)
                infoTag(icon: "clock", text: post.time)
            }

            HStack(spacing: 8) {
                infoTag(icon: "speedometer", text: post.targetPace)
                infoTag(icon: "flag", text: post.targetDistance)
            }

            if !post.description.isEmpty {
                Text(post.description)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(2)
            }

            if post.currentMembers < post.maxMembers || post.isJoined {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.toggleJoin(postId: post.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: post.isJoined ? "checkmark.circle.fill" : "hand.raised.fill")
                            .font(.system(size: 12))
                        Text(post.isJoined ? "참여 취소" : "참여하기")
                            .font(RBFont.label(13))
                    }
                    .foregroundStyle(RBColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(post.isJoined ? AnyShapeStyle(RBColor.cardBgLight) : AnyShapeStyle(RBColor.accentGradient))
                    .clipShape(Capsule())
                }
            } else {
                HStack {
                    Spacer()
                    Text("모집 마감")
                        .font(RBFont.label(12))
                        .foregroundStyle(RBColor.textTertiary)
                    Spacer()
                }
                .frame(height: 38)
                .background(RBColor.cardBgLight)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func infoTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(RBFont.caption(10))
        }
        .foregroundStyle(RBColor.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        Group {
            ForEach(viewModel.feedPosts) { post in
                FeedCardView(post: post, viewModel: viewModel)
            }

            if viewModel.feedPosts.isEmpty {
                emptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "아직 게시글이 없어요",
                    subtitle: "러닝 결과를 공유하고 다른 러너들과 소통해보세요!"
                )
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(RBColor.textTertiary)
            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textSecondary)
            Text(subtitle)
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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

// MARK: - Feed Card View (likes/comments)

struct FeedCardView: View {
    let post: RunnerPost
    @ObservedObject var viewModel: CommunityViewModel
    @State private var showComments = false
    @State private var newComment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(levelColor(post.authorLevel).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text(String(post.authorName.prefix(1)))
                        .font(RBFont.label(14))
                        .foregroundStyle(levelColor(post.authorLevel))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(post.authorLevel.rawValue)
                            .font(RBFont.caption(9))
                            .foregroundStyle(levelColor(post.authorLevel))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelColor(post.authorLevel).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(post.timeAgo)
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }

                Spacer()
            }

            Text(post.content)
                .font(RBFont.label(14))
                .foregroundStyle(RBColor.textPrimary)

            // 사진
            if let photoData = post.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let dist = post.distanceKm, let pace = post.paceFormatted {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 12))
                            .foregroundStyle(RBColor.accent)
                        Text(String(format: "%.2f km", dist))
                            .font(RBFont.metric(14))
                            .foregroundStyle(RBColor.textPrimary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 12))
                            .foregroundStyle(RBColor.accent)
                        Text(pace)
                            .font(RBFont.metric(14))
                            .foregroundStyle(RBColor.textPrimary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RBColor.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Like & Comment buttons
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.toggleLike(postId: post.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(post.isLiked ? RBColor.danger : RBColor.textSecondary)
                        Text("\(post.likes)")
                            .font(RBFont.caption(12))
                    }
                    .foregroundStyle(post.isLiked ? RBColor.danger : RBColor.textSecondary)
                }

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showComments.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showComments ? "bubble.right.fill" : "bubble.right")
                            .font(.system(size: 14))
                        Text("\(post.comments.count)")
                            .font(RBFont.caption(12))
                    }
                    .foregroundStyle(showComments ? RBColor.accent : RBColor.textSecondary)
                }

                Spacer()
            }

            // Comments section
            if showComments {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(Color.white.opacity(0.08))

                    ForEach(post.comments) { comment in
                        HStack(alignment: .top, spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(levelColor(comment.authorLevel).opacity(0.2))
                                    .frame(width: 24, height: 24)
                                Text(String(comment.authorName.prefix(1)))
                                    .font(RBFont.caption(10))
                                    .foregroundStyle(levelColor(comment.authorLevel))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(comment.authorName)
                                        .font(RBFont.label(11))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text(comment.timeAgo)
                                        .font(RBFont.caption(9))
                                        .foregroundStyle(RBColor.textTertiary)
                                }
                                Text(comment.content)
                                    .font(RBFont.caption(12))
                                    .foregroundStyle(RBColor.textSecondary)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("댓글 입력...", text: $newComment)
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RBColor.cardBgLight)
                            .clipShape(Capsule())

                        Button {
                            guard !newComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            viewModel.addComment(postId: post.id, content: newComment)
                            newComment = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(newComment.isEmpty ? RBColor.textTertiary : RBColor.accent)
                                .frame(width: 36, height: 36)
                                .background(RBColor.cardBgLight)
                                .clipShape(Circle())
                        }
                        .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

// MARK: - Create Mate Post View

struct CreateMatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CommunityViewModel
    @State private var title = ""
    @State private var location = ""
    @State private var date = Date()
    @State private var targetPace = "5'30\""
    @State private var targetDistance = "5km"
    @State private var maxMembers = 4
    @State private var description = ""
    @State private var selectedCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    @State private var mapCameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780), distance: 5000)
    )
    @State private var showCalendar = true
    @State private var locationSearchText = ""
    @State private var locationSearchResults: [MKMapItem] = []
    @State private var isManualMemberInput = false
    @State private var manualMemberText = "4"

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !location.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 제목
                        inputField(title: "제목", placeholder: "러닝 메이트 모집 제목", text: $title)

                        // ── 날짜 및 시간 (달력 기본 표시, 접기 가능) ──
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showCalendar.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 13))
                                        .foregroundStyle(RBColor.accent)
                                    Text("날짜 및 시간")
                                        .font(RBFont.label(14))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Spacer()
                                    Text(dateFormatted)
                                        .font(RBFont.caption(12))
                                        .foregroundStyle(RBColor.accent)
                                    Image(systemName: showCalendar ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11))
                                        .foregroundStyle(RBColor.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if showCalendar {
                                VStack(spacing: 8) {
                                    DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date])
                                        .datePickerStyle(.graphical)
                                        .tint(RBColor.accent)
                                        .labelsHidden()

                                    DatePicker("시간 선택", selection: $date, displayedComponents: .hourAndMinute)
                                        .font(RBFont.label(13))
                                        .foregroundStyle(RBColor.textPrimary)
                                        .tint(RBColor.accent)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // ── 장소 검색 ──
                        VStack(alignment: .leading, spacing: 8) {
                            Text("모임 장소")
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)

                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13))
                                    .foregroundStyle(RBColor.textTertiary)
                                TextField("장소 검색 (예: 반포한강공원)", text: $locationSearchText)
                                    .font(RBFont.label(14))
                                    .foregroundStyle(RBColor.textPrimary)
                                    .onSubmit { searchLocation() }
                                if !locationSearchText.isEmpty {
                                    Button {
                                        locationSearchText = ""
                                        locationSearchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(RBColor.textTertiary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(RBColor.cardBgLight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            // 검색 결과
                            if !locationSearchResults.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(locationSearchResults, id: \.self) { item in
                                        Button {
                                            selectLocation(item)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(RBColor.accent)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name ?? "")
                                                        .font(RBFont.label(13))
                                                        .foregroundStyle(RBColor.textPrimary)
                                                    if let subtitle = item.placemark.thoroughfare ?? item.placemark.locality {
                                                        Text(subtitle)
                                                            .font(RBFont.caption(10))
                                                            .foregroundStyle(RBColor.textTertiary)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 4)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        if item != locationSearchResults.last {
                                            Divider().background(Color.white.opacity(0.06))
                                        }
                                    }
                                }
                                .padding(8)
                                .background(RBColor.cardBgLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            // 선택된 장소 표시
                            if !location.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(RBColor.success)
                                    Text(location)
                                        .font(RBFont.label(13))
                                        .foregroundStyle(RBColor.textPrimary)
                                }
                            }

                            // 미니 지도
                            Map(position: $mapCameraPosition) {
                                Annotation("모임 장소", coordinate: selectedCoordinate) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(RBColor.accent)
                                }
                            }
                            .mapStyle(.standard(emphasis: .muted))
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .allowsHitTesting(false)
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // 목표 페이스 / 거리
                        HStack(spacing: 12) {
                            inputField(title: "목표 페이스", placeholder: "5'30\"", text: $targetPace)
                            inputField(title: "목표 거리", placeholder: "5km", text: $targetDistance)
                        }

                        // ── 최대 인원 (+/- 버튼 + 직접 입력) ──
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("최대 인원")
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textTertiary)
                                Spacer()
                                Button {
                                    withAnimation {
                                        isManualMemberInput.toggle()
                                        manualMemberText = "\(maxMembers)"
                                    }
                                } label: {
                                    Text(isManualMemberInput ? "버튼 모드" : "직접 입력")
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(RBColor.accent)
                                }
                            }

                            if isManualMemberInput {
                                HStack(spacing: 12) {
                                    TextField("인원 수", text: $manualMemberText)
                                        .font(RBFont.metric(24))
                                        .foregroundStyle(RBColor.textPrimary)
                                        .multilineTextAlignment(.center)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(RBColor.cardBgLight)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .onChange(of: manualMemberText) { _, newVal in
                                            if let num = Int(newVal), num >= 2 {
                                                maxMembers = min(num, 50)
                                            }
                                        }
                                    Text("명")
                                        .font(RBFont.label(14))
                                        .foregroundStyle(RBColor.textSecondary)
                                }
                            } else {
                                HStack(spacing: 16) {
                                    Button {
                                        if maxMembers > 2 { maxMembers -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(RBColor.textPrimary)
                                            .frame(width: 40, height: 40)
                                            .background(RBColor.cardBgLight)
                                            .clipShape(Circle())
                                    }

                                    Spacer()

                                    Text("\(maxMembers)")
                                        .font(RBFont.metric(28))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text("명")
                                        .font(RBFont.label(14))
                                        .foregroundStyle(RBColor.textSecondary)

                                    Spacer()

                                    Button {
                                        if maxMembers < 50 { maxMembers += 1 }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(RBColor.textPrimary)
                                            .frame(width: 40, height: 40)
                                            .background(RBColor.cardBgLight)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // ── 상세 설명 (3줄 높이) ──
                        VStack(alignment: .leading, spacing: 6) {
                            Text("상세 설명")
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)
                            TextEditor(text: $description)
                                .font(RBFont.label(14))
                                .foregroundStyle(RBColor.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(height: 72)
                                .padding(10)
                                .background(RBColor.cardBgLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        RBPrimaryButton("모집 글 올리기", icon: "paperplane.fill") {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "M/d (E)"
                            formatter.locale = Locale(identifier: "ko_KR")
                            let dateStr = formatter.string(from: date)
                            let timeFormatter = DateFormatter()
                            timeFormatter.dateFormat = "HH:mm"
                            let timeStr = timeFormatter.string(from: date)

                            let newPost = RunMatePost(
                                authorName: "나",
                                authorLevel: .starter,
                                title: title,
                                location: location,
                                coordinate: selectedCoordinate,
                                date: dateStr,
                                time: timeStr,
                                targetPace: targetPace,
                                targetDistance: targetDistance,
                                currentMembers: 1,
                                maxMembers: maxMembers,
                                description: description,
                                timeAgo: "방금"
                            )
                            viewModel.addMatePost(newPost)
                            dismiss()
                        }
                        .disabled(!isValid)
                        .opacity(isValid ? 1.0 : 0.5)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("러닝 메이트 모집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
    }

    private var dateFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "M/d (E) HH:mm"
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }

    private func searchLocation() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationSearchText
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        MKLocalSearch(request: request).start { response, _ in
            if let items = response?.mapItems {
                locationSearchResults = Array(items.prefix(6))
            }
        }
    }

    private func selectLocation(_ item: MKMapItem) {
        location = item.name ?? ""
        locationSearchText = item.name ?? ""
        locationSearchResults = []
        if let coord = item.placemark.location?.coordinate {
            selectedCoordinate = coord
            withAnimation(.spring(response: 0.4)) {
                mapCameraPosition = .camera(
                    MapCamera(centerCoordinate: coord, distance: 3000)
                )
            }
        }
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textTertiary)
            TextField(placeholder, text: text)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
                .padding(12)
                .background(RBColor.cardBgLight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Create Feed Post View

struct CreateFeedPostView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CommunityViewModel
    @State private var content = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?

    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 내용 입력
                        VStack(alignment: .leading, spacing: 6) {
                            Text("내용")
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)

                            TextEditor(text: $content)
                                .font(RBFont.label(15))
                                .foregroundStyle(RBColor.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(RBColor.cardBgLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // 사진 선택
                        VStack(alignment: .leading, spacing: 8) {
                            Text("사진 (선택)")
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)

                            if let photoData = selectedPhotoData, let uiImage = UIImage(data: photoData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button {
                                        withAnimation {
                                            selectedPhotoData = nil
                                            selectedPhotoItem = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(RBColor.textPrimary)
                                            .background(Circle().fill(.black.opacity(0.5)))
                                    }
                                    .padding(8)
                                }
                            }

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 14))
                                    Text(selectedPhotoData == nil ? "사진 추가" : "사진 변경")
                                        .font(RBFont.label(13))
                                }
                                .foregroundStyle(RBColor.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(RBColor.cardBgLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                        selectedPhotoData = data
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Spacer(minLength: 20)

                        RBPrimaryButton("게시하기", icon: "paperplane.fill") {
                            let newPost = RunnerPost(
                                authorName: "나",
                                authorLevel: .starter,
                                content: content,
                                distanceKm: nil,
                                paceFormatted: nil,
                                timeAgo: "방금",
                                likes: 0,
                                comments: [],
                                type: .freeBoard,
                                photoData: selectedPhotoData
                            )
                            viewModel.addFeedPost(newPost)
                            dismiss()
                        }
                        .disabled(!isValid)
                        .opacity(isValid ? 1.0 : 0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("글 작성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
    }
}

#Preview {
    CommunityView()
}
