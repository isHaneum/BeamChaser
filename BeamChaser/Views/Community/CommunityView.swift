import SwiftUI
import MapKit
import PhotosUI
import UIKit
import AuthenticationServices
import CryptoKit

// MARK: - Community Data Models

struct RunnerPost: Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorLevel: RunnerLevel
    let headline: String?
    let content: String
    let runStartedAt: Date?
    let distanceKm: Double?
    let durationFormatted: String?
    let paceFormatted: String?
    let averageHeartRateBpm: Int?
    let averageSpeedKmh: Double?
    let cadenceSpm: Int?
    let elevationGainMeters: Double?
    let caloriesKcal: Double?
    let targetPaceFormatted: String?
    let goalDeltaSeconds: Int?
    let selectedMetricKeys: [RunShareMetricKey]
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

    var isRunResult: Bool {
        type == .runResult && distanceKm != nil
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
    let username: String
    let searchId: String
    let name: String
    let photoURL: String?
    let level: RunnerLevel
    let totalDistanceKm: Double
    let totalRuns: Int

    var handle: String {
        "@\(username)"
    }

    var recordSummary: String {
        AppLanguage.current.text(
            "\(totalRuns)회 · \(String(format: "%.1f", totalDistanceKm))km",
            "\(totalRuns) runs · \(String(format: "%.1f", totalDistanceKm))km"
        )
    }
}

struct CommunityFriendRequest: Identifiable {
    let id: String
    let friend: CommunityFriend
    let source: String
    let createdAt: Date
    let isIncoming: Bool
}

struct ContactMatchedFriend: Identifiable {
    let id: String
    let friend: CommunityFriend
    let contactName: String
}

enum CommunityFeedScope: String, CaseIterable {
    case all = "전체 피드"
    case friends = "친구 피드"
}

enum CommunityFormatter {
    static func relativeString(from date: Date, appLanguage: AppLanguage = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLanguage.isEnglish ? Locale(identifier: "en") : Locale(identifier: "ko_KR")
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
    @Published var incomingFriendRequests: [CommunityFriendRequest] = []
    @Published var outgoingFriendRequests: [CommunityFriendRequest] = []
    @Published var contactMatches: [ContactMatchedFriend] = []
    @Published var searchedFriends: [CommunityFriend] = []
    @Published var feedScope: CommunityFeedScope = .all {
        didSet { applyFeedFilter() }
    }
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var isSearchingUsers = false
    @Published var errorMessage: String?
    @Published var blockedUserIds: Set<String> = []
    @Published var hiddenFeedUserIds: Set<String> = []

    private var backendService: BackendService?
    private var allFeedPosts: [RunnerPost] = []
    private var currentUserId: String?
    private var friendIds: Set<String> = []
    private var pendingRequestUserIds: Set<String> = []
    private var userDirectory: [String: FirestorePublicUser] = [:]
    private var rankedUsers: [FirestorePublicUser] = []
    private var contactEmailDirectory: [String: String] = [:]
    private var lastFriendSearchQuery = ""

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
            return AppLanguage.current.text("커뮤니티 권한을 확인해주세요.", "Check Community permissions.")
        }

        return fallback
    }

    private func friendActionErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let localized = nsError.localizedDescription.lowercased()

        if (nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7)
            || localized.contains("missing or insufficient permissions")
            || localized.contains("insufficient permissions") {
            return AppLanguage.current.text(
                "친구 요청을 처리하지 못했어요. 잠시 후 다시 시도해주세요.",
                "Couldn't process the friend request. Please try again shortly."
            )
        }

        return AppLanguage.current.text(
            "친구 요청을 처리하지 못했어요. 잠시 후 다시 시도해주세요.",
            "Couldn't process the friend request. Please try again shortly."
        )
    }

    func updateContactDirectory(_ directory: [String: String]) {
        contactEmailDirectory = directory
        refreshSocialDiscovery()
    }

    func reload() async {
        guard let backendService else { return }
        guard backendService.isSignedIn else {
            matePosts = []
            feedPosts = []
            allFeedPosts = []
            suggestedFriends = []
            friends = []
            incomingFriendRequests = []
            outgoingFriendRequests = []
            contactMatches = []
            searchedFriends = []
            friendIds = []
            pendingRequestUserIds = []
            userDirectory = [:]
            rankedUsers = []
            lastFriendSearchQuery = ""
            hiddenFeedUserIds = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 네 작업을 동시에 시작하되, 유저 목록·친구 목록은 soft-fail 처리
        // (Firestore 보안 규칙에서 컬렉션 전체 읽기가 막혀도 포스트는 보여줌)
        async let usersTask   = backendService.fetchUsers(limit: 100)
        async let blocksTask = backendService.fetchBlocks()
        async let requestsTask = backendService.fetchFriendRequests()
        async let friendshipsTask = backendService.fetchFriendships()
        async let followsTask = backendService.fetchFollowStates()
        async let mateTask    = backendService.fetchMatePosts()
        async let feedTask    = backendService.fetchFeedPosts()

        let users    = (try? await usersTask) ?? []
        let blocks   = (try? await blocksTask) ?? []
        let requests = (try? await requestsTask) ?? []
        let friendships = (try? await friendshipsTask) ?? []
        let follows = (try? await followsTask) ?? []

        do {
            let fetchedMatePosts = try await mateTask
            let fetchedFeedPosts = try await feedTask

            currentUserId = backendService.userId
            let currentUserId = backendService.userId
            userDirectory = Dictionary(uniqueKeysWithValues: users.map { ($0.uid, $0) })
            rankedUsers = users.sorted { lhs, rhs in
                if lhs.resolvedTotalDistanceKm == rhs.resolvedTotalDistanceKm {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.resolvedTotalDistanceKm > rhs.resolvedTotalDistanceKm
            }

            blockedUserIds = Set(blocks.compactMap { block in
                guard let currentUserId else { return nil }
                if block.blockerId == currentUserId { return block.blockedId }
                if block.blockedId == currentUserId { return block.blockerId }
                return nil
            })
            hiddenFeedUserIds = Set(follows.filter { !$0.isActive }.map(\.followingId))

            rebuildRelationships(requests: requests, friendships: friendships)
            refreshSocialDiscovery()

            friends = rankedUsers
                .filter { friendIds.contains($0.uid) && !blockedUserIds.contains($0.uid) }
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
            errorMessage = presentableMessage(
                for: error,
                fallback: AppLanguage.current.text("커뮤니티를 불러오지 못했어요.", "Couldn't load Community.")
            )
        }
    }

    func addFriend(friendId: String, source: String = "manual") async {
        guard let backendService else { return }
        guard backendService.isSignedIn else {
            errorMessage = AppLanguage.current.text(
                "친구 요청은 로그인 후 사용할 수 있어요.",
                "Friend requests are available after sign-in."
            )
            return
        }

        guard !friendIds.contains(friendId) else {
            errorMessage = nil
            return
        }

        guard !pendingRequestUserIds.contains(friendId) else {
            errorMessage = AppLanguage.current.text(
                "이미 진행 중인 친구 요청이 있어요.",
                "There is already a friend request in progress."
            )
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.sendFriendRequest(toUserId: friendId, source: source)
            pendingRequestUserIds.insert(friendId)
            searchedFriends.removeAll { $0.id == friendId }
            suggestedFriends.removeAll { $0.id == friendId }
            contactMatches.removeAll { $0.friend.id == friendId }
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = friendActionErrorMessage(for: error)
        }
    }

    func searchFriends(query: String) async {
        guard let backendService else { return }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastFriendSearchQuery = trimmedQuery
        let normalizedQuery = FirestorePublicUser.normalizedSearchText(
            trimmedQuery.replacingOccurrences(of: "@", with: "")
        )

        guard backendService.isSignedIn else {
            searchedFriends = []
            errorMessage = AppLanguage.current.text(
                "친구 검색은 로그인 후 사용할 수 있어요.",
                "Friend search is available after sign-in."
            )
            return
        }

        guard !trimmedQuery.isEmpty else {
            searchedFriends = []
            return
        }

        var resultsById: [String: CommunityFriend] = [:]
        for user in rankedUsers where matchesSearchQuery(user, normalizedQuery: normalizedQuery) {
            guard user.uid != currentUserId,
                  !friendIds.contains(user.uid),
                  !pendingRequestUserIds.contains(user.uid),
                  !blockedUserIds.contains(user.uid) else {
                continue
            }
            let friend = makeCommunityFriend(from: user)
            resultsById[friend.id] = friend
        }

        isSearchingUsers = true
        defer { isSearchingUsers = false }

        do {
            let users = try await backendService.searchUsers(query: trimmedQuery)
            for user in users {
                guard user.uid != currentUserId,
                      !friendIds.contains(user.uid),
                      !pendingRequestUserIds.contains(user.uid),
                      !blockedUserIds.contains(user.uid) else {
                    continue
                }
                let friend = makeCommunityFriend(from: user)
                resultsById[friend.id] = friend
            }
            searchedFriends = resultsById.values.sorted { lhs, rhs in
                if lhs.totalDistanceKm == rhs.totalDistanceKm {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.totalDistanceKm > rhs.totalDistanceKm
            }
            errorMessage = nil
        } catch {
            searchedFriends = resultsById.values.sorted { lhs, rhs in
                if lhs.totalDistanceKm == rhs.totalDistanceKm {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.totalDistanceKm > rhs.totalDistanceKm
            }
            errorMessage = searchedFriends.isEmpty
                ? presentableMessage(
                    for: error,
                    fallback: AppLanguage.current.text("친구 검색에 실패했어요.", "Couldn't search for friends.")
                )
                : nil
        }
    }

    func clearFriendSearch() {
        lastFriendSearchQuery = ""
        searchedFriends = []
    }

    func respondToFriendRequest(requestId: String, accept: Bool) async {
        guard let backendService else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await backendService.respondToFriendRequest(requestId: requestId, accept: accept)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = friendActionErrorMessage(for: error)
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
            errorMessage = AppLanguage.current.text("좋아요 반영 실패: \(error.localizedDescription)", "Couldn't update the like: \(error.localizedDescription)")
        }
    }

    func addComment(postId: String, content: String) async {
        guard
            let backendService,
            let userId = backendService.userId
        else {
            errorMessage = AppLanguage.current.text("댓글 작성은 로그인 후 사용할 수 있어요.", "You can write comments after sign-in.")
            return
        }

        let author = userDirectory[userId] ?? backendService.currentUser?.publicProfile
        let comment = FirestoreComment(
            id: UUID().uuidString,
            authorId: userId,
            authorName: author?.displayName ?? AppLanguage.current.text("러너", "Runner"),
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
            errorMessage = AppLanguage.current.text("댓글 저장 실패: \(error.localizedDescription)", "Couldn't save the comment: \(error.localizedDescription)")
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
            errorMessage = AppLanguage.current.text("참여 상태 반영 실패: \(error.localizedDescription)", "Couldn't update participation: \(error.localizedDescription)")
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
            errorMessage = AppLanguage.current.text("신고를 전송하지 못했어요.", "Couldn't send the report.")
        }
    }

    func blockUser(userId: String) async {
        guard let backendService else { return }
        do {
            try await backendService.blockUser(uid: userId)
            blockedUserIds.insert(userId)
            hiddenFeedUserIds.insert(userId)
            allFeedPosts = allFeedPosts.filter { $0.authorId != userId }
            applyFeedFilter()
            matePosts = matePosts.filter { $0.authorId != userId }
            friends.removeAll { $0.id == userId }
            suggestedFriends.removeAll { $0.id == userId }
            contactMatches.removeAll { $0.friend.id == userId }
            incomingFriendRequests.removeAll { $0.friend.id == userId }
            outgoingFriendRequests.removeAll { $0.friend.id == userId }
        } catch {
            errorMessage = AppLanguage.current.text("차단할 수 없었어요.", "Couldn't block this user.")
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
            errorMessage = AppLanguage.current.text("메이트 모집은 로그인 후 사용할 수 있어요.", "You can create mate posts after sign-in.")
            return false
        }

        let author = userDirectory[userId] ?? backendService.currentUser?.publicProfile
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = AppLanguage.current.isEnglish ? "MMM d (E)" : "M/d (E)"
        dateFormatter.locale = AppLanguage.current.isEnglish ? Locale(identifier: "en") : Locale(identifier: "ko_KR")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = AppLanguage.current.isEnglish ? Locale(identifier: "en") : Locale(identifier: "ko_KR")

        let post = FirestoreMatePost(
            id: UUID().uuidString,
            authorId: userId,
            authorName: author?.displayName ?? AppLanguage.current.text("러너", "Runner"),
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
            errorMessage = AppLanguage.current.text("메이트 모집 글 저장 실패: \(error.localizedDescription)", "Couldn't save the mate post: \(error.localizedDescription)")
            return false
        }
    }

    func createFeedPost(content: String, photoData: Data?) async -> Bool {
        guard
            let backendService,
            let userId = backendService.userId
        else {
            errorMessage = AppLanguage.current.text("피드 작성은 로그인 후 사용할 수 있어요.", "You can write feed posts after sign-in.")
            return false
        }

        let author = userDirectory[userId] ?? backendService.currentUser?.publicProfile

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
                authorName: author?.displayName ?? AppLanguage.current.text("러너", "Runner"),
                authorLevel: author?.level ?? RunnerLevel.starter.rawValue,
                headline: nil,
                content: content,
                runId: nil,
                runStartedAt: nil,
                distanceKm: nil,
                durationFormatted: nil,
                paceFormatted: nil,
                averageHeartRateBpm: nil,
                averageSpeedKmh: nil,
                cadenceSpm: nil,
                elevationGainMeters: nil,
                caloriesKcal: nil,
                targetPaceFormatted: nil,
                goalDeltaSeconds: nil,
                selectedMetricKeys: nil,
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
            errorMessage = AppLanguage.current.text("피드 업로드 실패: \(error.localizedDescription)", "Couldn't upload the feed post: \(error.localizedDescription)")
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
            feedPosts = allFeedPosts.filter { !hiddenFeedUserIds.contains($0.authorId) }
        case .friends:
            feedPosts = allFeedPosts.filter {
                friendIds.contains($0.authorId) && !hiddenFeedUserIds.contains($0.authorId)
            }
        }
    }

    private func rebuildRelationships(requests: [FirestoreFriendRequest], friendships: [FirestoreFriendship]) {
        var acceptedFriendIds = Set<String>()
        var pendingIds = Set<String>()
        var nextIncoming: [CommunityFriendRequest] = []
        var nextOutgoing: [CommunityFriendRequest] = []

        guard let currentUserId else { return }

        for friendship in friendships where friendship.isActive {
            if let counterpartId = friendship.users.first(where: { $0 != currentUserId }) {
                acceptedFriendIds.insert(counterpartId)
            }
        }

        for request in requests {
            let counterpartId: String
            let isIncoming: Bool

            if request.resolvedReceiverId == currentUserId {
                counterpartId = request.resolvedSenderId
                isIncoming = true
            } else if request.resolvedSenderId == currentUserId {
                counterpartId = request.resolvedReceiverId
                isIncoming = false
            } else {
                continue
            }

            switch request.status {
            case "accepted":
                let friendshipId = [currentUserId, counterpartId].sorted().joined(separator: "_")
                if !friendships.contains(where: { ($0.friendshipId.isEmpty ? $0.id : $0.friendshipId) == friendshipId }) {
                    acceptedFriendIds.insert(counterpartId)
                }
            case "pending":
                pendingIds.insert(counterpartId)
                guard let counterpart = userDirectory[counterpartId] else { continue }
                let item = CommunityFriendRequest(
                    id: request.documentId,
                    friend: makeCommunityFriend(from: counterpart),
                    source: request.source,
                    createdAt: request.createdAt,
                    isIncoming: isIncoming
                )
                if isIncoming {
                    nextIncoming.append(item)
                } else {
                    nextOutgoing.append(item)
                }
            default:
                continue
            }
        }

        friendIds = acceptedFriendIds
        pendingRequestUserIds = pendingIds
        incomingFriendRequests = nextIncoming
            .filter { !blockedUserIds.contains($0.friend.id) }
            .sorted { $0.createdAt > $1.createdAt }
        outgoingFriendRequests = nextOutgoing
            .filter { !blockedUserIds.contains($0.friend.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func refreshSocialDiscovery() {
        guard let currentUserId else {
            suggestedFriends = []
            contactMatches = []
            return
        }

        let hashedContacts = contactEmailDirectory.reduce(into: [String: String]()) { result, item in
            if let emailHash = contactEmailHash(item.key) {
                result[emailHash] = item.value
            }
        }

        let matchedUsers = rankedUsers.filter { user in
            return user.uid != currentUserId
                && !friendIds.contains(user.uid)
                && !pendingRequestUserIds.contains(user.uid)
                && !blockedUserIds.contains(user.uid)
                && (user.contactEmailHash.flatMap { hashedContacts[$0] } != nil)
        }

        let contactMatchedIds = Set(matchedUsers.map(\.uid))
        contactMatches = matchedUsers.prefix(20).map { user in
            return ContactMatchedFriend(
                id: user.uid,
                friend: makeCommunityFriend(from: user),
                contactName: user.contactEmailHash.flatMap { hashedContacts[$0] } ?? user.displayName
            )
        }

        suggestedFriends = rankedUsers
            .filter { user in
                user.uid != currentUserId
                    && !friendIds.contains(user.uid)
                    && !pendingRequestUserIds.contains(user.uid)
                    && !blockedUserIds.contains(user.uid)
                    && !contactMatchedIds.contains(user.uid)
            }
            .prefix(12)
            .map { makeCommunityFriend(from: $0) }
    }

    private func contactEmailHash(_ email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeCommunityFriend(from user: FirestorePublicUser) -> CommunityFriend {
        CommunityFriend(
            id: user.uid,
            username: user.resolvedUsername,
            searchId: user.resolvedUsername,
            name: user.displayName,
            photoURL: user.photoURL,
            level: RunnerLevel(rawValue: user.level) ?? .starter,
            totalDistanceKm: user.resolvedTotalDistanceKm,
            totalRuns: user.resolvedTotalRuns
        )
    }

    private func matchesSearchQuery(_ user: FirestorePublicUser, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return false }

        let normalizedName = user.displayNameLower ?? FirestorePublicUser.normalizedSearchText(user.displayName)
        let normalizedSearchId = user.usernameLower ?? user.searchId ?? FirestorePublicUser.searchId(from: user.uid)
        let normalizedUid = FirestorePublicUser.normalizedSearchText(user.uid)

        return normalizedName.hasPrefix(normalizedQuery)
            || normalizedSearchId.hasPrefix(normalizedQuery)
            || normalizedUid.hasPrefix(normalizedQuery)
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
            headline: post.headline,
            content: post.content,
            runStartedAt: post.runStartedAt,
            distanceKm: post.distanceKm,
            durationFormatted: post.durationFormatted,
            paceFormatted: post.paceFormatted,
            averageHeartRateBpm: post.averageHeartRateBpm,
            averageSpeedKmh: post.averageSpeedKmh,
            cadenceSpm: post.cadenceSpm,
            elevationGainMeters: post.elevationGainMeters,
            caloriesKcal: post.caloriesKcal,
            targetPaceFormatted: post.targetPaceFormatted,
            goalDeltaSeconds: post.goalDeltaSeconds,
            selectedMetricKeys: (post.selectedMetricKeys ?? []).compactMap(RunShareMetricKey.init(rawValue:)),
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
    @EnvironmentObject private var authService: AuthService
    @Environment(\.openURL) private var openURL
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @StateObject private var viewModel = CommunityViewModel()
    @StateObject private var friendshipViewModel = FriendshipViewModel()
    @StateObject private var contactsService = ContactsService()
    @State private var selectedTab: CommunityTab = .mate
    @State private var selectedMateMode: MateMode = .friends
    @State private var showCreateMate = false
    @State private var showCreateFeed = false
    @State private var friendSearchText = ""
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
        case requests = "요청"
        case discover = "찾기"

        var icon: String {
            switch self {
            case .friends: return "person.2.wave.2.fill"
            case .requests: return "bell.badge.fill"
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
                                if selectedTab == .feed, let error = viewModel.errorMessage {
                                    errorBanner(error)
                                }

                                if selectedTab == .feed && viewModel.isLoading && viewModel.feedPosts.isEmpty {
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
                            await friendshipViewModel.refresh()
                        }
                        .contentMargins(.bottom, RBLayout.scrollBottomInset, for: .scrollContent)
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
                friendshipViewModel.configure(backendService: backendService)
                contactsService.refreshAuthorizationStatus()
                if contactsService.isAuthorized {
                    await contactsService.loadContacts()
                }
                await viewModel.reload()
                await friendshipViewModel.refresh()
                viewModel.updateContactDirectory(contactsService.contactEmailDirectory)
            }
            .task(id: friendshipViewModel.relationshipRevision) {
                guard friendshipViewModel.relationshipRevision > 0 else { return }
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

                    if backendService.isSignedIn, selectedTab == .mate {
                        Text(appLanguage.text("친구와 요청을 관리합니다", "Manage friends and requests"))
                            .font(RBFont.caption(11))
                            .foregroundStyle(RBColor.textSecondary)
                    }
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
        Group {
            if selectedTab == .mate, let inviteText = friendshipViewModel.inviteShareText {
                ShareLink(item: inviteText) {
                    addButtonChrome
                }
            } else {
                Button {
                    showCreateFeed = true
                } label: {
                    addButtonChrome
                }
            }
        }
        .accessibilityLabel(selectedTab == .mate ? appLanguage.text("내 아이디 공유", "Share my ID") : appLanguage.text("피드 추가", "Add feed post"))
    }

    private var addButtonChrome: some View {
        ZStack {
            Circle()
                .fill(
                    selectedTab == .mate
                        ? LinearGradient(
                            colors: [AppColorTheme.ember.primary, AppColorTheme.ember.gradientTail],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : RBColor.accentGradient
                )
                .frame(width: 52, height: 52)
            Image(systemName: selectedTab == .mate ? "square.and.arrow.up" : "plus")
                .font(.system(size: 18, weight: .heavy))
        }
        .foregroundStyle(.black)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: RBColor.accent.opacity(0.35), radius: 14, y: 8)
    }

    private var signInRequiredState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(RBColor.accent.opacity(0.14))
                    .frame(width: 74, height: 74)
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(RBColor.accent)
            }

            VStack(spacing: 6) {
                Text(appLanguage.text("커뮤니티 로그인이 필요해요", "Sign in to use Community"))
                    .font(RBFont.label(20))
                    .foregroundStyle(RBColor.textPrimary)
                Text(appLanguage.text("친구 추가, 메이트 모집, 피드 작성을 사용할 수 있습니다.", "Add friends, create mate posts, and write feed posts."))
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                LocalizedAppleSignInButton(
                    title: appLanguage.text("Apple로 로그인", "Sign in with Apple"),
                    isAuthenticating: authService.selectedProvider == .apple,
                    isAvailable: authService.isAppleSignInAvailable
                ) { request in
                    authService.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    Task {
                        await authService.handleSignInResult(result, backendService: backendService)
                        await viewModel.reload()
                    }
                }

                if let availabilityMessage = authService.appleSignInAvailabilityMessage {
                    Text(availabilityMessage)
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if authService.isGoogleSignInAvailable {
                    GoogleBrandedSignInButton(
                        title: appLanguage.text("Google로 로그인", "Sign in with Google"),
                        isAuthenticating: authService.selectedProvider == .google
                    ) {
                        Task {
                            await authService.signInWithGoogle(backendService: backendService)
                            await viewModel.reload()
                        }
                    }
                }

                if authService.isAuthenticating {
                    ProgressView()
                        .tint(RBColor.accent)
                }

                if let error = authService.signInError {
                    errorBanner(error)
                }
            }
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
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
                    .foregroundStyle(selectedTab == tab ? .black : RBColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedTab == tab ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedTab == tab ? Color.black.opacity(0.18) : RBColor.divider.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: selectedTab == tab ? RBColor.accent.opacity(0.18) : .clear, radius: 12, y: 6)
                }
            }
        }
    }

    private var mateModeSelector: some View {
        FriendTabs(selection: $selectedMateMode)
    }

    // MARK: - Mate Content

    private var mateContent: some View {
        CommunityFriendView(viewModel: friendshipViewModel, selection: $selectedMateMode)
    }

    private var mateFriendsContent: some View {
        Group {
            if !viewModel.friends.isEmpty || !viewModel.incomingFriendRequests.isEmpty || !viewModel.outgoingFriendRequests.isEmpty {
                mateFriendsHero
            }

            if !viewModel.incomingFriendRequests.isEmpty {
                incomingFriendRequestsSection
            }

            if !viewModel.outgoingFriendRequests.isEmpty {
                outgoingFriendRequestsSection
            }

            friendSearchSection

            if !viewModel.friends.isEmpty {
                friendsRecordSection
            }

            if !viewModel.suggestedFriends.isEmpty {
                suggestedFriendsSection
            }

            if viewModel.friends.isEmpty
                && viewModel.suggestedFriends.isEmpty
                && viewModel.incomingFriendRequests.isEmpty
                && viewModel.outgoingFriendRequests.isEmpty
                && !viewModel.isLoading {
                emptyState(
                    icon: "person.2.slash",
                    title: appLanguage.text("아직 연결된 러닝 친구가 없어요", "No running friends yet")
                )
            }
        }
    }

    private var mateDiscoverContent: some View {
        Group {
            contactDiscoverySection

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
                    subtitle: appLanguage.text("연결됨", "Connected")
                )
                socialStatCard(
                    title: appLanguage.text("받은 요청", "Requests"),
                    value: "\(viewModel.incomingFriendRequests.count)",
                    subtitle: appLanguage.text("응답 필요", "Needs reply")
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

    private var incomingFriendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appLanguage.text("받은 친구 요청", "Incoming Requests"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                Text(appLanguage.text("\(viewModel.incomingFriendRequests.count)건", "\(viewModel.incomingFriendRequests.count)"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }

            VStack(spacing: 12) {
                ForEach(viewModel.incomingFriendRequests) { request in
                    friendRequestCard(request)
                }
            }
        }
    }

    private var outgoingFriendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appLanguage.text("보낸 친구 요청", "Sent Requests"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
            }

            VStack(spacing: 12) {
                ForEach(viewModel.outgoingFriendRequests) { request in
                    friendRequestCard(request)
                }
            }
        }
    }

    private func friendRequestCard(_ request: CommunityFriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(communityLevelColor(request.friend.level).opacity(0.18))
                        .frame(width: 48, height: 48)
                    Text(String(request.friend.name.prefix(1)))
                        .font(RBFont.label(16))
                        .foregroundStyle(communityLevelColor(request.friend.level))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(request.friend.name)
                            .font(RBFont.label(15))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(request.friend.level.localizedName(appLanguage))
                            .font(RBFont.caption(10))
                            .foregroundStyle(communityLevelColor(request.friend.level))
                    }
                    Text(CommunityFormatter.relativeString(from: request.createdAt, appLanguage: appLanguage))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }

                Spacer()

                requestSourceBadge(request.source)
            }

            HStack(spacing: 10) {
                compactFriendStat(title: appLanguage.text("거리", "Distance"), value: String(format: "%.1fkm", request.friend.totalDistanceKm))
                compactFriendStat(title: appLanguage.text("러닝", "Runs"), value: appLanguage.text("\(request.friend.totalRuns)회", "\(request.friend.totalRuns)x"))
            }

            if request.isIncoming {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await viewModel.respondToFriendRequest(requestId: request.id, accept: false)
                        }
                    } label: {
                        Text(appLanguage.text("거절", "Decline"))
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RBColor.cardBgLight)
                            .clipShape(Capsule())
                    }

                    Button {
                        Task {
                            await viewModel.respondToFriendRequest(requestId: request.id, accept: true)
                        }
                    } label: {
                        Text(appLanguage.text("수락", "Accept"))
                            .font(RBFont.label(13))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RBColor.accentGradient)
                            .clipShape(Capsule())
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                    Text(appLanguage.text("응답 대기 중", "Waiting for reply"))
                        .font(RBFont.label(12))
                }
                .foregroundStyle(RBColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RBColor.cardBgLight)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var contactDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appLanguage.text("연락처에서 러너 찾기", "Find Runners in Contacts"))
                    .font(RBFont.label(16))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                if contactsService.isAuthorized {
                    Text(appLanguage.text("\(viewModel.contactMatches.count)명", "\(viewModel.contactMatches.count)"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }
            }

            if contactsService.isAuthorized {
                if contactsService.isLoading {
                    ProgressView()
                        .tint(RBColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(RBColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if viewModel.contactMatches.isEmpty {
                    emptyState(
                        icon: "person.crop.circle.badge.questionmark",
                        title: appLanguage.text("일치하는 연락처가 아직 없어요", "No matching contacts yet"),
                        subtitle: appLanguage.text("현재는 연락처 이메일 기준으로만 친구를 추천합니다.", "For now, contact-based matching uses contact email addresses only.")
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.contactMatches) { match in
                            contactMatchCard(match)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appLanguage.text("연락처를 허용하면 저장된 이메일과 일치하는 러너에게 바로 요청을 보낼 수 있어요.", "Allow contacts to send requests to runners whose emails match your saved contacts."))
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)

                    Button {
                        Task {
                            if contactsService.authorizationStatus == .denied || contactsService.authorizationStatus == .restricted {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            } else {
                                await contactsService.requestAccessIfNeeded()
                                viewModel.updateContactDirectory(contactsService.contactEmailDirectory)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: contactsService.authorizationStatus == .denied ? "gearshape.fill" : "person.crop.circle.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(contactsService.authorizationStatus == .denied
                                 ? appLanguage.text("설정 열기", "Open Settings")
                                 : appLanguage.text("연락처 접근 허용", "Allow Contacts"))
                                .font(RBFont.label(13))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RBColor.accentGradient)
                        .clipShape(Capsule())
                    }
                }
                .padding(16)
                .background(RBColor.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func contactMatchCard(_ match: ContactMatchedFriend) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(communityLevelColor(match.friend.level).opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(String(match.friend.name.prefix(1)))
                        .font(RBFont.label(18))
                        .foregroundStyle(communityLevelColor(match.friend.level))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(match.friend.name)
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(match.friend.level.localizedName(appLanguage))
                        .font(RBFont.caption(10))
                        .foregroundStyle(communityLevelColor(match.friend.level))
                    Text(appLanguage.text("연락처: \(match.contactName)", "Contact: \(match.contactName)"))
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                compactFriendStat(title: appLanguage.text("거리", "Distance"), value: String(format: "%.1fkm", match.friend.totalDistanceKm))
                compactFriendStat(title: appLanguage.text("러닝", "Runs"), value: appLanguage.text("\(match.friend.totalRuns)회", "\(match.friend.totalRuns)x"))
            }

            Button {
                Task {
                    await viewModel.addFriend(friendId: match.friend.id, source: "contacts")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLanguage.text("친구 요청", "Send Request"))
                        .font(RBFont.label(13))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RBColor.accentGradient)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.6 : 1)
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func requestSourceBadge(_ source: String) -> some View {
        Text(source == "contacts"
             ? appLanguage.text("연락처", "Contacts")
             : appLanguage.text("앱 추천", "Suggested"))
            .font(RBFont.caption(9))
            .foregroundStyle(RBColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RBColor.cardBgLight)
            .clipShape(Capsule())
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
                        Text(post.authorLevel.localizedName(appLanguage))
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
                Text(appLanguage.text("\(viewModel.suggestedFriends.count)명", "\(viewModel.suggestedFriends.count)"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }

            VStack(spacing: 12) {
                ForEach(viewModel.suggestedFriends) { friend in
                    suggestedFriendCard(friend)
                }
            }
        }
    }

    private var friendSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage.text("아이디로 친구 찾기", "Find Friends by ID"))
                        .font(RBFont.label(16))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(appLanguage.text("러너 아이디 또는 이름 앞부분으로 검색하세요. 예: @ab12cd34", "Search by runner ID or the beginning of a name. Example: @ab12cd34"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RBColor.textTertiary)

                    TextField(appLanguage.text("아이디 또는 이름", "Runner ID or name"), text: $friendSearchText)
                        .font(RBFont.label(14))
                        .foregroundStyle(RBColor.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task {
                                await viewModel.searchFriends(query: friendSearchText)
                            }
                        }

                    if !friendSearchText.isEmpty {
                        Button {
                            friendSearchText = ""
                            viewModel.clearFriendSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(RBColor.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(RBColor.cardBg)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(RBColor.divider.opacity(0.8), lineWidth: 1)
                )

                Button {
                    Task {
                        await viewModel.searchFriends(query: friendSearchText)
                    }
                } label: {
                    Text(appLanguage.text("검색", "Search"))
                        .font(RBFont.label(13))
                        .foregroundStyle(RBColor.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(RBColor.accentGradient)
                        .clipShape(Capsule())
                }
                .disabled(viewModel.isSearchingUsers || friendSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.isSearchingUsers || friendSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            }

            if viewModel.isSearchingUsers {
                ProgressView()
                    .tint(RBColor.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RBColor.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if !viewModel.searchedFriends.isEmpty {
                VStack(spacing: 12) {
                    ForEach(viewModel.searchedFriends) { friend in
                        searchableFriendCard(friend)
                    }
                }
            } else if !friendSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState(
                    icon: "person.crop.circle.badge.questionmark",
                    title: appLanguage.text("검색 결과가 없어요", "No matching runners"),
                    subtitle: appLanguage.text("아직 공개 프로필에 검색용 아이디가 동기화되지 않은 사용자는 검색되지 않을 수 있어요.", "Users whose public profile hasn't synced search fields yet may not appear here.")
                )
            }
        }
    }

    private func suggestedFriendCard(_ friend: CommunityFriend) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(communityLevelColor(friend.level).opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(String(friend.name.prefix(1)))
                        .font(RBFont.label(18))
                        .foregroundStyle(communityLevelColor(friend.level))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.textPrimary)
                    Text("@\(friend.searchId)")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(friend.level.localizedName(appLanguage))
                        .font(RBFont.caption(10))
                        .foregroundStyle(communityLevelColor(friend.level))
                }

                Spacer()

                Text(friend.recordSummary)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 10) {
                compactFriendStat(title: appLanguage.text("거리", "Distance"), value: String(format: "%.1fkm", friend.totalDistanceKm))
                compactFriendStat(title: appLanguage.text("러닝", "Runs"), value: appLanguage.text("\(friend.totalRuns)회", "\(friend.totalRuns)x"))
            }

            Button {
                Task {
                    await viewModel.addFriend(friendId: friend.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLanguage.text("친구 요청", "Send Request"))
                        .font(RBFont.label(13))
                }
                .foregroundStyle(RBColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RBColor.accentGradient)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.6 : 1)
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func searchableFriendCard(_ friend: CommunityFriend) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(communityLevelColor(friend.level).opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(String(friend.name.prefix(1)))
                        .font(RBFont.label(18))
                        .foregroundStyle(communityLevelColor(friend.level))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .font(RBFont.label(15))
                        .foregroundStyle(RBColor.textPrimary)
                    Text("@\(friend.searchId)")
                        .font(RBFont.caption(10))
                        .foregroundStyle(RBColor.textTertiary)
                    Text(friend.level.localizedName(appLanguage))
                        .font(RBFont.caption(10))
                        .foregroundStyle(communityLevelColor(friend.level))
                }

                Spacer()

                Text(friend.recordSummary)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textSecondary)
            }

            HStack(spacing: 10) {
                compactFriendStat(title: appLanguage.text("거리", "Distance"), value: String(format: "%.1fkm", friend.totalDistanceKm))
                compactFriendStat(title: appLanguage.text("러닝", "Runs"), value: appLanguage.text("\(friend.totalRuns)회", "\(friend.totalRuns)x"))
            }

            Button {
                Task {
                    await viewModel.addFriend(friendId: friend.id, source: "search")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLanguage.text("친구 요청", "Send Request"))
                        .font(RBFont.label(13))
                }
                .foregroundStyle(RBColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RBColor.accentGradient)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.6 : 1)
        }
        .padding(16)
        .background(RBColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                                    Text(friend.level.localizedName(appLanguage))
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
                        .foregroundStyle(viewModel.feedScope == scope ? .black : RBColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            Capsule()
                                .fill(viewModel.feedScope == scope ? AnyShapeStyle(RBColor.accentGradient) : AnyShapeStyle(RBColor.cardBg))
                        }
                        .overlay(
                            Capsule()
                                .stroke(viewModel.feedScope == scope ? Color.black.opacity(0.18) : RBColor.divider.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func compactFriendStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(RBFont.caption(9))
                .foregroundStyle(RBColor.textTertiary)
            Text(value)
                .font(RBFont.metric(13))
                .foregroundStyle(RBColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RBColor.cardBgLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    private struct RunSummaryMetric: Identifiable {
        let key: RunShareMetricKey
        let title: String
        let value: String
        let subtitle: String?
        let accent: Color

        var id: String { key.rawValue }
    }

    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    let post: RunnerPost
    @ObservedObject var viewModel: CommunityViewModel
    @State private var showComments = false
    @State private var newComment = ""
    @State private var showReportDialog = false

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            if post.isRunResult {
                runSummaryBlock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            if shouldShowMediaBlock {
                mediaBlock
            }

            VStack(alignment: .leading, spacing: 12) {
                actionRow

                if post.isRunResult {
                    runNarrativeBlock
                } else {
                    freeBoardContentBlock
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

    private var shouldShowMediaBlock: Bool {
        if post.isRunResult {
            return post.photoURL != nil
        }
        return true
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
                    Text(post.authorLevel.localizedName(appLanguage))
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

    private var runSummaryBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(appLanguage.text("러닝 기록", "Run Result"))
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
                    .tracking(1.2)

                Spacer()

                if let runStartedAt = post.runStartedAt {
                    Text(RunPresentationFormatter.scheduleString(from: runStartedAt, appLanguage: appLanguage))
                        .font(RBFont.caption(11))
                        .foregroundStyle(RBColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(resolvedHeadline)
                .font(RBFont.hero(22))
                .foregroundStyle(RBColor.textPrimary)
                .lineLimit(3)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(distanceValueText)
                    .font(RBFont.hero(42))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text("km")
                    .font(RBFont.label(18))
                    .foregroundStyle(RBColor.textSecondary)

                Spacer(minLength: 8)

                Text(post.timeAgo)
                    .font(RBFont.caption(11))
                    .foregroundStyle(RBColor.textTertiary)
            }

            if !runSummaryMetrics.isEmpty {
                LazyVGrid(columns: summaryColumns, spacing: 10) {
                    ForEach(runSummaryMetrics) { metric in
                        runSummaryMetricCard(metric)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            RBColor.cardBgLight,
                            RBColor.cardBg,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RBColor.divider.opacity(0.75), lineWidth: 1)
        )
    }

    private func runSummaryMetricCard(_ metric: RunSummaryMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.key.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(metric.accent)
                Text(metric.title)
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textTertiary)
            }

            Text(metric.value)
                .font(RBFont.metric(16))
                .foregroundStyle(RBColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle = metric.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RBFont.caption(10))
                    .foregroundStyle(RBColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RBColor.cardBg.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .frame(height: post.isRunResult ? 260 : 300)
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
        } else if !post.isRunResult {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [RBColor.accent.opacity(0.22), RBColor.cardBgLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(appLanguage.text("피드 스냅", "Run Snap"))
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

    private var freeBoardContentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dist = post.distanceKm, let pace = post.paceFormatted {
                HStack(spacing: 10) {
                    statPill(icon: "figure.run", value: String(format: "%.2f km", dist))
                    statPill(icon: "speedometer", value: pace)
                }
            }

            Text(post.content)
                .font(RBFont.label(14))
                .foregroundStyle(RBColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var runNarrativeBlock: some View {
        if !trimmedContent.isEmpty {
            Text(trimmedContent)
                .font(RBFont.label(14))
                .foregroundStyle(RBColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var resolvedHeadline: String {
        let trimmedHeadline = (post.headline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHeadline.isEmpty {
            return trimmedHeadline
        }
        return appLanguage.text("오늘의 러닝 결과", "Run Result")
    }

    private var trimmedContent: String {
        post.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var distanceValueText: String {
        String(format: "%.2f", post.distanceKm ?? 0)
    }

    private var runSummaryMetrics: [RunSummaryMetric] {
        let metricKeys = post.selectedMetricKeys.isEmpty ? [RunShareMetricKey.duration, .pace] : post.selectedMetricKeys

        return metricKeys.compactMap { metric in
            switch metric {
            case .duration:
                guard let duration = post.durationFormatted else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: duration,
                    subtitle: nil,
                    accent: RBColor.accent
                )
            case .pace:
                guard let pace = post.paceFormatted else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: pace,
                    subtitle: nil,
                    accent: RBColor.accent
                )
            case .averageHeartRate:
                guard let averageHeartRateBpm = post.averageHeartRateBpm, averageHeartRateBpm > 0 else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: "\(averageHeartRateBpm) bpm",
                    subtitle: nil,
                    accent: RBColor.danger
                )
            case .averageSpeed:
                guard let speed = post.averageSpeedKmh else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: String(format: "%.1f km/h", speed),
                    subtitle: nil,
                    accent: RBColor.success
                )
            case .cadence:
                guard let cadence = post.cadenceSpm, cadence > 0 else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: "\(cadence) spm",
                    subtitle: nil,
                    accent: RBColor.success
                )
            case .elevationGain:
                guard let elevation = post.elevationGainMeters else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: String(format: "%.0f m", elevation),
                    subtitle: nil,
                    accent: RBColor.accent
                )
            case .calories:
                guard let calories = post.caloriesKcal else { return nil }
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: String(format: "%.0f kcal", calories),
                    subtitle: nil,
                    accent: .orange
                )
            case .goalDelta:
                guard let delta = post.goalDeltaSeconds else { return nil }
                let isGoalMet = delta <= 0
                let value = isGoalMet
                    ? appLanguage.text("목표 달성", "Goal Hit")
                    : appLanguage.text(String(format: "+%d초", delta), String(format: "+%ds", delta))
                return RunSummaryMetric(
                    key: metric,
                    title: metric.title(appLanguage),
                    value: value,
                    subtitle: post.targetPaceFormatted,
                    accent: isGoalMet ? RBColor.success : RBColor.danger
                )
            }
        }
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
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
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

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        inputField(
                            title: appLanguage.text("제목", "Title"),
                            placeholder: appLanguage.text("러닝 메이트 모집 제목", "Running mate post title"),
                            text: $title
                        )

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
                                    Text(appLanguage.text("날짜 및 시간", "Date & Time"))
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

                                    DatePicker(appLanguage.text("시간 선택", "Choose time"), selection: $date, displayedComponents: .hourAndMinute)
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
                            Text(appLanguage.text("모임 장소", "Meetup location"))
                                .font(RBFont.caption(11))
                                .foregroundStyle(RBColor.textTertiary)

                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13))
                                    .foregroundStyle(RBColor.textTertiary)
                                TextField(appLanguage.text("장소 검색 (예: 반포한강공원)", "Search a place (e.g. Banpo Hangang Park)"), text: $locationSearchText)
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
                                Annotation(appLanguage.text("모임 장소", "Meetup location"), coordinate: selectedCoordinate) {
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
                            inputField(title: appLanguage.text("목표 페이스", "Target pace"), placeholder: "5'30\"", text: $targetPace)
                            inputField(title: appLanguage.text("목표 거리", "Target distance"), placeholder: "5km", text: $targetDistance)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(appLanguage.text("최대 인원", "Max members"))
                                    .font(RBFont.caption(11))
                                    .foregroundStyle(RBColor.textTertiary)
                                Spacer()
                                Button {
                                    withAnimation {
                                        isManualMemberInput.toggle()
                                        manualMemberText = "\(maxMembers)"
                                    }
                                } label: {
                                    Text(isManualMemberInput ? appLanguage.text("버튼 모드", "Stepper") : appLanguage.text("직접 입력", "Manual input"))
                                        .font(RBFont.caption(10))
                                        .foregroundStyle(RBColor.accent)
                                }
                            }

                            if isManualMemberInput {
                                HStack(spacing: 12) {
                                    TextField(appLanguage.text("인원 수", "Members"), text: $manualMemberText)
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
                                    Text(appLanguage.text("명", "people"))
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
                                    Text(appLanguage.text("명", "people"))
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
                            Text(appLanguage.text("상세 설명", "Details"))
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

                        RBPrimaryButton(appLanguage.text("모집 글 올리기", "Post Meetup"), icon: "paperplane.fill") {
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
            .navigationTitle(appLanguage.text("러닝 메이트 모집", "Create Running Mate Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appLanguage.text("취소", "Cancel")) { dismiss() }
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
    }

    private var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = appLanguage.isEnglish ? "MMM d (E) HH:mm" : "M/d (E) HH:mm"
        formatter.locale = appLanguage.isEnglish ? Locale(identifier: "en") : Locale(identifier: "ko_KR")
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
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @ObservedObject var viewModel: CommunityViewModel
    @State private var content = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?

    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appLanguage.text("내용", "Content"))
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
                            Text(appLanguage.text("사진 (선택)", "Photo (optional)"))
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
                                    Text(selectedPhotoData == nil ? appLanguage.text("사진 추가", "Add Photo") : appLanguage.text("사진 변경", "Change Photo"))
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

                        RBPrimaryButton(appLanguage.text("게시하기", "Publish"), icon: "paperplane.fill") {
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
            .navigationTitle(appLanguage.text("글 작성", "Write Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appLanguage.text("취소", "Cancel")) { dismiss() }
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
