import SwiftUI

struct FriendshipToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

enum FriendCardMenuActionKind: String, Identifiable {
    case viewRecords
    case hideFeed
    case showFeed
    case removeFriend
    case block
    case unblock
    case cancelRequest

    var id: String { rawValue }
}

struct FriendCardMenuAction: Identifiable {
    let kind: FriendCardMenuActionKind
    let title: String
    let systemImage: String
    let role: ButtonRole?

    var id: String { kind.id }
}

enum FriendConfirmationAction: Identifiable {
    case cancelRequest(CommunityFriendRequest)
    case removeFriend(CommunityFriend)
    case block(CommunityFriend)
    case unblock(CommunityFriend)

    var id: String {
        switch self {
        case let .cancelRequest(request):
            return "cancel-\(request.id)"
        case let .removeFriend(friend):
            return "remove-\(friend.id)"
        case let .block(friend):
            return "block-\(friend.id)"
        case let .unblock(friend):
            return "unblock-\(friend.id)"
        }
    }
}

@MainActor
final class FriendshipViewModel: ObservableObject {
    @Published private(set) var friends: [CommunityFriend] = []
    @Published private(set) var blockedFriends: [CommunityFriend] = []
    @Published private(set) var incomingRequests: [CommunityFriendRequest] = []
    @Published private(set) var outgoingRequests: [CommunityFriendRequest] = []
    @Published private(set) var suggestedFriends: [CommunityFriend] = []
    @Published private(set) var searchResults: [CommunityFriend] = []
    @Published private(set) var relationshipStates: [String: FriendshipRelationship] = [:]
    @Published private(set) var processingUserIds: Set<String> = []
    @Published private(set) var processingRequestIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var relationshipRevision = 0
    @Published var loadErrorMessage: String?
    @Published var toast: FriendshipToast?
    @Published var debugMessage: String?

    private let service = FriendshipService()
    private var backendService: BackendService?
    private var usersById: [String: FirestorePublicUser] = [:]
    private var currentUsername = ""
    private var blockedByMeUserIds: Set<String> = []
    private var blockedMeUserIds: Set<String> = []
    private var latestSearchQuery = ""
    private var toastDismissTask: Task<Void, Never>?

    deinit {
        toastDismissTask?.cancel()
    }

    var pendingRequestCount: Int {
        incomingRequests.count + outgoingRequests.count
    }

    var hiddenFeedCount: Int {
        relationshipStates.values.filter { $0.status == .friends && !$0.isFollowing }.count
    }

    var myRunnerId: String {
        currentUsername.isEmpty ? "-" : "@\(currentUsername)"
    }

    var inviteShareText: String? {
        service.inviteShareText()
    }

    func configure(backendService: BackendService) {
        guard self.backendService !== backendService else { return }
        self.backendService = backendService
        service.configure(backendService: backendService)
    }

    func refresh() async {
        guard backendService != nil else { return }

        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await service.loadSnapshot()
            apply(snapshot: snapshot)
        } catch {
            loadErrorMessage = AppLanguage.current.text(
                "친구 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.",
                "Couldn't load friend data. Please try again in a moment."
            )
            captureDebug(operation: "loadSnapshot", error: error)
        }
    }

    func clearSearch() {
        latestSearchQuery = ""
        searchResults = []
    }

    func search(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        latestSearchQuery = trimmedQuery

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let users = try await service.searchUsers(query: trimmedQuery)
            guard latestSearchQuery == trimmedQuery else { return }

            for user in users {
                usersById[user.uid] = user
                if relationshipStates[user.uid] == nil {
                    if blockedByMeUserIds.contains(user.uid) {
                        relationshipStates[user.uid] = FriendshipRelationship(
                            userId: user.uid,
                            status: .blockedByMe,
                            requestId: nil,
                            friendshipId: nil,
                            isFollowing: false,
                            detail: nil
                        )
                    } else if blockedMeUserIds.contains(user.uid) {
                        relationshipStates[user.uid] = FriendshipRelationship(
                            userId: user.uid,
                            status: .blockedMe,
                            requestId: nil,
                            friendshipId: nil,
                            isFollowing: false,
                            detail: nil
                        )
                    } else {
                        relationshipStates[user.uid] = .none(userId: user.uid)
                    }
                }
            }

            searchResults = users
                .filter { !blockedByMeUserIds.contains($0.uid) && !blockedMeUserIds.contains($0.uid) }
                .map(makeCommunityFriend)
        } catch {
            showToast(
                AppLanguage.current.text(
                    "검색 결과를 불러오지 못했어요.",
                    "Couldn't load search results."
                ),
                isError: true
            )
            captureDebug(operation: "searchUsers", error: error)
        }
    }

    func relationship(for userId: String) -> FriendshipRelationship {
        relationshipStates[userId] ?? .none(userId: userId)
    }

    func isProcessing(userId: String) -> Bool {
        processingUserIds.contains(userId)
    }

    func isProcessing(requestId: String) -> Bool {
        processingRequestIds.contains(requestId)
    }

    func sendFriendRequest(to friend: CommunityFriend, source: String = "manual") async {
        processingUserIds.insert(friend.id)
        relationshipStates[friend.id] = FriendshipRelationship(
            userId: friend.id,
            status: .sending,
            requestId: relationshipStates[friend.id]?.requestId,
            friendshipId: relationshipStates[friend.id]?.friendshipId,
            isFollowing: relationshipStates[friend.id]?.isFollowing ?? false,
            detail: nil
        )

        do {
            try await service.sendFriendRequest(to: friend.id, source: source)
            showToast(AppLanguage.current.text("친구 요청을 보냈어요.", "Friend request sent."), isError: false)
            processingUserIds.remove(friend.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(friend.id)
            await handleSendError(for: friend, error: error)
        }
    }

    func cancelRequest(_ request: CommunityFriendRequest) async {
        processingUserIds.insert(request.friend.id)
        processingRequestIds.insert(request.id)

        do {
            try await service.cancelFriendRequest(requestId: request.id)
            showToast(AppLanguage.current.text("요청을 취소했어요.", "Request canceled."), isError: false)
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            showToast(
                AppLanguage.current.text(
                    "친구 요청을 보내지 못했어요. 잠시 후 다시 시도해주세요.",
                    "Couldn't update the friend request. Please try again in a moment."
                ),
                isError: true
            )
            captureDebug(operation: "cancelFriendRequest", error: error)
        }
    }

    func acceptRequest(_ request: CommunityFriendRequest) async {
        processingUserIds.insert(request.friend.id)
        processingRequestIds.insert(request.id)
        relationshipStates[request.friend.id] = FriendshipRelationship(
            userId: request.friend.id,
            status: .sending,
            requestId: request.id,
            friendshipId: nil,
            isFollowing: true,
            detail: nil
        )

        do {
            try await service.acceptFriendRequest(requestId: request.id)
            showToast(AppLanguage.current.text("러닝 메이트가 되었어요.", "You're now running mates."), isError: false)
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            showToast(
                AppLanguage.current.text(
                    "친구 요청을 보내지 못했어요. 잠시 후 다시 시도해주세요.",
                    "Couldn't update the friend request. Please try again in a moment."
                ),
                isError: true
            )
            captureDebug(operation: "acceptFriendRequest", error: error)
            await refresh()
        }
    }

    func rejectRequest(_ request: CommunityFriendRequest) async {
        processingUserIds.insert(request.friend.id)
        processingRequestIds.insert(request.id)

        do {
            try await service.rejectFriendRequest(requestId: request.id)
            showToast(AppLanguage.current.text("요청을 정리했어요.", "Request cleared."), isError: false)
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(request.friend.id)
            processingRequestIds.remove(request.id)
            showToast(
                AppLanguage.current.text(
                    "친구 요청을 보내지 못했어요. 잠시 후 다시 시도해주세요.",
                    "Couldn't update the friend request. Please try again in a moment."
                ),
                isError: true
            )
            captureDebug(operation: "rejectFriendRequest", error: error)
            await refresh()
        }
    }

    func setFeedVisibility(for friend: CommunityFriend, isVisible: Bool) async {
        processingUserIds.insert(friend.id)

        do {
            try await service.setFeedVisibility(for: friend.id, isVisible: isVisible)
            showToast(
                AppLanguage.current.text(
                    isVisible ? "피드를 다시 보여줄게요." : "피드를 숨겼어요.",
                    isVisible ? "Showing this feed again." : "Feed hidden."
                ),
                isError: false
            )
            processingUserIds.remove(friend.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(friend.id)
            showToast(
                AppLanguage.current.text("잠시 후 다시 시도해주세요.", "Please try again in a moment."),
                isError: true
            )
            captureDebug(operation: isVisible ? "showFeed" : "hideFeed", error: error)
        }
    }

    func removeFriend(_ friend: CommunityFriend) async {
        processingUserIds.insert(friend.id)

        do {
            try await service.removeFriend(userId: friend.id)
            showToast(AppLanguage.current.text("친구를 정리했어요.", "Friend removed."), isError: false)
            processingUserIds.remove(friend.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(friend.id)
            showToast(
                AppLanguage.current.text("잠시 후 다시 시도해주세요.", "Please try again in a moment."),
                isError: true
            )
            captureDebug(operation: "removeFriend", error: error)
        }
    }

    func block(_ friend: CommunityFriend) async {
        processingUserIds.insert(friend.id)

        do {
            try await service.blockUser(userId: friend.id)
            showToast(AppLanguage.current.text("차단했어요.", "User blocked."), isError: false)
            processingUserIds.remove(friend.id)
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(friend.id)
            showToast(
                AppLanguage.current.text("잠시 후 다시 시도해주세요.", "Please try again in a moment."),
                isError: true
            )
            captureDebug(operation: "blockUser", error: error)
        }
    }

    func unblock(_ friend: CommunityFriend) async {
        processingUserIds.insert(friend.id)

        do {
            try await service.unblockUser(userId: friend.id)
            processingUserIds.remove(friend.id)
            blockedFriends.removeAll { $0.id == friend.id }
            blockedByMeUserIds.remove(friend.id)
            relationshipStates[friend.id] = .none(userId: friend.id)
            showToast(
                AppLanguage.current.text(
                    "차단을 해제했어요. 다시 친구가 되려면 친구 요청을 보내야 합니다.",
                    "User unblocked. Send a new friend request to reconnect."
                ),
                isError: false
            )
            await refresh()
            markMutation()
        } catch {
            processingUserIds.remove(friend.id)
            showToast(
                AppLanguage.current.text(
                    "차단 해제에 실패했어요. 잠시 후 다시 시도해주세요.",
                    "Couldn't unblock the user. Please try again in a moment."
                ),
                isError: true
            )
            captureDebug(operation: "unblockUser", error: error)
        }
    }

    private func apply(snapshot: FriendshipSnapshot) {
        currentUsername = snapshot.currentUsername
        friends = snapshot.friends
        blockedFriends = snapshot.blockedFriends
        incomingRequests = snapshot.incomingRequests
        outgoingRequests = snapshot.outgoingRequests
        suggestedFriends = snapshot.suggestedFriends
        usersById = snapshot.usersById
        blockedByMeUserIds = snapshot.blockedByMeUserIds
        blockedMeUserIds = snapshot.blockedMeUserIds

        var mergedStates = snapshot.relationshipsByUserId
        for userId in processingUserIds {
            mergedStates[userId] = FriendshipRelationship(
                userId: userId,
                status: .sending,
                requestId: mergedStates[userId]?.requestId,
                friendshipId: mergedStates[userId]?.friendshipId,
                isFollowing: mergedStates[userId]?.isFollowing ?? false,
                detail: nil
            )
        }
        relationshipStates = mergedStates

        searchResults = searchResults
            .filter { !blockedByMeUserIds.contains($0.id) && !blockedMeUserIds.contains($0.id) }
            .map { friend in
                if let user = usersById[friend.id] {
                    return makeCommunityFriend(from: user)
                }
                return friend
            }
    }

    private func handleSendError(for friend: CommunityFriend, error: Error) async {
        let genericMessage = AppLanguage.current.text(
            "친구 요청을 보내지 못했어요.",
            "Couldn't send the friend request."
        )

        if let friendshipError = error as? FriendshipServiceError {
            switch friendshipError {
            case .alreadyFriends, .outgoingPending, .incomingPending, .blocked, .blockedByUser:
                showToast(friendshipError.localizedDescription, isError: true)
                captureDebug(operation: "sendFriendRequest", error: error)
                await refresh()
                return
            case .loginRequired, .unavailable, .cannotFriendYourself, .userNotFound, .requestNotFound, .friendshipNotFound, .noPermission, .alreadyHandled:
                break
            }
        }

        relationshipStates[friend.id] = FriendshipRelationship(
            userId: friend.id,
            status: .error,
            requestId: nil,
            friendshipId: nil,
            isFollowing: false,
            detail: genericMessage
        )
        showToast(genericMessage, isError: true)
        captureDebug(operation: "sendFriendRequest", error: error)
    }

    private func showToast(_ text: String, isError: Bool) {
        toastDismissTask?.cancel()

        let newToast = FriendshipToast(text: text, isError: isError)
        toast = newToast

        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled, self.toast?.id == newToast.id else { return }
            self.toast = nil
        }
    }

    private func captureDebug(operation: String, error: Error) {
        let nsError = error as NSError
        debugMessage = nil
        #if DEBUG
        print("DEBUG \(operation) • \(nsError.domain) • \(nsError.code) • \(nsError.localizedDescription)")
        #endif
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

    private func markMutation() {
        relationshipRevision += 1
    }
}

struct CommunityFriendView: View {
    @ObservedObject var viewModel: FriendshipViewModel
    @Binding var selection: CommunityView.MateMode
    @State private var searchText = ""
    @State private var confirmationAction: FriendConfirmationAction?
    @State private var selectedRecordFriend: CommunityFriend?
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private let accent = AppColorTheme.ember.primary
    private let accentDeep = AppColorTheme.ember.gradientTail
    private let accentSurface = AppColorTheme.ember.accentSurfaceLight

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage = viewModel.loadErrorMessage {
                friendlyErrorCard(errorMessage)
            }

            summaryCard

            switch selection {
            case .friends:
                friendsSection
            case .requests:
                requestsSection
            case .discover:
                findSection
            }

        }
        .overlay(alignment: .top) {
            if let toast = viewModel.toast {
                toastView(toast)
                    .padding(.top, 8)
            }
        }
        .task(id: searchText) {
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard selection == .discover else { return }
            if trimmed.isEmpty {
                viewModel.clearSearch()
                return
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.search(query: trimmed)
        }
        .alert(item: $confirmationAction) { action in
            switch action {
            case let .cancelRequest(request):
                return Alert(
                    title: Text(appLanguage.text("요청을 취소할까요?", "Cancel request?")),
                    message: Text(appLanguage.text("보낸 친구 요청을 취소합니다.", "This will cancel the sent request.")),
                    primaryButton: .destructive(Text(appLanguage.text("요청 취소", "Cancel Request"))) {
                        Task { await viewModel.cancelRequest(request) }
                    },
                    secondaryButton: .cancel(Text(appLanguage.text("닫기", "Close")))
                )
            case let .removeFriend(friend):
                return Alert(
                    title: Text(appLanguage.text("친구를 끊을까요?", "Remove friend?")),
                    message: Text(appLanguage.text("친구를 끊으면 새 요청이 필요해요.", "You'll need a new request to connect again.")),
                    primaryButton: .destructive(Text(appLanguage.text("친구 끊기", "Remove"))) {
                        Task { await viewModel.removeFriend(friend) }
                    },
                    secondaryButton: .cancel(Text(appLanguage.text("닫기", "Close")))
                )
            case let .block(friend):
                return Alert(
                    title: Text(appLanguage.text("이 사용자를 차단할까요?", "Block this user?")),
                    message: Text(appLanguage.text("서로의 기록과 피드를 볼 수 없고, 친구 요청을 주고받을 수 없습니다.", "You won't be able to see each other's runs or feeds, and friend requests will be blocked.")),
                    primaryButton: .destructive(Text(appLanguage.text("차단하기", "Block"))) {
                        Task { await viewModel.block(friend) }
                    },
                    secondaryButton: .cancel(Text(appLanguage.text("취소", "Cancel")))
                )
            case let .unblock(friend):
                return Alert(
                    title: Text(appLanguage.text("차단을 해제할까요?", "Unblock this user?")),
                    message: Text(appLanguage.text("친구 관계는 자동으로 복구되지 않아요. 다시 친구가 되려면 새 친구 요청이 필요합니다.", "Friendship won't be restored automatically. You'll need a new friend request to reconnect.")),
                    primaryButton: .default(Text(appLanguage.text("차단 해제", "Unblock"))) {
                        Task { await viewModel.unblock(friend) }
                    },
                    secondaryButton: .cancel(Text(appLanguage.text("취소", "Cancel")))
                )
            }
        }
        .sheet(item: $selectedRecordFriend) { friend in
            FriendRecordSheet(friend: friend, relationship: viewModel.relationship(for: friend.id), accent: accent)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage.text("친구 네트워크", "Friend Network"))
                        .font(RBFont.label(20))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(viewModel.myRunnerId)
                        .font(RBFont.caption(12))
                        .foregroundStyle(accentDeep)
                }
                Spacer()
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
            }

            HStack(spacing: 12) {
                summaryMetric(title: appLanguage.text("친구", "Friends"), value: "\(viewModel.friends.count)")
                summaryMetric(title: appLanguage.text("대기", "Pending"), value: "\(viewModel.pendingRequestCount)")
                summaryMetric(title: appLanguage.text("숨김", "Hidden"), value: "\(viewModel.hiddenFeedCount)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentSurface, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
    }

    private var friendsSection: some View {
        VStack(spacing: 14) {
            sectionHeader(title: appLanguage.text("친구", "Friends"), count: viewModel.friends.count)

            if viewModel.isLoading && viewModel.friends.isEmpty && viewModel.blockedFriends.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    FriendSkeletonCard()
                }
            } else if viewModel.friends.isEmpty && viewModel.blockedFriends.isEmpty {
                emptyState(
                    icon: "person.2.slash",
                    title: appLanguage.text("아직 친구가 없어요", "No friends yet"),
                    subtitle: appLanguage.text("찾기 탭에서 친구를 추가해보세요.", "Find friends from the Find tab.")
                )
            } else {
                ForEach(viewModel.friends) { friend in
                    let relationship = viewModel.relationship(for: friend.id)
                    FriendCard(
                        friend: friend,
                        relationship: relationship,
                        accent: accent,
                        accentDeep: accentDeep,
                        isProcessing: viewModel.isProcessing(userId: friend.id),
                        onTapPrimary: {
                            if relationship.status == .friends && !relationship.isFollowing {
                                Task { await viewModel.setFeedVisibility(for: friend, isVisible: true) }
                            }
                        },
                        onOpenRequests: {},
                        menuActions: menuActions(for: friend, relationship: relationship),
                        onMenuAction: { action in
                            handleMenuAction(action, friend: friend, relationship: relationship)
                        }
                    )
                }

                if !viewModel.blockedFriends.isEmpty {
                    sectionHeader(title: appLanguage.text("차단한 사용자", "Blocked"), count: viewModel.blockedFriends.count)

                    ForEach(viewModel.blockedFriends) { friend in
                        let relationship = viewModel.relationship(for: friend.id)
                        FriendCard(
                            friend: friend,
                            relationship: relationship,
                            accent: accent,
                            accentDeep: accentDeep,
                            isProcessing: viewModel.isProcessing(userId: friend.id),
                            onTapPrimary: {
                                confirmationAction = .unblock(friend)
                            },
                            onOpenRequests: {},
                            menuActions: menuActions(for: friend, relationship: relationship),
                            onMenuAction: { action in
                                handleMenuAction(action, friend: friend, relationship: relationship)
                            }
                        )
                    }
                }
            }
        }
    }

    private var requestsSection: some View {
        VStack(spacing: 14) {
            if viewModel.isLoading && viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    FriendSkeletonCard()
                }
            } else if viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty {
                emptyState(
                    icon: "tray",
                    title: appLanguage.text("대기 중인 요청이 없어요", "No pending requests"),
                    subtitle: appLanguage.text("새 요청이 오면 여기에서 바로 처리할 수 있어요.", "New requests will appear here.")
                )
            } else {
                if !viewModel.incomingRequests.isEmpty {
                    sectionHeader(title: appLanguage.text("받은 요청", "Incoming"), count: viewModel.incomingRequests.count)

                    ForEach(viewModel.incomingRequests) { request in
                        FriendRequestCard(
                            request: request,
                            accent: accent,
                            accentDeep: accentDeep,
                            isProcessing: viewModel.isProcessing(requestId: request.id),
                            onAccept: { Task { await viewModel.acceptRequest(request) } },
                            onReject: { Task { await viewModel.rejectRequest(request) } },
                            onCancel: {},
                            menuActions: requestMenuActions(for: request),
                            onMenuAction: { action in
                                handleRequestMenuAction(action, request: request)
                            }
                        )
                    }
                }

                if !viewModel.outgoingRequests.isEmpty {
                    sectionHeader(title: appLanguage.text("보낸 요청", "Sent"), count: viewModel.outgoingRequests.count)

                    ForEach(viewModel.outgoingRequests) { request in
                        FriendRequestCard(
                            request: request,
                            accent: accent,
                            accentDeep: accentDeep,
                            isProcessing: viewModel.isProcessing(requestId: request.id),
                            onAccept: {},
                            onReject: {},
                            onCancel: {
                                confirmationAction = .cancelRequest(request)
                            },
                            menuActions: requestMenuActions(for: request),
                            onMenuAction: { action in
                                handleRequestMenuAction(action, request: request)
                            }
                        )
                    }
                }
            }
        }
    }

    private var findSection: some View {
        VStack(spacing: 14) {
            FriendSearchSection(
                text: $searchText,
                isSearching: viewModel.isSearching,
                placeholder: appLanguage.text("아이디 또는 이름 검색", "Search by ID or name")
            )

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sectionHeader(title: appLanguage.text("검색 결과", "Results"), count: viewModel.searchResults.count)

                if viewModel.isSearching {
                    ProgressView()
                        .tint(accent)
                        .padding(.vertical, 20)
                } else if viewModel.searchResults.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: appLanguage.text("검색 결과가 없어요", "No results"),
                        subtitle: appLanguage.text("아이디나 이름을 다시 확인해주세요.", "Check the ID or name and try again.")
                    )
                } else {
                    ForEach(viewModel.searchResults) { friend in
                        let relationship = viewModel.relationship(for: friend.id)
                        FriendCard(
                            friend: friend,
                            relationship: relationship,
                            accent: accent,
                            accentDeep: accentDeep,
                            isProcessing: viewModel.isProcessing(userId: friend.id),
                            onTapPrimary: {
                                Task { await viewModel.sendFriendRequest(to: friend, source: "search") }
                            },
                            onOpenRequests: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    selection = .requests
                                }
                            },
                            menuActions: menuActions(for: friend, relationship: relationship),
                            onMenuAction: { action in
                                handleMenuAction(action, friend: friend, relationship: relationship)
                            }
                        )
                    }
                }
            }

            sectionHeader(title: appLanguage.text("추천 친구", "Suggested"), count: viewModel.suggestedFriends.count)

            if viewModel.isLoading && viewModel.suggestedFriends.isEmpty && searchText.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    FriendSkeletonCard()
                }
            } else if viewModel.suggestedFriends.isEmpty {
                emptyState(
                    icon: "sparkles",
                    title: appLanguage.text("추천 친구가 없어요", "No suggestions right now"),
                    subtitle: appLanguage.text("새 러너가 보이면 여기에서 바로 추가할 수 있어요.", "New runners will appear here.")
                )
            } else {
                ForEach(viewModel.suggestedFriends) { friend in
                    let relationship = viewModel.relationship(for: friend.id)
                    FriendCard(
                        friend: friend,
                        relationship: relationship,
                        accent: accent,
                        accentDeep: accentDeep,
                        isProcessing: viewModel.isProcessing(userId: friend.id),
                        onTapPrimary: {
                            Task { await viewModel.sendFriendRequest(to: friend, source: "manual") }
                        },
                        onOpenRequests: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                selection = .requests
                            }
                        },
                        menuActions: menuActions(for: friend, relationship: relationship),
                        onMenuAction: { action in
                            handleMenuAction(action, friend: friend, relationship: relationship)
                        }
                    )
                }
            }
        }
    }

    private func menuActions(for friend: CommunityFriend, relationship: FriendshipRelationship) -> [FriendCardMenuAction] {
        switch relationship.status {
        case .friends:
            return [
                FriendCardMenuAction(kind: .viewRecords, title: appLanguage.text("기록 보기", "View Records"), systemImage: "figure.run", role: nil),
                FriendCardMenuAction(
                    kind: relationship.isFollowing ? .hideFeed : .showFeed,
                    title: appLanguage.text(
                        relationship.isFollowing ? "피드 숨기기" : "피드 다시 보기",
                        relationship.isFollowing ? "Hide Feed" : "Show Feed Again"
                    ),
                    systemImage: relationship.isFollowing ? "eye.slash" : "eye",
                    role: nil
                ),
                FriendCardMenuAction(kind: .removeFriend, title: appLanguage.text("친구 끊기", "Remove Friend"), systemImage: "person.crop.circle.badge.minus", role: .destructive),
                FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
            ]
        case .blockedByMe:
            return [
                FriendCardMenuAction(kind: .unblock, title: appLanguage.text("차단 해제", "Unblock"), systemImage: "hand.raised.slash", role: nil),
            ]
        case .outgoingPending:
            return [
                FriendCardMenuAction(kind: .cancelRequest, title: appLanguage.text("요청 취소", "Cancel Request"), systemImage: "xmark.circle", role: .destructive),
                FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
            ]
        case .incomingPending:
            return [
                FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
            ]
        case .blockedMe:
            return []
        case .none, .sending, .error:
            return [
                FriendCardMenuAction(kind: .viewRecords, title: appLanguage.text("기록 보기", "View Records"), systemImage: "figure.run", role: nil),
                FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
            ]
        }
    }

    private func requestMenuActions(for request: CommunityFriendRequest) -> [FriendCardMenuAction] {
        if request.isIncoming {
            return [
                FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
            ]
        }

        return [
            FriendCardMenuAction(kind: .cancelRequest, title: appLanguage.text("요청 취소", "Cancel Request"), systemImage: "xmark.circle", role: .destructive),
            FriendCardMenuAction(kind: .block, title: appLanguage.text("차단", "Block"), systemImage: "hand.raised.fill", role: .destructive),
        ]
    }

    private func handleMenuAction(_ action: FriendCardMenuActionKind, friend: CommunityFriend, relationship: FriendshipRelationship) {
        switch action {
        case .viewRecords:
            selectedRecordFriend = friend
        case .hideFeed:
            Task { await viewModel.setFeedVisibility(for: friend, isVisible: false) }
        case .showFeed:
            Task { await viewModel.setFeedVisibility(for: friend, isVisible: true) }
        case .removeFriend:
            confirmationAction = .removeFriend(friend)
        case .block:
            confirmationAction = .block(friend)
        case .unblock:
            confirmationAction = .unblock(friend)
        case .cancelRequest:
            if let requestId = relationship.requestId,
               let request = viewModel.outgoingRequests.first(where: { $0.id == requestId }) {
                confirmationAction = .cancelRequest(request)
            }
        }
    }

    private func handleRequestMenuAction(_ action: FriendCardMenuActionKind, request: CommunityFriendRequest) {
        switch action {
        case .cancelRequest:
            confirmationAction = .cancelRequest(request)
        case .block:
            confirmationAction = .block(request.friend)
        case .viewRecords:
            selectedRecordFriend = request.friend
        case .hideFeed, .showFeed, .removeFriend, .unblock:
            break
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RBFont.caption(11))
                .foregroundStyle(RBColor.textSecondary)
            Text(value)
                .font(RBFont.label(18))
                .foregroundStyle(RBColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)
            Text("\(count)")
                .font(RBFont.caption(11))
                .foregroundStyle(accentDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(accentSurface)
                )
            Spacer()
        }
    }

    private func friendlyErrorCard(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentDeep)

            Text(text)
                .font(RBFont.body(13))
                .foregroundStyle(RBColor.textPrimary)

            Spacer()

            Button(appLanguage.text("다시 시도", "Retry")) {
                Task { await viewModel.refresh() }
            }
            .font(RBFont.label(12))
            .foregroundStyle(accentDeep)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentSurface)
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(title)
                .font(RBFont.label(16))
                .foregroundStyle(RBColor.textPrimary)

            Text(subtitle)
                .font(RBFont.caption(12))
                .foregroundStyle(RBColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RBColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RBColor.divider.opacity(0.7), lineWidth: 1)
        )
    }

    private func toastView(_ toast: FriendshipToast) -> some View {
        Text(toast.text)
            .font(RBFont.label(13))
            .foregroundStyle(toast.isError ? Color.white : RBColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(toast.isError ? RBColor.textPrimary : Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(toast.isError ? Color.white.opacity(0.12) : accent.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
    }

}

struct FriendTabs: View {
    @Binding var selection: CommunityView.MateMode
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private let accent = AppColorTheme.ember.primary
    private let accentSurface = AppColorTheme.ember.accentSurfaceLight

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CommunityView.MateMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: modeIcon(mode))
                            .font(.system(size: 12, weight: .semibold))
                        Text(modeTitle(mode))
                            .font(RBFont.label(13))
                    }
                    .foregroundStyle(selection == mode ? accent : RBColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(selection == mode ? accentSurface : RBColor.cardBg)
                    )
                    .overlay(
                        Capsule()
                            .stroke(selection == mode ? accent.opacity(0.22) : RBColor.divider.opacity(0.7), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func modeTitle(_ mode: CommunityView.MateMode) -> String {
        switch mode {
        case .friends:
            return appLanguage.text("친구", "Friends")
        case .requests:
            return appLanguage.text("요청", "Requests")
        case .discover:
            return appLanguage.text("찾기", "Find")
        }
    }

    private func modeIcon(_ mode: CommunityView.MateMode) -> String {
        switch mode {
        case .friends:
            return "person.2.fill"
        case .requests:
            return "bell.badge.fill"
        case .discover:
            return "magnifyingglass"
        }
    }
}

struct FriendSearchSection: View {
    @Binding var text: String
    let isSearching: Bool
    let placeholder: String

    private let accent = AppColorTheme.ember.primary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RBColor.textSecondary)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(RBFont.body(14))
                .foregroundStyle(RBColor.textPrimary)

            if isSearching {
                ProgressView()
                    .tint(accent)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RBColor.divider.opacity(0.7), lineWidth: 1)
        )
    }
}

struct FriendCard: View {
    let friend: CommunityFriend
    let relationship: FriendshipRelationship
    let accent: Color
    let accentDeep: Color
    let isProcessing: Bool
    let onTapPrimary: () -> Void
    let onOpenRequests: () -> Void
    let menuActions: [FriendCardMenuAction]
    let onMenuAction: (FriendCardMenuActionKind) -> Void

    var body: some View {
        HStack(spacing: 14) {
            FriendAvatar(name: friend.name, photoURL: friend.photoURL, accent: accent)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(friend.name)
                        .font(RBFont.label(16))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(friend.level.rawValue)
                        .font(RBFont.caption(10))
                        .foregroundStyle(accentDeep)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.10))
                        )
                }

                Text(friend.handle)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)

                Text(friend.recordSummary)
                    .font(RBFont.caption(12))
                    .foregroundStyle(RBColor.textSecondary)

                if relationship.status == .friends && !relationship.isFollowing {
                    statusBadge("피드 숨김")
                } else if relationship.status == .blockedByMe {
                    statusBadge("차단됨")
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 10) {
                if !menuActions.isEmpty {
                    Menu {
                        ForEach(menuActions) { action in
                            Button(role: action.role) {
                                onMenuAction(action.kind)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(RBColor.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(RBColor.cardBgLight)
                            )
                    }
                }

                FriendshipButton(
                    relationship: relationship,
                    accent: accent,
                    isProcessing: isProcessing,
                    onTapPrimary: onTapPrimary,
                    onOpenRequests: onOpenRequests
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RBColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RBColor.divider.opacity(0.65), lineWidth: 1)
        )
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(RBFont.caption(11))
            .foregroundStyle(accentDeep)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accent.opacity(0.10))
            )
    }
}

struct FriendRequestCard: View {
    let request: CommunityFriendRequest
    let accent: Color
    let accentDeep: Color
    let isProcessing: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCancel: () -> Void
    let menuActions: [FriendCardMenuAction]
    let onMenuAction: (FriendCardMenuActionKind) -> Void

    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                FriendAvatar(name: request.friend.name, photoURL: request.friend.photoURL, accent: accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.friend.name)
                        .font(RBFont.label(16))
                        .foregroundStyle(RBColor.textPrimary)
                    Text(request.friend.handle)
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                    Text(request.friend.recordSummary)
                        .font(RBFont.caption(12))
                        .foregroundStyle(RBColor.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(request.isIncoming ? appLanguage.text("받은 요청", "Incoming") : appLanguage.text("보낸 요청", "Sent"))
                        .font(RBFont.caption(11))
                        .foregroundStyle(accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.10))
                        )

                    if !menuActions.isEmpty {
                        Menu {
                            ForEach(menuActions) { action in
                                Button(role: action.role) {
                                    onMenuAction(action.kind)
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(RBColor.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(RBColor.cardBgLight)
                                )
                        }
                    }
                }
            }

            if isProcessing {
                ProgressView()
                    .tint(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if request.isIncoming {
                HStack(spacing: 10) {
                    Button(action: onReject) {
                        Text(appLanguage.text("거절", "Decline"))
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(RBColor.cardBgLight)
                            )
                    }

                    Button(action: onAccept) {
                        Text(appLanguage.text("수락", "Accept"))
                            .font(RBFont.label(13))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(LinearGradient(colors: [accent, accentDeep], startPoint: .leading, endPoint: .trailing))
                            )
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Text(appLanguage.text("수락 대기중", "Awaiting response"))
                        .font(RBFont.label(13))
                        .foregroundStyle(accentDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accent.opacity(0.08))
                        )

                    Button(action: onCancel) {
                        Text(appLanguage.text("취소", "Cancel"))
                            .font(RBFont.label(13))
                            .foregroundStyle(RBColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(RBColor.cardBgLight)
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RBColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RBColor.divider.opacity(0.65), lineWidth: 1)
        )
    }
}

struct FriendshipButton: View {
    let relationship: FriendshipRelationship
    let accent: Color
    let isProcessing: Bool
    let onTapPrimary: () -> Void
    let onOpenRequests: () -> Void

    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        Group {
            switch relationship.status {
            case .none:
                primaryButton(title: appLanguage.text("친구 추가", "Add Friend"), action: onTapPrimary)
            case .sending:
                secondaryPill(title: appLanguage.text("전송 중...", "Sending..."), highlighted: true)
            case .outgoingPending:
                secondaryPill(title: appLanguage.text("수락 대기중", "Awaiting"), highlighted: true)
            case .incomingPending:
                primaryButton(title: appLanguage.text("요청 확인", "Review"), action: onOpenRequests)
            case .friends:
                if relationship.isFollowing {
                    secondaryPill(title: appLanguage.text("친구", "Friends"), highlighted: false)
                } else {
                    primaryButton(title: appLanguage.text("피드 다시 보기", "Show Feed Again"), action: onTapPrimary)
                }
            case .blockedByMe:
                primaryButton(title: appLanguage.text("차단 해제", "Unblock"), action: onTapPrimary)
            case .blockedMe:
                secondaryPill(title: appLanguage.text("차단됨", "Blocked"), highlighted: false)
            case .error:
                primaryButton(title: appLanguage.text("다시 시도", "Retry"), action: onTapPrimary)
            }
        }
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RBFont.label(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(accent)
                )
        }
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.7 : 1)
    }

    private func secondaryPill(title: String, highlighted: Bool) -> some View {
        Text(title)
            .font(RBFont.label(12))
            .foregroundStyle(highlighted ? accent : RBColor.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(highlighted ? accent.opacity(0.10) : RBColor.cardBgLight)
            )
    }
}

struct FriendAvatar: View {
    let name: String
    let photoURL: String?
    let accent: Color

    var body: some View {
        ZStack {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "R" }

        let parts = trimmed.split(separator: " ").prefix(2)
        if parts.isEmpty {
            return String(trimmed.prefix(1)).uppercased()
        }

        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
            Text(initials)
                .font(RBFont.label(15))
                .foregroundStyle(accent)
        }
    }
}

struct FriendSkeletonCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(RBColor.cardBgLight)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RBColor.cardBgLight)
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RBColor.cardBgLight)
                    .frame(width: 86, height: 12)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RBColor.cardBgLight)
                    .frame(width: 104, height: 12)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RBColor.cardBgLight)
                .frame(width: 84, height: 36)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RBColor.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RBColor.divider.opacity(0.65), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
    }
}

struct FriendRecordSheet: View {
    let friend: CommunityFriend
    let relationship: FriendshipRelationship
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FriendAvatar(name: friend.name, photoURL: friend.photoURL, accent: accent)
                        .frame(width: 88, height: 88)

                    VStack(spacing: 6) {
                        Text(friend.name)
                            .font(RBFont.label(22))
                            .foregroundStyle(RBColor.textPrimary)
                        Text(friend.handle)
                            .font(RBFont.caption(13))
                            .foregroundStyle(RBColor.textSecondary)
                    }

                    VStack(spacing: 12) {
                        metricRow(title: appLanguage.text("누적 거리", "Total Distance"), value: String(format: "%.1fkm", friend.totalDistanceKm))
                        metricRow(title: appLanguage.text("러닝 횟수", "Runs"), value: "\(friend.totalRuns)")
                        metricRow(title: appLanguage.text("상태", "Status"), value: statusText)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(RBColor.cardBg)
                    )
                }
                .padding(20)
            }
            .background(RBColor.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLanguage.text("닫기", "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch relationship.status {
        case .none:
            return appLanguage.text("친구 아님", "Not friends")
        case .sending:
            return appLanguage.text("전송 중", "Sending")
        case .outgoingPending:
            return appLanguage.text("수락 대기중", "Awaiting response")
        case .incomingPending:
            return appLanguage.text("응답 필요", "Needs response")
        case .friends:
            return relationship.isFollowing
                ? appLanguage.text("친구", "Friends")
                : appLanguage.text("친구 · 피드 숨김", "Friends · feed hidden")
        case .blockedByMe:
            return appLanguage.text("차단함", "Blocked by me")
        case .blockedMe:
            return appLanguage.text("차단됨", "Blocked me")
        case .error:
            return appLanguage.text("오류", "Error")
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(RBFont.body(14))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            Text(value)
                .font(RBFont.label(15))
                .foregroundStyle(RBColor.textPrimary)
        }
    }
}