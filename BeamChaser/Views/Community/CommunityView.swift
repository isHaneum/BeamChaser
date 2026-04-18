import SwiftUI
import MapKit
import PhotosUI
import UIKit

// MARK: - Community Data Models

struct RunnerPost: Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorLevel: RunnerLevel
    let content: String
    let distanceKm: Double?
    let paceFormatted: String?
    let createdAt: Date
    var likes: Int
    var comments: [PostComment]
    let type: PostType
    var isLiked: Bool = false
    var photoURL: String? = nil

    enum PostType: String {
        case runResult
        case mateFinding
        case freeBoard
    }

    var timeAgo: String {
        CommunityFormatter.relativeString(from: createdAt)
    }
}

struct PostComment: Identifiable {
    let id: String
    let authorName: String
    let authorLevel: RunnerLevel
    let content: String
    let createdAt: Date

    var timeAgo: String {
        CommunityFormatter.relativeString(from: createdAt)
    }
}

struct RunMatePost: Identifiable {
    let id: String
    let authorId: String
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
    let createdAt: Date
    var isJoined: Bool = false

    var timeAgo: String {
        CommunityFormatter.relativeString(from: createdAt)
    }
}

struct CommunityFriend: Identifiable {
    let id: String
    let name: String
    let level: RunnerLevel
    let totalDistanceKm: Double
    let totalRuns: Int

    var recordSummary: String {
        "\(totalRuns)회 · \(String(format: "%.1f", totalDistanceKm))km"
    }
}

enum CommunityFeedScope: String, CaseIterable {
    case all = "전체 피드"
    case friends = "친구 피드"
}

enum CommunityFormatter {
    static func relativeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension RunnerPost.PostType {
    init(firestoreValue: String) {
        switch firestoreValue {
        case "runResult":
            self = .runResult
        case "mateFinding":
            self = .mateFinding
        default:
            self = .freeBoard
        }
    }

    var firestoreValue: String {
        rawValue
    }
}

// MARK: - Community ViewModel

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var matePosts: [RunMatePost] = []
    @Published var feedPosts: [RunnerPost] = []
    @Published var suggestedFriends: [CommunityFriend] = []
    @Published var friends: [CommunityFriend] = []
    @Published var feedScope: CommunityFeedScope = .all {
        didSet { applyFeedFilter() }
    }
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var blockedUserIds: Set<String> = []

    private var backendService: BackendService?
    private var allFeedPosts: [RunnerPost] = []
    private var currentUserId: String?
    private var friendIds: Set<String> = []
    private var userDirectory: [String: FirestoreUser] = [:]

    func configure(backendService: BackendService) {
        guard self.backendService !== backendService else { return }
        self.backendService = backendService
    }

    private func presentableMessage(for error: Error, fallback: String) -> String {
        let nsError = error as NSError
        let localized = nsError.localizedDescription.lowercased()

        if (nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7)
            || localized.contains("missing or insufficient permissions")
            || localized.contains("insufficient permissions") {
            return "커뮤니티 권한을 확인해주세요."
        }

        return fallback
    }

    func reload() async {
        guard let backendService else { return }
        guard backendService.isSignedIn else {
            matePosts = []
            feedPosts = []
            allFeedPosts = []
            suggestedFriends = []
            friends = []
            friendIds = []
            userDirectory = [:]
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 네 작업을 동시에 시작하되, 유저 목록·친구 목록은 soft-fail 처리
        // (Firestore 보안 규칙에서 컬렉션 전체 읽기가 막혀도 포스트는 보여줌)
        async let usersTask   = backendService.fetchUsers(limit: 100)
        async let friendsTask = backendService.fetchFriends()
        async let blockedTask = backendService.fetchBlockedUsers()
        async let mateTask    = backendService.fetchMatePosts()
        async let feedTask    = backendService.fetchFeedPosts()

        let users       = (try? await usersTask)   ?? []
        let friendLinks = (try? await friendsTask) ?? []
        let blocked     = (try? await blockedTask) ?? []
        blockedUserIds  = Set(blocked)

        do {
            let fetchedMatePosts = try await mateTask
            let fetchedFeedPosts = try await feedTask

            currentUserId = backendService.userId
            userDirectory = Dictionary(uniqueKeysWithValues: users.map { ($0.uid, $0) })
            friendIds = Set(friendLinks.map(\.friendId))

            let sortedUsers = users.sorted { lhs, rhs in
                if lhs.totalDistanceKm == rhs.totalDistanceKm {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.totalDistanceKm > rhs.totalDistanceKm
            }

            friends = sortedUsers
                .filter { friendIds.contains($0.uid) }
                .map { makeCommunityFriend(from: $0) }

            suggestedFriends = sortedUsers
                .filter { user in
                    guard let currentUserId else { return false }
                    return user.uid != currentUserId && !friendIds.contains(user.uid)
                }
                .prefix(12)
                .map { makeCommunityFriend(from: $0) }

            matePosts = fetchedMatePosts
                .sorted { $0.createdAt > $1.createdAt }
                .filter { !blockedUserIds.contains($0.authorId) }
                .map { makeMatePost(from: $0) }

            allFeedPosts = fetchedFeedPosts
                .sorted { $0.createdAt > $1.createdAt }
                .filter { !blockedUserIds.contains($0.authorId) }
                .map { makeRunnerPost(from: $0) }

            applyFeedFilter()
            errorMessage = nil
        } catch {
            errorMessage = presentableMessage(for: error, fallback: "커뮤니티를 불러오지 못했어요.")
        }
    }

    func addFriend(friendId: String) async {
        guard let backendService else { return }
        guard backendService.isSignedIn else {
            errorMessage = "친구 추가는 로그인 후 사용할 수 있어요."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.addFriend(friendId: friendId)
            await reload()
        } catch {
            errorMessage = "친구 추가 실패: \(error.localizedDescription)"
        }
    }

    func toggleLike(postId: String) async {
        guard let backendService else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.toggleLikeFeedPost(postId: postId)
            await reload()
        } catch {
            errorMessage = "좋아요 반영 실패: \(error.localizedDescription)"
        }
    }

    func addComment(postId: String, content: String) async {
        guard
            let backendService,
            let userId = backendService.userId
        else {
            errorMessage = "댓글 작성은 로그인 후 사용할 수 있어요."
            return
        }

        let author = userDirectory[userId] ?? backendService.currentUser
        let comment = FirestoreComment(
            id: UUID().uuidString,
            authorId: userId,
            authorName: author?.displayName ?? "러너",
            authorLevel: author?.level ?? RunnerLevel.starter.rawValue,
            content: content,
            createdAt: Date()
        )

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.addCommentToFeedPost(postId: postId, comment: comment)
            await reload()
        } catch {
            errorMessage = "댓글 저장 실패: \(error.localizedDescription)"
        }
    }

    func toggleJoin(postId: String) async {
        guard let backendService else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.toggleJoinMatePost(postId: postId)
            await reload()
        } catch {
            errorMessage = "참여 상태 반영 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Moderation

    func reportPost(targetId: String, targetType: String, reason: String) async {
        guard let backendService else { return }
        do {
            try await backendService.reportContent(
                targetId: targetId,
                targetType: targetType,
                reason: reason
            )
        } catch {
            errorMessage = "신고를 전송하지 못했어요."
        }
    }

    func blockUser(userId: String) async {
        guard let backendService else { return }
        do {
            try await backendService.blockUser(uid: userId)
            blockedUserIds.insert(userId)
            allFeedPosts = allFeedPosts.filter { $0.authorId != userId }
            applyFeedFilter()
            matePosts = matePosts.filter { $0.authorId != userId }
        } catch {
            errorMessage = "차단할 수 없었어요."
        }
    }

    func createMatePost(
        title: String,
        location: String,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        targetPace: String,
        targetDistance: String,
        maxMembers: Int,
        description: String
    ) async -> Bool {
        guard
            let backendService,
            let userId = backendService.userId
        else {
            errorMessage = "메이트 모집은 로그인 후 사용할 수 있어요."
            return false
        }

        let author = userDirectory[userId] ?? backendService.currentUser
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d (E)"
        dateFormatter.locale = Locale(identifier: "ko_KR")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = Locale(identifier: "ko_KR")

        let post = FirestoreMatePost(
            id: UUID().uuidString,
            authorId: userId,
            authorName: author?.displayName ?? "러너",
            authorLevel: author?.level ?? RunnerLevel.starter.rawValue,
            title: title,
            location: location,
            latitude: approximateCoordinate(coordinate.latitude),
            longitude: approximateCoordinate(coordinate.longitude),
            date: dateFormatter.string(from: date),
            time: timeFormatter.string(from: date),
            targetPace: targetPace,
            targetDistance: targetDistance,
            currentMembers: 1,
            maxMembers: maxMembers,
            description: description,
            joinedUserIds: [userId],
            createdAt: Date()
        )

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.createMatePost(post)
            await reload()
            return true
        } catch {
            errorMessage = "메이트 모집 글 저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    func createFeedPost(content: String, photoData: Data?) async -> Bool {
        guard
            let backendService,
            let userId = backendService.userId
        else {
            errorMessage = "피드 작성은 로그인 후 사용할 수 있어요."
            return false
        }

        let author = userDirectory[userId] ?? backendService.currentUser

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            var photoURL: String?
            if let photoData {
                let uploadData: Data
                if let image = UIImage(data: photoData),
                   let jpegData = image.jpegData(compressionQuality: 0.85) {
                    uploadData = jpegData
                } else {
                    uploadData = photoData
                }

                photoURL = try await backendService.uploadPhoto(
                    data: uploadData,
                    path: "feed_photos/\(userId)/\(UUID().uuidString).jpg"
                )
            }

            let post = FirestoreFeedPost(
                id: UUID().uuidString,
                authorId: userId,
                authorName: author?.displayName ?? "러너",
                authorLevel: author?.level ?? RunnerLevel.starter.rawValue,
                content: content,
                distanceKm: nil,
                paceFormatted: nil,
                photoURL: photoURL,
                likedUserIds: [],
                comments: [],
                type: RunnerPost.PostType.freeBoard.firestoreValue,
                createdAt: Date()
            )

            try await backendService.createFeedPost(post)
            await reload()
            return true
        } catch {
            errorMessage = "피드 업로드 실패: \(error.localizedDescription)"
            return false
        }
    }

    private func approximateCoordinate(_ value: Double) -> Double {
        // 소수점 3자리로 완화해 약 100m 단위의 위치만 공유합니다.
        (value * 1000).rounded() / 1000
    }

    private func applyFeedFilter() {
        switch feedScope {
        case .all:
            feedPosts = allFeedPosts
        case .friends:
            feedPosts = allFeedPosts.filter { friendIds.contains($0.authorId) }
        }
    }

    private func makeCommunityFriend(from user: FirestoreUser) -> CommunityFriend {
        CommunityFriend(
            id: user.uid,
            name: user.displayName,
            level: RunnerLevel(rawValue: user.level) ?? .starter,
            totalDistanceKm: user.totalDistanceKm,
            totalRuns: user.totalRuns
        )
    }

    private func makeMatePost(from post: FirestoreMatePost) -> RunMatePost {
        RunMatePost(
            id: post.id,
            authorId: post.authorId,
            authorName: post.authorName,
            authorLevel: RunnerLevel(rawValue: post.authorLevel) ?? .starter,
            title: post.title,
            location: post.location,
            coordinate: CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude),
            date: post.date,
            time: post.time,
            targetPace: post.targetPace,
            targetDistance: post.targetDistance,
            currentMembers: post.currentMembers,
            maxMembers: post.maxMembers,
            description: post.description,
            createdAt: post.createdAt,
            isJoined: post.joinedUserIds.contains(currentUserId ?? "")
        )
    }

    private func makeRunnerPost(from post: FirestoreFeedPost) -> RunnerPost {
        RunnerPost(
            id: post.id,
            authorId: post.authorId,
            authorName: post.authorName,
            authorLevel: RunnerLevel(rawValue: post.authorLevel) ?? .starter,
            content: post.content,
            distanceKm: post.distanceKm,
            paceFormatted: post.paceFormatted,
            createdAt: post.createdAt,
            likes: post.likedUserIds.count,
            comments: post.comments
                .sorted { $0.createdAt < $1.createdAt }
                .map {
                    PostComment(
                        id: $0.id,
                        authorName: $0.authorName,
                        authorLevel: RunnerLevel(rawValue: $0.authorLevel) ?? .starter,
                        content: $0.content,
                        createdAt: $0.createdAt
                    )
                },
            type: RunnerPost.PostType(firestoreValue: post.type),
            isLiked: post.likedUserIds.contains(currentUserId ?? ""),
            photoURL: post.photoURL
        )
    }
}

// MARK: - Community View

struct CommunityView: View {
    @EnvironmentObject private var backendService: BackendService
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @StateObject private var viewModel = CommunityViewModel()
    @State private var selectedTab: CommunityTab = .mate
    @State private var selectedMateMode: MateMode = .friends
    @State private var showCreateMate = false
    @State private var showCreateFeed = false
    @State private var mapSearchText = ""
    @State private var mapSearchResults: [MKMapItem] = []
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    // 모집 글 신고/차단
    @State private var moderationTarget: (id: String, type: String, authorId: String)? = nil
    @State private var showMateReportDialog = false
    @State private var showBlockConfirm = false

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

    enum MateMode: String, CaseIterable {
        case friends = "친구"
        case discover = "찾기"

        var icon: String {
            switch self {
            case .friends: return "person.2.wave.2.fill"
            case .discover: return "location.magnifyingglass"
            }
        }
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    stickyHeader

                    if !backendService.isSignedIn {
                        signInRequiredState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                if let error = viewModel.errorMessage {
                                    errorBanner(error)
                                }

                                if viewModel.isLoading && viewModel.matePosts.isEmpty && viewModel.feedPosts.isEmpty {
                                    ProgressView()
                                        .tint(RBColor.accent)
                                        .padding(.top, 40)
                                }

                                switch selectedTab {
                                case .mate:
                                    mateContent
                                case .feed:
                                    feedContent
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        }
                        .refreshable {
                            await viewModel.reload()
                        }
                        .contentMargins(.bottom, 100, for: .scrollContent)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateMate) {
                CreateMatePostView(viewModel: viewModel)
            }
            .sheet(isPresented: $showCreateFeed) {
                CreateFeedPostView(viewModel: viewModel)
            }
            .confirmationDialog(
                appLanguage.text("신고 사유를 선택하세요", "Select a reason"),
                isPresented: $showMateReportDialog,
                titleVisibility: .visible
            ) {
                Button(appLanguage.text("스팸", "Spam")) {
                    if let t = moderationTarget {
                        Task { await viewModel.reportPost(targetId: t.id, targetType: t.type, reason: "스팸") }
                    }
                }
                Button(appLanguage.text("욕설 / 혐오 발언", "Hate speech")) {
                    if let t = moderationTarget {
                        Task { await viewModel.reportPost(targetId: t.id, targetType: t.type, reason: "욕설/혐오 발언") }
                    }
                }
                Button(appLanguage.text("부적절한 콘텐츠", "Inappropriate content")) {
                    if let t = moderationTarget {
                        Task { await viewModel.reportPost(targetId: t.id, targetType: t.type, reason: "부적절한 콘텐츠") }
                    }
                }
                Button(appLanguage.text("허위 정보", "False information")) {
                    if let t = moderationTarget {
                        Task { await viewModel.reportPost(targetId: t.id, targetType: t.type, reason: "허위 정보") }
                    }
                }
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) { moderationTarget = nil }
            }
            .alert(
                appLanguage.text("이 사용자를 차단할까요?", "Block this user?"),
                isPresented: $showBlockConfirm
            ) {
                Button(appLanguage.text("차단", "Block"), role: .destructive) {
                    if let t = moderationTarget {
                        Task { await viewModel.blockUser(userId: t.authorId) }
                        moderationTarget = nil
                    }
                }
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) { moderationTarget = nil }
            } message: {
                Text(appLanguage.text(
                    "차단하면 이 사용자의 게시글이 표시되지 않습니다.",
                    "You won't see posts from this user."
                ))
            }
            .task(id: backendService.userId) {
                viewModel.configure(backendService: backendService)
                await viewModel.reload()
            }
        }
    }

    private var stickyHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(appLanguage.text("커뮤니티", "Community"))
                        .font(RBFont.hero(28))
                        .foregroundStyle(RBColor.textPrimary)
                }

                Spacer()

                if backendService.isSignedIn {
                    addButton
                }
            }

            tabSelector

            if selectedTab == .mate {
                mateModeSelector
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            VStack(spacing: 0) {
                RBColor.bg.opacity(0.96)
                Rectangle()
                    .fill(RBColor.divider.opacity(0.7))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
        )
    }

    private var addButton: some View {
        Button {
            if selectedTab == .mate {
                showCreateMate = true
            } else {
                showCreateFeed = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(RBColor.accentGradient)
                    .frame(width: 52, height: 52)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .heavy))
            }
            .foregroundStyle(.white)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: RBColor.accent.opacity(0.35), radius: 14, y: 8)
        }
        .accessibilityLabel(selectedTab == .mate ? appLanguage.text("모집 글 추가", "Add mate post") : appLanguage.text("피드 추가", "Add feed post"))
    }

    private var signInRequiredState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(RBColor.textTertiary)
            Text(appLanguage.text("로그인 후 이용할 수 있어요", "Available after sign-in"))
                .font(RBFont.label(18))
                .foregroundStyle(RBColor.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RBColor.danger.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RBColor.danger)
            }
            Text(text)
                .font(RBFont.label(12))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(RBColor.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RBColor.danger.opacity(0.28), lineWidth: 1)
        )
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
                        Text(tab == .mate ? appLanguage.text("러닝 메이트", "Running Mate") : appLanguage.text("피드", "Feed"))
                            .font(RBFont.label(14))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : RBColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedTab == tab ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedTab == tab ? Color.white.opacity(0.08) : RBColor.divider.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: selectedTab == tab ? RBColor.accent.opacity(0.18) : .clear, radius: 12, y: 6)
                }
            }
        }
    }

    private var mateModeSelector: some View {
        HStack(spacing: 8) {
            ForEach(MateMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMateMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                        Text(mode == .friends ? appLanguage.text("친구", "Friends") : appLanguage.text("찾기", "Discover"))
                            .font(RBFont.label(13))
                    }
                    .foregroundStyle(selectedMateMode == mode ? .white : RBColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        Capsule()
                            .fill(selectedMateMode == mode ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                    }
                    .overlay(
                        Capsule()
                            .stroke(selectedMateMode == mode ? Color.white.opacity(0.08) : RBColor.divider.opacity(0.7), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Mate Content

    private var mateContent: some View {
        Group {
            switch selectedMateMode {
            case .friends:
                mateFriendsContent
            case .discover:
                mateDiscoverContent
            }
        }
    }

    private var mateFriendsContent: some View {
        Group {
            if !viewModel.friends.isEmpty {
                mateFriendsHero
                friendsRecordSection
            }

            if !viewModel.suggestedFriends.isEmpty {
                suggestedFriendsSection
            }

            if viewModel.friends.isEmpty && viewModel.suggestedFriends.isEmpty && !viewModel.isLoading {
                emptyState(
                    icon: "person.2.slash",
                    title: appLanguage.text("아직 연결된 러닝 친구가 없어요", "No running friends yet")
                )
            }
        }
    }

    private var mateDiscoverContent: some View {
        Group {
            mateMapPreview

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.accent)
                    Text(appLanguage.text("내 근처 러닝 모집", "Runs Near Me"))
                        .font(RBFont.label(14))
                        .foregroundStyle(RBColor.textPrimary)
                    Spacer()
                }
            }

            ForEach(viewModel.matePosts) { post in
                mateCard(
                    post,
                    onReport: {
                        moderationTarget = (post.id, "matePost", post.authorId)
                        showMateReportDialog = true
                    },
                    onBlock: {
                        moderationTarget = (post.id, "matePost", post.authorId)
                        showBlockConfirm = true
                    }
                )
            }

            if viewModel.matePosts.isEmpty && !viewModel.isLoading {
                emptyState(
                    icon: "person.2.slash",
                    title: appLanguage.text("아직 모집 글이 없어요", "No mate posts yet")
                )
            }
        }
    }

    private var mateMapPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textTertiary)
                TextField(
                    "",
                    text: $mapSearchText,
                    prompt: Text(appLanguage.text("장소 검색 (예: 한강공원, 여의도)", "Search places (e.g. Han River Park)"))
                        .foregroundStyle(RBColor.textSecondary)
                )
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
            .background(RBColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(RBColor.divider.opacity(0.7), lineWidth: 1)
            )

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
                                .background(RBColor.accent.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(RBColor.accent.opacity(0.35), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

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

    private var mateFriendsHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appLanguage.text("친구 네트워크", "Friend Network"))
                        .font(RBFont.label(18))
                        .foregroundStyle(RBColor.textPrimary)
                }
                Spacer()
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(RBColor.accent)
            }

            HStack(spacing: 10) {
                socialStatCard(
                    title: appLanguage.text("내 친구", "Friends"),
                    value: "\(viewModel.friends.count)",
                    subtitle: appLanguage.text("함께 뛰는 러너", "Connected runners")
                )
                socialStatCard(
                    title: appLanguage.text("추천", "Suggested"),
                    value: "\(viewModel.suggestedFriends.count)",
                    subtitle: appLanguage.text("추가 후보", "People to add")
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [RBColor.cardBg, RBColor.accent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private func mateCard(
        _ post: RunMatePost,
        onReport: @escaping () -> Void,
        onBlock: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(communityLevelColor(post.authorLevel).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text(String(post.authorName.prefix(1)))
                        .font(RBFont.label(14))
                        .foregroundStyle(communityLevelColor(post.authorLevel))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(post.authorLevel.rawValue)
                            .font(RBFont.caption(9))
                            .foregroundStyle(communityLevelColor(post.authorLevel))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(communityLevelColor(post.authorLevel).opacity(0.15))
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

                // MARK: 신고 / 차단 메뉴
                Menu {
                    Button(role: .destructive, action: onReport) {
                        Label(
                            appLanguage.text("신고", "Report"),
                            systemImage: "exclamationmark.bubble"
                        )
                    }
                    Button(role: .destructive, action: onBlock) {
                        Label(
                            appLanguage.text("차단", "Block"),
                            systemImage: "hand.raised"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(RBColor.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }

            Text(post.title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)

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
                    Task {
                        await viewModel.toggleJoin(postId: post.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: post.isJoined ? "checkmark.circle.fill" : "hand.raised.fill")
                            .font(.system(size: 12))
                        Text(post.isJoined
                             ? appLanguage.text("참여 취소", "Leave")
                             : appLanguage.text("참여하기", "Join"))
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
                    Text(appLanguage.text("모집 마감", "Closed"))
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

    private func socialStatCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(RBFont.caption(10))
                .foregroundStyle(RBColor.textTertiary)
                .tracking(1)
            Text(value)
                .font(RBFont.metric(22))
                .foregroundStyle(RBColor.textPrimary)
            Text(subtitle)
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RBColor.cardBg.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            if !viewModel.friends.isEmpty || !viewModel.suggestedFriends.isEmpty {
                feedStoryStrip
            }

            feedScopeSelector

            ForEach(viewModel.feedPosts) { post in
                FeedCardView(post: post, viewModel: viewModel)
            }

            if viewModel.feedScope == .friends && viewModel.feedPosts.isEmpty && !viewModel.friends.isEmpty {
                emptyState(
                    icon: "person.3.sequence.fill",
                    title: appLanguage.text("친구 피드가 아직 없어요", "No friend posts yet")
                )
            } else if viewModel.feedPosts.isEmpty && !viewModel.isLoading {
                emptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: appLanguage.text("아직 게시글이 없어요", "No posts yet")
                )
            }
        }
    }

    private var feedStoryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appLanguage.text("오늘의 러너", "Today's Runners"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.friends.isEmpty ? viewModel.suggestedFriends : viewModel.friends) { friend in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [RBColor.accent, communityLevelColor(friend.level)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                    .frame(width: 68, height: 68)

                                Circle()
                                    .fill(communityLevelColor(friend.level).opacity(0.16))
                                    .frame(width: 58, height: 58)

                                Text(String(friend.name.prefix(1)))
                                    .font(RBFont.hero(20))
                                    .foregroundStyle(communityLevelColor(friend.level))
                            }

                            Text(friend.name)
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textPrimary)
                                .lineLimit(1)

                            Text(viewModel.friends.contains(where: { $0.id == friend.id })
                                 ? appLanguage.text("친구", "Friend")
                                 : appLanguage.text("추천", "Suggested"))
                                .font(RBFont.caption(9))
                                .foregroundStyle(RBColor.textTertiary)
                        }
                        .frame(width: 78)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var suggestedFriendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appLanguage.text("추천 친구", "Suggested Friends"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.suggestedFriends) { friend in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(communityLevelColor(friend.level).opacity(0.2))
                                        .frame(width: 42, height: 42)
                                    Text(String(friend.name.prefix(1)))
                                        .font(RBFont.label(16))
                                        .foregroundStyle(communityLevelColor(friend.level))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name)
                                        .font(RBFont.label(13))
                                        .foregroundStyle(RBColor.textPrimary)
                                        .lineLimit(1)
                                    Text(friend.level.rawValue)
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(communityLevelColor(friend.level))
                                }
                            }

                            Text(friend.recordSummary)
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textSecondary)

                            Button {
                                Task {
                                    await viewModel.addFriend(friendId: friend.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 11))
                                    Text(appLanguage.text("친구 추가", "Add Friend"))
                                        .font(RBFont.label(12))
                                }
                                .foregroundStyle(RBColor.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(RBColor.accentGradient)
                                .clipShape(Capsule())
                            }
                        }
                        .frame(width: 200, alignment: .leading)
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    private var friendsRecordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appLanguage.text("친구 기록", "Friend Records"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                Text(appLanguage.text("\(viewModel.friends.count)명", "\(viewModel.friends.count) runners"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.friends) { friend in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(communityLevelColor(friend.level).opacity(0.2))
                                        .frame(width: 34, height: 34)
                                    Text(String(friend.name.prefix(1)))
                                        .font(RBFont.label(13))
                                        .foregroundStyle(communityLevelColor(friend.level))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name)
                                        .font(RBFont.label(12))
                                        .foregroundStyle(RBColor.textPrimary)
                                    Text(friend.level.rawValue)
                                        .font(RBFont.caption(9))
                                        .foregroundStyle(communityLevelColor(friend.level))
                                }
                            }

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appLanguage.text("누적 거리", "Distance"))
                                        .font(RBFont.caption(9))
                                        .foregroundStyle(RBColor.textTertiary)
                                    Text(String(format: "%.1fkm", friend.totalDistanceKm))
                                        .font(RBFont.metric(13))
                                        .foregroundStyle(RBColor.textPrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appLanguage.text("러닝 횟수", "Runs"))
                                        .font(RBFont.caption(9))
                                        .foregroundStyle(RBColor.textTertiary)
                                    Text(appLanguage.text("\(friend.totalRuns)회", "\(friend.totalRuns)x"))
                                        .font(RBFont.metric(13))
                                        .foregroundStyle(RBColor.textPrimary)
                                }
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                        .padding(14)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    private var feedScopeSelector: some View {
        HStack(spacing: 8) {
            ForEach(CommunityFeedScope.allCases, id: \.self) { scope in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.feedScope = scope
                    }
                } label: {
                    Text(scope == .all ? appLanguage.text("전체 피드", "All Feed") : appLanguage.text("친구 피드", "Friends"))
                        .font(RBFont.label(12))
                        .foregroundStyle(viewModel.feedScope == scope ? .white : RBColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            Capsule()
                                .fill(viewModel.feedScope == scope ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                        }
                        .overlay(
                            Capsule()
                                .stroke(viewModel.feedScope == scope ? Color.white.opacity(0.08) : RBColor.divider.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(RBColor.textTertiary)
            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Feed Card View

struct FeedCardView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    let post: RunnerPost
    @ObservedObject var viewModel: CommunityViewModel
    @State private var showComments = false
    @State private var newComment = ""
    @State private var showReportDialog = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            mediaBlock

            VStack(alignment: .leading, spacing: 12) {
                actionRow

                if let dist = post.distanceKm, let pace = post.paceFormatted {
                    HStack(spacing: 10) {
                        statPill(icon: "figure.run", value: String(format: "%.2f km", dist))
                        statPill(icon: "speedometer", value: pace)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.authorName)
                        .font(RBFont.label(13))
                        .foregroundStyle(RBColor.textPrimary)

                    Text(post.content)
                        .font(RBFont.label(14))
                        .foregroundStyle(RBColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !post.comments.isEmpty && !showComments {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showComments = true
                        }
                    } label: {
                        Text(appLanguage.text("댓글 \(post.comments.count)개 모두 보기", "View all \(post.comments.count) comments"))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                if showComments {
                    commentsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .confirmationDialog(
            appLanguage.text("신고 사유를 선택하세요", "Select a reason"),
            isPresented: $showReportDialog,
            titleVisibility: .visible
        ) {
            Button(appLanguage.text("스팸", "Spam")) {
                Task { await viewModel.reportPost(targetId: post.id, targetType: "feedPost", reason: "스팸") }
            }
            Button(appLanguage.text("욕설 / 혐오 발언", "Hate speech")) {
                Task { await viewModel.reportPost(targetId: post.id, targetType: "feedPost", reason: "욕설/혐오 발언") }
            }
            Button(appLanguage.text("부적절한 콘텐츠", "Inappropriate content")) {
                Task { await viewModel.reportPost(targetId: post.id, targetType: "feedPost", reason: "부적절한 콘텐츠") }
            }
            Button(appLanguage.text("허위 정보", "False information")) {
                Task { await viewModel.reportPost(targetId: post.id, targetType: "feedPost", reason: "허위 정보") }
            }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(communityLevelColor(post.authorLevel).opacity(0.2))
                    .frame(width: 38, height: 38)
                Text(String(post.authorName.prefix(1)))
                    .font(RBFont.label(14))
                    .foregroundStyle(communityLevelColor(post.authorLevel))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(post.authorName)
                        .font(RBFont.label(13))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(post.authorLevel.rawValue)
                        .font(RBFont.caption(9))
                        .foregroundStyle(communityLevelColor(post.authorLevel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(communityLevelColor(post.authorLevel).opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(post.timeAgo)
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }

            Spacer()

            // MARK: 신고 / 차단 메뉴
            Menu {
                Button(role: .destructive) {
                    showReportDialog = true
                } label: {
                    Label(
                        appLanguage.text("신고", "Report"),
                        systemImage: "exclamationmark.bubble"
                    )
                }
                Button(role: .destructive) {
                    Task { await viewModel.blockUser(userId: post.authorId) }
                } label: {
                    Label(
                        appLanguage.text("차단", "Block"),
                        systemImage: "hand.raised"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var mediaBlock: some View {
        if let photoURL = post.photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                case .failure:
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(RBColor.cardBgLight)
                        .frame(height: 220)
                        .overlay(
                            Text(appLanguage.text("사진을 불러오지 못했어요", "Couldn't load the photo"))
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)
                        )
                default:
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(RBColor.cardBgLight)
                        .frame(height: 220)
                        .overlay(ProgressView().tint(RBColor.accent))
                }
            }
        } else {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [RBColor.accent.opacity(0.22), RBColor.cardBgLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(appLanguage.text("RUN SNAP", "RUN SNAP"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                        .tracking(1.2)
                    Text(post.content)
                        .font(RBFont.hero(22))
                        .foregroundStyle(RBColor.textPrimary)
                        .lineLimit(4)
                }
                .padding(18)
            }
            .frame(height: 220)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 18) {
            Button {
                Task {
                    await viewModel.toggleLike(postId: post.id)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15))
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
                HStack(spacing: 5) {
                    Image(systemName: showComments ? "bubble.right.fill" : "bubble.right")
                        .font(.system(size: 15))
                    Text("\(post.comments.count)")
                        .font(RBFont.caption(12))
                }
                .foregroundStyle(showComments ? RBColor.accent : RBColor.textSecondary)
            }

            Spacer()
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Color.white.opacity(0.08))

            ForEach(post.comments) { comment in
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(communityLevelColor(comment.authorLevel).opacity(0.2))
                            .frame(width: 24, height: 24)
                        Text(String(comment.authorName.prefix(1)))
                            .font(RBFont.caption(10))
                            .foregroundStyle(communityLevelColor(comment.authorLevel))
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
                TextField(appLanguage.text("댓글 입력...", "Write a comment..."), text: $newComment)
                    .font(RBFont.label(13))
                    .foregroundStyle(RBColor.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RBColor.cardBgLight)
                    .clipShape(Capsule())

                Button {
                    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task {
                        await viewModel.addComment(postId: post.id, content: trimmed)
                        newComment = ""
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? RBColor.textTertiary : RBColor.accent)
                        .frame(width: 36, height: 36)
                        .background(RBColor.cardBgLight)
                        .clipShape(Circle())
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(RBColor.accent)
            Text(value)
                .font(RBFont.metric(13))
                .foregroundStyle(RBColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RBColor.accent.opacity(0.08))
        .clipShape(Capsule())
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        inputField(title: "제목", placeholder: "러닝 메이트 모집 제목", text: $title)

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

                        HStack(spacing: 12) {
                            inputField(title: "목표 페이스", placeholder: "5'30\"", text: $targetPace)
                            inputField(title: "목표 거리", placeholder: "5km", text: $targetDistance)
                        }

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
                            Task {
                                let success = await viewModel.createMatePost(
                                    title: title,
                                    location: location,
                                    coordinate: selectedCoordinate,
                                    date: date,
                                    targetPace: targetPace,
                                    targetDistance: targetDistance,
                                    maxMembers: maxMembers,
                                    description: description
                                )
                                if success {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!isValid || viewModel.isSubmitting)
                        .opacity((isValid && !viewModel.isSubmitting) ? 1.0 : 0.5)
                        .padding(.top, 8)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.danger)
                                .multilineTextAlignment(.center)
                        }
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
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d (E) HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
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
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
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
                            Task {
                                let success = await viewModel.createFeedPost(
                                    content: content,
                                    photoData: selectedPhotoData
                                )
                                if success {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!isValid || viewModel.isSubmitting)
                        .opacity((isValid && !viewModel.isSubmitting) ? 1.0 : 0.5)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.danger)
                                .multilineTextAlignment(.center)
                        }
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

private func communityLevelColor(_ level: RunnerLevel) -> Color {
    switch level {
    case .starter: return .gray
    case .bronze: return Color(red: 0.72, green: 0.45, blue: 0.2)
    case .silver: return Color(white: 0.75)
    case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
    case .laser: return RBColor.laserRed
    case .beam: return RBColor.accent
    }
}

#Preview {
    CommunityView()
}
