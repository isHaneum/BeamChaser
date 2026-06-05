import Foundation

enum FriendshipStatus: Equatable {
    case none
    case sending
    case outgoingPending
    case incomingPending
    case friends
    case blockedByMe
    case blockedMe
    case error
}

struct FriendshipRelationship: Equatable {
    let userId: String
    var status: FriendshipStatus
    var requestId: String?
    var friendshipId: String?
    var isFollowing: Bool
    var detail: String?

    static func none(userId: String) -> FriendshipRelationship {
        FriendshipRelationship(
            userId: userId,
            status: .none,
            requestId: nil,
            friendshipId: nil,
            isFollowing: false,
            detail: nil
        )
    }
}

struct FriendshipSnapshot {
    let currentUserId: String
    let currentUsername: String
    let friends: [CommunityFriend]
    let blockedFriends: [CommunityFriend]
    let incomingRequests: [CommunityFriendRequest]
    let outgoingRequests: [CommunityFriendRequest]
    let suggestedFriends: [CommunityFriend]
    let relationshipsByUserId: [String: FriendshipRelationship]
    let usersById: [String: FirestorePublicUser]
    let blockedByMeUserIds: Set<String>
    let blockedMeUserIds: Set<String>
}

@MainActor
final class FriendshipService {
    private weak var backendService: BackendService?

    func configure(backendService: BackendService) {
        self.backendService = backendService
    }

    func loadSnapshot() async throws -> FriendshipSnapshot {
        guard let backendService, let currentUserId = backendService.userId else {
            throw FriendshipServiceError.loginRequired
        }

        async let usersTask = loadUsers(using: backendService)
        async let requestsTask = loadFriendRequests(using: backendService)
        async let friendshipsTask = loadFriendships(using: backendService)
        async let followsTask = loadFollowStates(using: backendService)
        async let blocksTask = loadBlocks(using: backendService)

        var users = await usersTask
        let requests = await requestsTask
        let friendships = await friendshipsTask
        let follows = await followsTask
        let blocks = await blocksTask

        let blockedByMeUserIds = Set(blocks.filter { $0.blockerId == currentUserId }.map(\.blockedId))
        let blockedMeUserIds = Set(blocks.filter { $0.blockedId == currentUserId }.map(\.blockerId))

        let requestCounterpartIds = Set(requests.compactMap { counterpartUserId(for: $0, currentUserId: currentUserId) })
        let friendshipCounterpartIds = Set(friendships.compactMap { counterpartUserId(for: $0, currentUserId: currentUserId) })
        let followCounterpartIds = Set(follows.map(\.followingId))
        let blockCounterpartIds = blockedByMeUserIds.union(blockedMeUserIds)
        let counterpartIds = requestCounterpartIds
            .union(friendshipCounterpartIds)
            .union(followCounterpartIds)
            .union(blockCounterpartIds)

        var usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.uid, $0) })
        let missingIds = counterpartIds.subtracting(usersById.keys)
        for missingId in missingIds {
            if let user = try? await backendService.fetchPublicUser(uid: missingId) {
                users.append(user)
                usersById[user.uid] = user
            }
        }

        let sortedRequests = requests.sorted { $0.createdAt > $1.createdAt }
        let friendshipsById = Dictionary(uniqueKeysWithValues: friendships.map { ($0.friendshipId.isEmpty ? $0.documentId : $0.friendshipId, $0) })

        var activeFriendIds = Set(friendships.filter(\.isActive).compactMap { counterpartUserId(for: $0, currentUserId: currentUserId) })
        for request in sortedRequests where request.status == "accepted" {
            guard let counterpartId = counterpartUserId(for: request, currentUserId: currentUserId) else { continue }
            let friendshipId = friendshipKey(currentUserId, counterpartId)
            if friendshipsById[friendshipId] == nil {
                activeFriendIds.insert(counterpartId)
            }
        }

        let explicitFollowStates = Dictionary(uniqueKeysWithValues: follows.map { ($0.followingId, $0.isActive) })

        var pendingByUserId: [String: FirestoreFriendRequest] = [:]
        for request in sortedRequests where request.status == "pending" {
            guard let counterpartId = counterpartUserId(for: request, currentUserId: currentUserId) else { continue }
            guard !activeFriendIds.contains(counterpartId) else { continue }
            guard !blockedByMeUserIds.contains(counterpartId), !blockedMeUserIds.contains(counterpartId) else { continue }
            if pendingByUserId[counterpartId] == nil {
                pendingByUserId[counterpartId] = request
            }
        }

        let visibleUsers = usersById.values.filter { user in
            user.uid != currentUserId && !blockedMeUserIds.contains(user.uid)
        }

        let friends = activeFriendIds
            .filter { !blockedByMeUserIds.contains($0) && !blockedMeUserIds.contains($0) }
            .compactMap { usersById[$0] }
            .map(makeCommunityFriend)
            .sorted(by: friendSort)

        let blockedFriends = blockedByMeUserIds
            .compactMap { usersById[$0] }
            .map(makeCommunityFriend)
            .sorted(by: friendSort)

        let incomingRequests = pendingByUserId.values
            .filter { $0.resolvedReceiverId == currentUserId }
            .compactMap { request -> CommunityFriendRequest? in
                guard let counterpart = usersById[request.resolvedSenderId] else { return nil }
                return CommunityFriendRequest(
                    id: request.documentId,
                    friend: makeCommunityFriend(from: counterpart),
                    source: request.source,
                    createdAt: request.createdAt,
                    isIncoming: true
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        let outgoingRequests = pendingByUserId.values
            .filter { $0.resolvedSenderId == currentUserId }
            .compactMap { request -> CommunityFriendRequest? in
                guard let counterpart = usersById[request.resolvedReceiverId] else { return nil }
                return CommunityFriendRequest(
                    id: request.documentId,
                    friend: makeCommunityFriend(from: counterpart),
                    source: request.source,
                    createdAt: request.createdAt,
                    isIncoming: false
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        let pendingIds = Set(pendingByUserId.keys)
        let suggestedFriends = visibleUsers
            .filter {
                !blockedByMeUserIds.contains($0.uid)
                    && !activeFriendIds.contains($0.uid)
                    && !pendingIds.contains($0.uid)
            }
            .sorted { lhs, rhs in
                if lhs.resolvedTotalDistanceKm == rhs.resolvedTotalDistanceKm {
                    if lhs.resolvedTotalRuns == rhs.resolvedTotalRuns {
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhs.resolvedTotalRuns > rhs.resolvedTotalRuns
                }
                return lhs.resolvedTotalDistanceKm > rhs.resolvedTotalDistanceKm
            }
            .prefix(10)
            .map(makeCommunityFriend)

        var relationshipsByUserId: [String: FriendshipRelationship] = [:]
        for user in usersById.values where user.uid != currentUserId {
            if blockedByMeUserIds.contains(user.uid) {
                relationshipsByUserId[user.uid] = FriendshipRelationship(
                    userId: user.uid,
                    status: .blockedByMe,
                    requestId: nil,
                    friendshipId: friendshipKey(currentUserId, user.uid),
                    isFollowing: false,
                    detail: nil
                )
                continue
            }

            if blockedMeUserIds.contains(user.uid) {
                relationshipsByUserId[user.uid] = FriendshipRelationship(
                    userId: user.uid,
                    status: .blockedMe,
                    requestId: nil,
                    friendshipId: nil,
                    isFollowing: false,
                    detail: nil
                )
                continue
            }

            if activeFriendIds.contains(user.uid) {
                relationshipsByUserId[user.uid] = FriendshipRelationship(
                    userId: user.uid,
                    status: .friends,
                    requestId: nil,
                    friendshipId: friendshipKey(currentUserId, user.uid),
                    isFollowing: explicitFollowStates[user.uid] ?? true,
                    detail: nil
                )
                continue
            }

            if let request = pendingByUserId[user.uid] {
                relationshipsByUserId[user.uid] = FriendshipRelationship(
                    userId: user.uid,
                    status: request.resolvedSenderId == currentUserId ? .outgoingPending : .incomingPending,
                    requestId: request.documentId,
                    friendshipId: nil,
                    isFollowing: false,
                    detail: nil
                )
                continue
            }

            relationshipsByUserId[user.uid] = .none(userId: user.uid)
        }

        let currentUsername = backendService.currentUser?.publicProfile.resolvedUsername
            ?? FirestorePublicUser.username(from: currentUserId)

        return FriendshipSnapshot(
            currentUserId: currentUserId,
            currentUsername: currentUsername,
            friends: friends,
            blockedFriends: blockedFriends,
            incomingRequests: incomingRequests,
            outgoingRequests: outgoingRequests,
            suggestedFriends: suggestedFriends,
            relationshipsByUserId: relationshipsByUserId,
            usersById: usersById,
            blockedByMeUserIds: blockedByMeUserIds,
            blockedMeUserIds: blockedMeUserIds
        )
    }

    private func loadUsers(using backendService: BackendService) async -> [FirestorePublicUser] {
        (try? await backendService.fetchUsers(limit: 160)) ?? []
    }

    private func loadFriendRequests(using backendService: BackendService) async -> [FirestoreFriendRequest] {
        (try? await backendService.fetchFriendRequests()) ?? []
    }

    private func loadFriendships(using backendService: BackendService) async -> [FirestoreFriendship] {
        (try? await backendService.fetchFriendships()) ?? []
    }

    private func loadFollowStates(using backendService: BackendService) async -> [FirestoreFollow] {
        (try? await backendService.fetchFollowStates()) ?? []
    }

    private func loadBlocks(using backendService: BackendService) async -> [FirestoreBlock] {
        (try? await backendService.fetchBlocks()) ?? []
    }

    func searchUsers(query: String) async throws -> [FirestorePublicUser] {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        return try await backendService.searchUsers(query: query, limit: 24)
    }

    func sendFriendRequest(to userId: String, source: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.sendFriendRequest(toUserId: userId, source: source)
    }

    func cancelFriendRequest(requestId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.cancelFriendRequest(requestId: requestId)
    }

    func acceptFriendRequest(requestId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.respondToFriendRequest(requestId: requestId, accept: true)
    }

    func rejectFriendRequest(requestId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.respondToFriendRequest(requestId: requestId, accept: false)
    }

    func setFeedVisibility(for userId: String, isVisible: Bool) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.setFollowState(targetUserId: userId, isActive: isVisible)
    }

    func removeFriend(userId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.removeFriend(targetUserId: userId)
    }

    func blockUser(userId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.blockUser(uid: userId)
    }

    func unblockUser(userId: String) async throws {
        guard let backendService else {
            throw FriendshipServiceError.unavailable
        }
        try await backendService.unblockUser(uid: userId)
    }

    func inviteShareText() -> String? {
        guard let backendService, let currentUserId = backendService.userId else { return nil }
        let username = backendService.currentUser?.publicProfile.resolvedUsername
            ?? FirestorePublicUser.username(from: currentUserId)
        return AppLanguage.current.text(
            "BeamChaser에서 @\(username) 로 나를 찾아 친구를 추가해줘.",
            "Find me on BeamChaser with @\(username)."
        )
    }

    private func counterpartUserId(for request: FirestoreFriendRequest, currentUserId: String) -> String? {
        let senderId = request.resolvedSenderId
        let receiverId = request.resolvedReceiverId
        guard !senderId.isEmpty, !receiverId.isEmpty else { return nil }
        if senderId == currentUserId {
            return receiverId
        }
        if receiverId == currentUserId {
            return senderId
        }
        return nil
    }

    private func counterpartUserId(for friendship: FirestoreFriendship, currentUserId: String) -> String? {
        friendship.users.first { $0 != currentUserId }
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

    private func friendSort(lhs: CommunityFriend, rhs: CommunityFriend) -> Bool {
        if lhs.totalDistanceKm == rhs.totalDistanceKm {
            if lhs.totalRuns == rhs.totalRuns {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.totalRuns > rhs.totalRuns
        }
        return lhs.totalDistanceKm > rhs.totalDistanceKm
    }

    private func friendshipKey(_ firstUserId: String, _ secondUserId: String) -> String {
        [firstUserId, secondUserId].sorted().joined(separator: "_")
    }
}
