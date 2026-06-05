import Foundation
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - Firestore Data Models

struct FirestoreUser: Codable {
    let uid: String
    var username: String?
    var displayName: String
    var email: String
    var level: String
    var totalDistanceKm: Double
    var totalDistance: Double?
    var totalRuns: Int
    var runCount: Int?
    var totalTimeSeconds: Double
    var heightCm: Double?
    var photoURL: String?
    var createdAt: Date
    var updatedAt: Date

    static func from(authUser: User, name: String) -> FirestoreUser {
        FirestoreUser(
            uid: authUser.uid,
            username: FirestorePublicUser.username(from: authUser.uid, email: authUser.email, displayName: name),
            displayName: name,
            email: authUser.email ?? "",
            level: RunnerLevel.starter.rawValue,
            totalDistanceKm: 0,
            totalDistance: 0,
            totalRuns: 0,
            runCount: 0,
            totalTimeSeconds: 0,
            heightCm: nil,
            photoURL: authUser.photoURL?.absoluteString,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    var publicProfile: FirestorePublicUser {
        FirestorePublicUser(from: self)
    }

    static func contactEmailHash(for email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct FirestorePublicUser: Codable {
    let uid: String
    var username: String?
    var usernameLower: String?
    var displayName: String
    var displayNameLower: String?
    var searchId: String?
    var level: String
    var totalDistanceKm: Double
    var totalDistance: Double?
    var totalRuns: Int
    var runCount: Int?
    var photoURL: String?
    var contactEmailHash: String?
    var updatedAt: Date

    var resolvedUsername: String {
        username ?? searchId ?? Self.username(from: uid, displayName: displayName)
    }

    var resolvedSearchId: String {
        searchId ?? usernameLower ?? Self.normalizedSearchText(resolvedUsername)
    }

    var resolvedTotalDistanceKm: Double {
        totalDistance ?? totalDistanceKm
    }

    var resolvedTotalRuns: Int {
        runCount ?? totalRuns
    }

    static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func searchId(from uid: String) -> String {
        let normalized = normalizedSearchText(uid)
        return String(normalized.prefix(10))
    }

    static func username(from uid: String, email: String? = nil, displayName: String? = nil) -> String {
        let candidates = [
            email?.split(separator: "@").first.map(String.init),
            displayName,
            uid,
        ]

        let suffix = String(normalizedSearchText(uid).prefix(4))

        for candidate in candidates {
            let sanitized = sanitizedUsernameBase(candidate)
            guard !sanitized.isEmpty else { continue }

            let trimmedBase = String(sanitized.prefix(max(3, 12 - suffix.count)))
            return normalizedSearchText(trimmedBase + suffix)
        }

        return normalizedSearchText("runner" + suffix)
    }

    private static func sanitizedUsernameBase(_ value: String?) -> String {
        guard let value else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
    }

    init(from user: FirestoreUser) {
        uid = user.uid
        let resolvedUsername = user.username ?? Self.username(from: user.uid, email: user.email, displayName: user.displayName)
        username = resolvedUsername
        usernameLower = Self.normalizedSearchText(resolvedUsername)
        displayName = user.displayName
        displayNameLower = Self.normalizedSearchText(user.displayName)
        searchId = usernameLower
        level = user.level
        totalDistanceKm = user.totalDistanceKm
        totalDistance = user.totalDistance ?? user.totalDistanceKm
        totalRuns = user.totalRuns
        runCount = user.runCount ?? user.totalRuns
        photoURL = user.photoURL
        contactEmailHash = FirestoreUser.contactEmailHash(for: user.email)
        updatedAt = user.updatedAt
    }
}

enum FriendshipServiceError: LocalizedError {
    case loginRequired
    case unavailable
    case cannotFriendYourself
    case userNotFound
    case blocked
    case blockedByUser
    case alreadyFriends
    case outgoingPending
    case incomingPending
    case requestNotFound
    case friendshipNotFound
    case noPermission
    case alreadyHandled

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return AppLanguage.current.text("로그인이 필요해요.", "Sign in is required.")
        case .unavailable:
            return AppLanguage.current.text("친구 기능을 지금 사용할 수 없어요.", "Friend features are unavailable right now.")
        case .cannotFriendYourself:
            return AppLanguage.current.text("자기 자신에게는 친구 요청을 보낼 수 없어요.", "You can't send a friend request to yourself.")
        case .userNotFound:
            return AppLanguage.current.text("상대방을 찾지 못했어요.", "Couldn't find that user.")
        case .blocked:
            return AppLanguage.current.text("차단한 사용자에게는 친구 요청을 보낼 수 없어요.", "You can't send a friend request to a blocked user.")
        case .blockedByUser:
            return AppLanguage.current.text("상대방과는 친구 요청을 주고받을 수 없어요.", "You can't exchange friend requests with that user.")
        case .alreadyFriends:
            return AppLanguage.current.text("이미 친구예요.", "You're already friends.")
        case .outgoingPending:
            return AppLanguage.current.text("이미 보낸 친구 요청이 있어요.", "A friend request is already pending.")
        case .incomingPending:
            return AppLanguage.current.text("상대방이 먼저 친구 요청을 보냈어요.", "That user already sent you a friend request.")
        case .requestNotFound:
            return AppLanguage.current.text("친구 요청을 찾지 못했어요.", "Couldn't find the friend request.")
        case .friendshipNotFound:
            return AppLanguage.current.text("친구 관계를 찾지 못했어요.", "Couldn't find the friendship.")
        case .noPermission:
            return AppLanguage.current.text("이 작업을 수행할 권한이 없어요.", "You don't have permission for this action.")
        case .alreadyHandled:
            return AppLanguage.current.text("이미 처리된 친구 요청이에요.", "This friend request has already been handled.")
        }
    }
}

struct FirestoreRunRecord: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let userId: String
    let startDate: Date
    let endDate: Date
    let totalDistanceMeters: Double
    let elapsedSeconds: Double
    let targetPaceMinutes: Int?
    let targetPaceSeconds: Int?
    let goalType: String?
    let goalDistanceKm: Double?
    let goalTimeMinutes: Int?
    let averageCadenceSpm: Int?
    let averageHeartRateBpm: Int?
    let caloriesEstimatedKcal: Double?
    let heartRateSource: String?
    let cadenceSource: String?
    let elevationSource: String?
    let gpsQuality: String?
    let hasReliableElevation: Bool?
    let hasReliableSpeed: Bool?
    let hasReliableHeartRate: Bool?
    let hasReliableCadence: Bool?
    let routeEncoded: String?
    let createdAt: Date
}

struct FirestoreChallengeProgress: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let userId: String
    let periodType: String
    let periodStart: Date
    let periodEnd: Date
    let targetRunCount: Int
    let targetDistanceKm: Double
    let completedRunCount: Int
    let completedDistanceKm: Double
    let pacedRunCount: Int
    let goalHitCount: Int
    let updatedAt: Date

    var runProgress: Double {
        guard targetRunCount > 0 else { return 0 }
        return min(1.0, Double(completedRunCount) / Double(targetRunCount))
    }

    var distanceProgress: Double {
        guard targetDistanceKm > 0 else { return 0 }
        return min(1.0, completedDistanceKm / targetDistanceKm)
    }

    var combinedProgress: Double {
        (runProgress + distanceProgress) / 2.0
    }

    func title(_ appLanguage: AppLanguage = .current) -> String {
        switch periodType {
        case "weekly":
            return appLanguage.text("주간 챌린지", "Weekly Challenge")
        default:
            return appLanguage.text("월간 챌린지", "Monthly Challenge")
        }
    }

    func periodLabel(_ appLanguage: AppLanguage = .current) -> String {
        let calendar = Calendar.current
        switch periodType {
        case "weekly":
            let startMonth = calendar.component(.month, from: periodStart)
            let startDay = calendar.component(.day, from: periodStart)
            let endDate = calendar.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
            let endMonth = calendar.component(.month, from: endDate)
            let endDay = calendar.component(.day, from: endDate)
            if appLanguage.isEnglish {
                return String(format: "%d/%d - %d/%d", startMonth, startDay, endMonth, endDay)
            }
            return "\(startMonth)월 \(startDay)일 - \(endMonth)월 \(endDay)일"
        default:
            let month = calendar.component(.month, from: periodStart)
            let year = calendar.component(.year, from: periodStart)
            return appLanguage.isEnglish ? "\(year).\(month)" : "\(year)년 \(month)월"
        }
    }

    static func weeklySnapshot(
        userId: String,
        records: [RunRecord],
        monthlyGoal: MonthlyGoal,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FirestoreChallengeProgress {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 24 * 60 * 60)
        let weeklyRecords = validRecords(in: weekInterval, from: records)
        let targetRunCount = max(3, Int(ceil(Double(monthlyGoal.targetRunCount) / 4.0)))
        let rawDistanceTarget = monthlyGoal.targetDistanceKm / 4.0
        let targetDistanceKm = max(10.0, (rawDistanceTarget * 10).rounded() / 10)

        return FirestoreChallengeProgress(
            id: challengeId(type: "weekly", date: weekInterval.start, calendar: calendar),
            userId: userId,
            periodType: "weekly",
            periodStart: weekInterval.start,
            periodEnd: weekInterval.end,
            targetRunCount: targetRunCount,
            targetDistanceKm: targetDistanceKm,
            completedRunCount: weeklyRecords.count,
            completedDistanceKm: weeklyRecords.reduce(0) { $0 + $1.distanceKm },
            pacedRunCount: weeklyRecords.filter { $0.targetPace != nil }.count,
            goalHitCount: weeklyRecords.filter(didHitGoal).count,
            updatedAt: now
        )
    }

    static func monthlySnapshot(
        userId: String,
        records: [RunRecord],
        monthlyGoal: MonthlyGoal,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FirestoreChallengeProgress {
        let monthInterval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 30 * 24 * 60 * 60)
        let monthlyRecords = validRecords(in: monthInterval, from: records)

        return FirestoreChallengeProgress(
            id: challengeId(type: "monthly", date: monthInterval.start, calendar: calendar),
            userId: userId,
            periodType: "monthly",
            periodStart: monthInterval.start,
            periodEnd: monthInterval.end,
            targetRunCount: monthlyGoal.targetRunCount,
            targetDistanceKm: monthlyGoal.targetDistanceKm,
            completedRunCount: monthlyRecords.count,
            completedDistanceKm: monthlyRecords.reduce(0) { $0 + $1.distanceKm },
            pacedRunCount: monthlyRecords.filter { $0.targetPace != nil }.count,
            goalHitCount: monthlyRecords.filter(didHitGoal).count,
            updatedAt: now
        )
    }

    private static func challengeId(type: String, date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        switch type {
        case "weekly":
            let week = calendar.component(.weekOfYear, from: date)
            return "weekly-\(year)-\(week)"
        default:
            let month = calendar.component(.month, from: date)
            return "monthly-\(year)-\(month)"
        }
    }

    private static func validRecords(in interval: DateInterval, from records: [RunRecord]) -> [RunRecord] {
        records.filter {
            $0.totalDistanceMeters > 100 &&
            $0.startDate >= interval.start &&
            $0.startDate < interval.end
        }
    }

    private static func didHitGoal(_ record: RunRecord) -> Bool {
        if let runGoal = record.runGoal {
            switch runGoal.type {
            case .distance:
                return record.distanceKm >= (runGoal.targetDistanceKm ?? .greatestFiniteMagnitude)
            case .time:
                return record.elapsedSeconds >= Double((runGoal.targetTimeMinutes ?? 0) * 60)
            case .combined:
                let hitDistance = record.distanceKm >= (runGoal.targetDistanceKm ?? .greatestFiniteMagnitude)
                let hitTime = record.elapsedSeconds >= Double((runGoal.targetTimeMinutes ?? 0) * 60)
                return hitDistance || hitTime
            case .none:
                break
            }
        }

        if let delta = record.goalDeltaSeconds {
            return delta <= 0
        }

        return false
    }
}

struct FirestoreMatePost: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let authorId: String
    let authorName: String
    let authorLevel: String
    let title: String
    let location: String
    let latitude: Double
    let longitude: Double
    let date: String
    let time: String
    let targetPace: String
    let targetDistance: String
    var currentMembers: Int
    let maxMembers: Int
    let description: String
    var joinedUserIds: [String]
    let createdAt: Date
}

struct FirestoreFeedPost: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let authorId: String
    let authorName: String
    let authorLevel: String
    let headline: String?
    let content: String
    let runId: String?
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
    let selectedMetricKeys: [String]?
    let photoURL: String?
    var likedUserIds: [String]
    var comments: [FirestoreComment]
    let type: String
    let createdAt: Date
}

struct FirestoreComment: Codable, Identifiable {
    var id: String
    let authorId: String
    let authorName: String
    let authorLevel: String
    let content: String
    let createdAt: Date
}

struct FirestoreFriendRequest: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let requestId: String?
    let fromUserId: String?
    let toUserId: String?
    let senderId: String?
    let receiverId: String?
    let status: String
    let source: String
    let createdAt: Date
    let updatedAt: Date?
    let respondedAt: Date?

    var resolvedSenderId: String {
        senderId ?? fromUserId ?? ""
    }

    var resolvedReceiverId: String {
        receiverId ?? toUserId ?? ""
    }

    var documentId: String {
        docId ?? id
    }

    func normalized(documentId: String) -> FirestoreFriendRequest {
        var normalized = self
        if normalized.id.isEmpty {
            normalized.id = documentId
        }
        return normalized
    }
}

struct FirestoreFriendship: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    var friendshipId: String
    let users: [String]
    let status: String?
    let createdAt: Date
    let updatedAt: Date?
    let removedBy: String?
    let removedAt: Date?

    var documentId: String {
        docId ?? id
    }

    var isActive: Bool {
        (status ?? "active") == "active"
    }

    func normalized(documentId: String) -> FirestoreFriendship {
        var normalized = self
        if normalized.id.isEmpty {
            normalized.id = documentId
        }
        if normalized.friendshipId.isEmpty {
            normalized.friendshipId = documentId
        }
        return normalized
    }
}

struct FirestoreFollow: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let followerId: String
    let followingId: String
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date?

    var documentId: String {
        docId ?? id
    }

    func normalized(documentId: String) -> FirestoreFollow {
        var normalized = self
        if normalized.id.isEmpty {
            normalized.id = documentId
        }
        return normalized
    }
}

struct FirestoreBlock: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let blockerId: String
    let blockedId: String
    let createdAt: Date

    var documentId: String {
        docId ?? id
    }

    func normalized(documentId: String) -> FirestoreBlock {
        var normalized = self
        if normalized.id.isEmpty {
            normalized.id = documentId
        }
        return normalized
    }
}

struct FirestoreReport: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let reporterId: String
    let targetId: String          // postId 또는 userId
    let targetType: String        // "feedPost" | "matePost" | "user"
    let reason: String
    let createdAt: Date
}

struct FirestoreBlockedUser: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let blockedUid: String
    let createdAt: Date
}

// MARK: - Backend Service

@MainActor
final class BackendService: ObservableObject {

    private struct FeedInteractionUpdate {
        let reference: DocumentReference
        let likedUserIds: [String]
        let comments: [[String: Any]]
    }

    private var _db: Firestore?
    private var _storage: Storage?

    private var db: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        if _db == nil { _db = Firestore.firestore() }
        return _db
    }
    private var storage: Storage? {
        guard FirebaseApp.app() != nil else { return nil }
        if _storage == nil { _storage = Storage.storage() }
        return _storage
    }

    @Published var currentUser: FirestoreUser?
    @Published var currentWeeklyChallenge: FirestoreChallengeProgress?
    @Published var currentMonthlyChallenge: FirestoreChallengeProgress?
    @Published var isLoading = false
    @Published var error: String?

    private var listeners: [ListenerRegistration] = []

    // MARK: - Collections

    private var usersCollection: CollectionReference? { db?.collection("users") }
    private var publicUsersCollection: CollectionReference? { db?.collection("publicUsers") }
    private var runsCollection: CollectionReference? { db?.collection("runs") }
    private var matePostsCollection: CollectionReference? { db?.collection("matePosts") }
    private var feedPostsCollection: CollectionReference? { db?.collection("feedPosts") }
    private var reportsCollection: CollectionReference? { db?.collection("reports") }
    private var friendRequestsCollection: CollectionReference? { db?.collection("friendRequests") }
    private var friendshipsCollection: CollectionReference? { db?.collection("friendships") }
    private var followsCollection: CollectionReference? { db?.collection("follows") }
    private var blocksCollection: CollectionReference? { db?.collection("blocks") }

    private func friendsCollection(for userId: String) -> CollectionReference? {
        usersCollection?.document(userId).collection("friends")
    }

    private func blockedUsersCollection(for userId: String) -> CollectionReference? {
        usersCollection?.document(userId).collection("blockedUsers")
    }

    private func challengeProgressCollection(for userId: String) -> CollectionReference? {
        usersCollection?.document(userId).collection("challengeProgress")
    }

    // MARK: - Auth

    func signInWithFirebase(
        idToken: String,
        nonce: String,
        fullName: PersonNameComponents? = nil,
        fallbackDisplayName: String = "러너"
    ) async throws {
        guard FirebaseApp.app() != nil else {
            self.error = "Firebase가 설정되지 않았습니다."
            return
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        let result = try await Auth.auth().signIn(with: credential)
        let resolvedName: String = {
            let appleName = [fullName?.familyName, fullName?.givenName]
                .compactMap { $0 }
                .joined()
            return appleName.isEmpty ? (result.user.displayName ?? fallbackDisplayName) : appleName
        }()
        await loadOrCreateUser(authUser: result.user, displayName: resolvedName)
    }

    func signInWithGoogle(
        idToken: String,
        accessToken: String,
        fallbackDisplayName: String = "러너"
    ) async throws {
        guard FirebaseApp.app() != nil else {
            self.error = "Firebase가 설정되지 않았습니다."
            return
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        let result = try await Auth.auth().signIn(with: credential)
        let resolvedName = result.user.displayName
            ?? result.user.email?.split(separator: "@").first.map(String.init)
            ?? fallbackDisplayName
        await loadOrCreateUser(authUser: result.user, displayName: resolvedName)
    }

    func signOut() throws {
        guard FirebaseApp.app() != nil else { return }
        try Auth.auth().signOut()
        currentUser = nil
        removeAllListeners()
    }

    var isSignedIn: Bool {
        guard FirebaseApp.app() != nil else { return false }
        return Auth.auth().currentUser != nil
    }

    var userId: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }

    // MARK: - User Profile

    func loadOrCreateUser(authUser: User, displayName: String) async {
        guard let usersCollection = usersCollection else { return }
        do {
            let doc = try await usersCollection.document(authUser.uid).getDocument()
            if doc.exists {
                var user = try doc.data(as: FirestoreUser.self)
                var updates: [String: Any] = [:]

                if user.username?.isEmpty ?? true {
                    let username = FirestorePublicUser.username(from: authUser.uid, email: authUser.email, displayName: user.displayName)
                    user.username = username
                    updates["username"] = username
                }
                if user.totalDistance == nil {
                    user.totalDistance = user.totalDistanceKm
                    updates["totalDistance"] = user.totalDistanceKm
                }
                if user.runCount == nil {
                    user.runCount = user.totalRuns
                    updates["runCount"] = user.totalRuns
                }
                if user.photoURL == nil, let authPhotoURL = authUser.photoURL?.absoluteString {
                    user.photoURL = authPhotoURL
                    updates["photoURL"] = authPhotoURL
                }

                if !updates.isEmpty {
                    updates["updatedAt"] = FieldValue.serverTimestamp()
                    try await usersCollection.document(authUser.uid).setData(updates, merge: true)
                }

                currentUser = user
                if let publicUsersCollection {
                    try await publicUsersCollection.document(authUser.uid).setData(from: user.publicProfile, merge: true)
                }
            } else {
                let newUser = FirestoreUser.from(authUser: authUser, name: displayName)
                try usersCollection.document(authUser.uid).setData(from: newUser)
                if let publicUsersCollection {
                    try await publicUsersCollection.document(authUser.uid).setData(from: newUser.publicProfile)
                }
                currentUser = newUser
            }
        } catch {
            self.error = "프로필 로드 실패: \(error.localizedDescription)"
        }
    }

    func updateUserProfile(_ updates: [String: Any]) async {
        guard let uid = userId, let usersCollection = usersCollection else { return }
        var merged = updates
        if let username = updates["username"] as? String {
            merged["username"] = FirestorePublicUser.normalizedSearchText(username)
        }
        if let totalDistanceKm = updates["totalDistanceKm"] as? Double {
            merged["totalDistance"] = totalDistanceKm
        }
        if let totalRuns = updates["totalRuns"] as? Int {
            merged["runCount"] = totalRuns
        }
        merged["updatedAt"] = FieldValue.serverTimestamp()
        do {
            try await usersCollection.document(uid).updateData(merged)
            if var currentUser {
                if let username = merged["username"] as? String {
                    currentUser.username = username
                }
                if let displayName = updates["displayName"] as? String {
                    currentUser.displayName = displayName
                }
                if let email = updates["email"] as? String {
                    currentUser.email = email
                }
                if let level = updates["level"] as? String {
                    currentUser.level = level
                }
                if let totalDistanceKm = updates["totalDistanceKm"] as? Double {
                    currentUser.totalDistanceKm = totalDistanceKm
                    currentUser.totalDistance = totalDistanceKm
                }
                if let totalRuns = updates["totalRuns"] as? Int {
                    currentUser.totalRuns = totalRuns
                    currentUser.runCount = totalRuns
                }
                if let totalTimeSeconds = updates["totalTimeSeconds"] as? Double {
                    currentUser.totalTimeSeconds = totalTimeSeconds
                }
                if let heightCm = updates["heightCm"] as? Double {
                    currentUser.heightCm = heightCm
                }
                if let photoURL = updates["photoURL"] as? String {
                    currentUser.photoURL = photoURL
                }
                currentUser.updatedAt = Date()
                if let publicUsersCollection {
                    try await publicUsersCollection.document(uid).setData(from: currentUser.publicProfile, merge: true)
                }
                self.currentUser = currentUser
            }
        } catch {
            self.error = "프로필 업데이트 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Profile Photo Upload

    func uploadProfilePhoto(_ image: UIImage) async throws -> String {
        guard let uid = userId else { throw makeError("로그인이 필요합니다.") }
        guard let storage = storage else { throw makeError("Storage가 설정되지 않았습니다.") }

        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw makeError("이미지 변환에 실패했습니다.")
        }

        let ref = storage.reference().child("profile_photos/\(uid)/avatar.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        let urlString = downloadURL.absoluteString

        await updateUserProfile(["photoURL": urlString])
        return urlString
    }

    func fetchUsers(limit: Int = 100) async throws -> [FirestorePublicUser] {
        guard let publicUsersCollection = publicUsersCollection else { return [] }
        let snapshot = try await publicUsersCollection
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestorePublicUser.self) }
    }

    func searchUsers(query: String, limit: Int = 20) async throws -> [FirestorePublicUser] {
        guard let publicUsersCollection = publicUsersCollection else { return [] }

        let normalized = FirestorePublicUser.normalizedSearchText(
            query.replacingOccurrences(of: "@", with: "")
        )
        guard !normalized.isEmpty else { return [] }

        let searchPrefix = String(normalized.prefix(24))

        async let legacyIdTask = publicUsersCollection
            .whereField("searchId", isGreaterThanOrEqualTo: searchPrefix)
            .whereField("searchId", isLessThanOrEqualTo: searchPrefix + "\u{f8ff}")
            .order(by: "searchId")
            .limit(to: limit)
            .getDocuments()

        async let usernameTask = publicUsersCollection
            .whereField("usernameLower", isGreaterThanOrEqualTo: searchPrefix)
            .whereField("usernameLower", isLessThanOrEqualTo: searchPrefix + "\u{f8ff}")
            .order(by: "usernameLower")
            .limit(to: limit)
            .getDocuments()

        async let nameTask = publicUsersCollection
            .whereField("displayNameLower", isGreaterThanOrEqualTo: searchPrefix)
            .whereField("displayNameLower", isLessThanOrEqualTo: searchPrefix + "\u{f8ff}")
            .order(by: "displayNameLower")
            .limit(to: limit)
            .getDocuments()

        let snapshots = try await [legacyIdTask, usernameTask, nameTask]
        var usersById: [String: FirestorePublicUser] = [:]

        for snapshot in snapshots {
            for document in snapshot.documents {
                guard let user = try? document.data(as: FirestorePublicUser.self) else { continue }
                usersById[user.uid] = user
            }
        }

        return usersById.values.sorted { lhs, rhs in
            let lhsId = lhs.usernameLower ?? lhs.searchId ?? FirestorePublicUser.searchId(from: lhs.uid)
            let rhsId = rhs.usernameLower ?? rhs.searchId ?? FirestorePublicUser.searchId(from: rhs.uid)

            let lhsMatchesId = lhsId.hasPrefix(searchPrefix)
            let rhsMatchesId = rhsId.hasPrefix(searchPrefix)
            if lhsMatchesId != rhsMatchesId {
                return lhsMatchesId && !rhsMatchesId
            }

            let lhsName = lhs.displayNameLower ?? FirestorePublicUser.normalizedSearchText(lhs.displayName)
            let rhsName = rhs.displayNameLower ?? FirestorePublicUser.normalizedSearchText(rhs.displayName)
            let lhsMatchesName = lhsName.hasPrefix(searchPrefix)
            let rhsMatchesName = rhsName.hasPrefix(searchPrefix)
            if lhsMatchesName != rhsMatchesName {
                return lhsMatchesName && !rhsMatchesName
            }

            if lhs.resolvedTotalDistanceKm == rhs.resolvedTotalDistanceKm {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.resolvedTotalDistanceKm > rhs.resolvedTotalDistanceKm
        }
    }

    func fetchPublicUser(uid: String) async throws -> FirestorePublicUser? {
        guard let publicUsersCollection else { return nil }
        let snapshot = try await publicUsersCollection.document(uid).getDocument()
        return try? snapshot.data(as: FirestorePublicUser.self)
    }

    func deleteCurrentAccount() async throws {
        guard FirebaseApp.app() != nil else {
            throw makeError("Firebase가 설정되지 않았습니다.")
        }
        guard let authUser = Auth.auth().currentUser else {
            throw makeError("삭제할 로그인 계정을 찾지 못했습니다.")
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        let uid = authUser.uid

        do {
            try await detachUserFromCommunity(uid: uid)
            try await deleteUserOwnedDocuments(uid: uid)
            try await deleteFriendLinks(uid: uid)
            try await deleteStorageFolder(path: "feed_photos/\(uid)")
            try await deleteStorageFolder(path: "profile_photos/\(uid)")

            if let usersCollection {
                try await usersCollection.document(uid).delete()
            }
            if let publicUsersCollection {
                try await publicUsersCollection.document(uid).delete()
            }

            try await authUser.delete()
            currentUser = nil
            removeAllListeners()
        } catch {
            self.error = presentableAccountDeletionError(error)
            throw error
        }
    }

    // MARK: - Friends

    func fetchFriendRequests() async throws -> [FirestoreFriendRequest] {
        guard let uid = userId, let friendRequestsCollection else { return [] }

        async let incomingTask = queryFriendRequests(field: "receiverId", value: uid)
        async let outgoingTask = queryFriendRequests(field: "senderId", value: uid)
        async let legacyIncomingTask = queryFriendRequests(field: "toUserId", value: uid)
        async let legacyOutgoingTask = queryFriendRequests(field: "fromUserId", value: uid)

        let snapshots = try await [incomingTask, outgoingTask, legacyIncomingTask, legacyOutgoingTask]
        var requestsById: [String: FirestoreFriendRequest] = [:]

        for snapshot in snapshots {
            for document in snapshot.documents {
                if let request = try? document.data(as: FirestoreFriendRequest.self).normalized(documentId: document.documentID) {
                    requestsById[document.documentID] = request
                }
            }
        }

        return requestsById.values.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchFriendships() async throws -> [FirestoreFriendship] {
        guard let uid = userId, let friendshipsCollection else { return [] }

        let snapshot = try await friendshipsCollection
            .whereField("users", arrayContains: uid)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: FirestoreFriendship.self).normalized(documentId: $0.documentID)
        }
    }

    func fetchFollowStates() async throws -> [FirestoreFollow] {
        guard let uid = userId, let followsCollection else { return [] }

        let snapshot = try await followsCollection
            .whereField("followerId", isEqualTo: uid)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: FirestoreFollow.self).normalized(documentId: $0.documentID)
        }
    }

    func fetchBlocks() async throws -> [FirestoreBlock] {
        guard let uid = userId else { return [] }

        var blocksById: [String: FirestoreBlock] = [:]

        if let blocksCollection {
            async let blockedByMeTask = blocksCollection.whereField("blockerId", isEqualTo: uid).getDocuments()
            async let blockedMeTask = blocksCollection.whereField("blockedId", isEqualTo: uid).getDocuments()

            let snapshots = try await [blockedByMeTask, blockedMeTask]
            for snapshot in snapshots {
                for document in snapshot.documents {
                    if let block = try? document.data(as: FirestoreBlock.self).normalized(documentId: document.documentID) {
                        blocksById[document.documentID] = block
                    }
                }
            }
        }

        if let legacyCollection = blockedUsersCollection(for: uid) {
            let snapshot = try await legacyCollection.getDocuments()
            for document in snapshot.documents {
                guard let legacy = try? document.data(as: FirestoreBlockedUser.self) else { continue }
                let blockId = blockKey(blockerId: uid, blockedId: legacy.blockedUid)
                blocksById[blockId] = FirestoreBlock(
                    docId: blockId,
                    id: blockId,
                    blockerId: uid,
                    blockedId: legacy.blockedUid,
                    createdAt: legacy.createdAt
                )
            }
        }

        return Array(blocksById.values)
    }

    func sendFriendRequest(toUserId: String, source: String = "manual") async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard uid != toUserId else {
            throw FriendshipServiceError.cannotFriendYourself
        }
        guard let friendRequestsCollection else {
            throw FriendshipServiceError.unavailable
        }

        let requestId = friendRequestDocumentId(senderId: uid, receiverId: toUserId)
        let friendshipId = friendshipKey(uid, toUserId)

        do {
            if try await isUserBlocked(blockerId: uid, blockedId: toUserId) {
                throw FriendshipServiceError.blocked
            }
            if try await isUserBlocked(blockerId: toUserId, blockedId: uid) {
                throw FriendshipServiceError.blockedByUser
            }

            guard try await publicUserExists(uid: toUserId) else {
                throw FriendshipServiceError.userNotFound
            }

            if let friendshipsCollection {
                let friendshipSnapshot = try await friendshipsCollection.document(friendshipId).getDocument()
                if let friendship = try? friendshipSnapshot.data(as: FirestoreFriendship.self).normalized(documentId: friendshipSnapshot.documentID),
                   friendship.isActive {
                    throw FriendshipServiceError.alreadyFriends
                }
            }

            let directRequestId = requestId
            let reverseRequestId = friendRequestDocumentId(senderId: toUserId, receiverId: uid)
            let legacyRequestId = friendshipKey(uid, toUserId)

            for existingRequestId in Set([directRequestId, reverseRequestId, legacyRequestId]) {
                let snapshot = try await friendRequestsCollection.document(existingRequestId).getDocument()
                guard let existing = try? snapshot.data(as: FirestoreFriendRequest.self).normalized(documentId: snapshot.documentID) else {
                    continue
                }

                switch existing.status {
                case "pending":
                    if existing.resolvedSenderId == uid {
                        throw FriendshipServiceError.outgoingPending
                    }
                    throw FriendshipServiceError.incomingPending
                case "accepted":
                    throw FriendshipServiceError.alreadyFriends
                default:
                    continue
                }
            }

            let now = Date()
            let requestData: [String: Any] = [
                "id": requestId,
                "requestId": requestId,
                "fromUserId": uid,
                "toUserId": toUserId,
                "senderId": uid,
                "receiverId": toUserId,
                "status": "pending",
                "source": source,
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
                "respondedAt": NSNull(),
            ]

            if let db, let followsCollection {
                let requestRef = friendRequestsCollection.document(requestId)
                let followId = followKey(followerId: uid, followingId: toUserId)
                let followRef = followsCollection.document(followId)
                let batch = db.batch()

                batch.setData(requestData, forDocument: requestRef)
                batch.setData([
                    "id": followId,
                    "followerId": uid,
                    "followingId": toUserId,
                    "isActive": true,
                    "createdAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: now),
                ], forDocument: followRef, merge: true)

                try await batch.commit()
            } else {
                try await friendRequestsCollection.document(requestId).setData(requestData)
            }
        } catch let error as FriendshipServiceError {
            throw error
        } catch {
            logFriendshipFailure(
                operation: "sendFriendRequest",
                uid: uid,
                targetUid: toUserId,
                path: "friendRequests/\(requestId)",
                error: error
            )
            throw error
        }
    }

    func cancelFriendRequest(requestId: String) async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard let friendRequestsCollection else {
            throw FriendshipServiceError.unavailable
        }

        let ref = friendRequestsCollection.document(requestId)

        do {
            let snapshot = try await ref.getDocument()
            guard let request = try? snapshot.data(as: FirestoreFriendRequest.self).normalized(documentId: snapshot.documentID) else {
                throw FriendshipServiceError.requestNotFound
            }
            guard request.resolvedSenderId == uid else {
                throw FriendshipServiceError.noPermission
            }
            guard request.status == "pending" else {
                throw FriendshipServiceError.alreadyHandled
            }

            try await ref.updateData([
                "status": "canceled",
                "updatedAt": Timestamp(date: Date()),
            ])
        } catch let error as FriendshipServiceError {
            throw error
        } catch {
            logFriendshipFailure(
                operation: "cancelFriendRequest",
                uid: uid,
                path: "friendRequests/\(requestId)",
                error: error
            )
            throw error
        }
    }

    func respondToFriendRequest(requestId: String, accept: Bool) async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard let friendRequestsCollection else {
            throw FriendshipServiceError.unavailable
        }

        let ref = friendRequestsCollection.document(requestId)

        do {
            let snapshot = try await ref.getDocument()
            guard let request = try? snapshot.data(as: FirestoreFriendRequest.self).normalized(documentId: snapshot.documentID) else {
                throw FriendshipServiceError.requestNotFound
            }
            guard request.resolvedReceiverId == uid else {
                throw FriendshipServiceError.noPermission
            }
            guard request.status == "pending" else {
                throw FriendshipServiceError.alreadyHandled
            }

            let now = Date()
                if accept,
                    let db,
                    let friendshipsCollection,
                    let followsCollection {
                let friendshipId = friendshipKey(request.resolvedSenderId, request.resolvedReceiverId)
                let friendshipRef = friendshipsCollection.document(friendshipId)
                let receiverFollowRef = followsCollection.document(followKey(followerId: request.resolvedReceiverId, followingId: request.resolvedSenderId))
                let batch = db.batch()

                batch.updateData([
                    "status": "accepted",
                    "updatedAt": Timestamp(date: now),
                    "respondedAt": Timestamp(date: now),
                ], forDocument: ref)
                batch.setData([
                    "id": friendshipId,
                    "friendshipId": friendshipId,
                    "users": [request.resolvedSenderId, request.resolvedReceiverId].sorted(),
                    "status": "active",
                    "createdAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: now),
                    "removedBy": FieldValue.delete(),
                    "removedAt": FieldValue.delete(),
                ], forDocument: friendshipRef, merge: true)
                batch.setData([
                    "id": receiverFollowRef.documentID,
                    "followerId": request.resolvedReceiverId,
                    "followingId": request.resolvedSenderId,
                    "isActive": true,
                    "createdAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: now),
                ], forDocument: receiverFollowRef, merge: true)

                try await batch.commit()
            } else {
                try await ref.updateData([
                    "status": accept ? "accepted" : "rejected",
                    "updatedAt": Timestamp(date: now),
                    "respondedAt": Timestamp(date: now),
                ])
            }
        } catch let error as FriendshipServiceError {
            throw error
        } catch {
            logFriendshipFailure(
                operation: accept ? "acceptFriendRequest" : "rejectFriendRequest",
                uid: uid,
                path: "friendRequests/\(requestId)",
                error: error
            )
            throw error
        }
    }

    func setFollowState(targetUserId: String, isActive: Bool) async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard let followsCollection else {
            throw FriendshipServiceError.unavailable
        }

        let now = Date()
        let followId = followKey(followerId: uid, followingId: targetUserId)
        try await followsCollection.document(followId).setData([
            "id": followId,
            "followerId": uid,
            "followingId": targetUserId,
            "isActive": isActive,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
        ], merge: true)
    }

    func removeFriend(targetUserId: String) async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard let db, let friendshipsCollection else {
            throw FriendshipServiceError.unavailable
        }

        let now = Date()
        let friendshipId = friendshipKey(uid, targetUserId)
        let friendshipRef = friendshipsCollection.document(friendshipId)
        let friendshipSnapshot = try await friendshipRef.getDocument()
        guard let friendship = try? friendshipSnapshot.data(as: FirestoreFriendship.self).normalized(documentId: friendshipSnapshot.documentID),
              friendship.isActive else {
            throw FriendshipServiceError.friendshipNotFound
        }
        guard friendship.users.contains(uid) else {
            throw FriendshipServiceError.noPermission
        }

        let batch = db.batch()
        batch.setData([
            "id": friendshipId,
            "friendshipId": friendshipId,
            "users": friendship.users,
            "status": "removed",
            "updatedAt": Timestamp(date: now),
            "removedBy": uid,
            "removedAt": Timestamp(date: now),
        ], forDocument: friendshipRef, merge: true)

        if let followsCollection {
            let followRef = followsCollection.document(followKey(followerId: uid, followingId: targetUserId))
            batch.setData([
                "id": followRef.documentID,
                "followerId": uid,
                "followingId": targetUserId,
                "isActive": false,
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
            ], forDocument: followRef, merge: true)
        }

        try await batch.commit()
    }

    // MARK: - Run Records

    func saveRunRecord(_ record: FirestoreRunRecord) async throws {
        try await syncRunRecord(record)
    }

    func syncRunRecord(_ record: FirestoreRunRecord) async throws {
        guard let runsCollection = runsCollection, let usersCollection = usersCollection else { return }

        let reference = runsCollection.document(record.id)
        let snapshot = try await reference.getDocument()
        let isNewRecord = !snapshot.exists

        try reference.setData(from: record, merge: true)

        guard isNewRecord, let uid = userId else { return }

        try await usersCollection.document(uid).updateData([
            "totalDistanceKm": FieldValue.increment(record.totalDistanceMeters / 1000.0),
            "totalDistance": FieldValue.increment(record.totalDistanceMeters / 1000.0),
            "totalRuns": FieldValue.increment(Int64(1)),
            "runCount": FieldValue.increment(Int64(1)),
            "totalTimeSeconds": FieldValue.increment(record.elapsedSeconds),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    func syncRunRecords(_ records: [RunRecord]) async {
        guard let uid = userId else { return }

        for record in records where record.totalDistanceMeters > 100 {
            let firestoreRecord = FirestoreRunRecord.from(record: record, userId: uid)
            do {
                try await syncRunRecord(firestoreRecord)
            } catch {
                self.error = "러닝 기록 동기화 실패: \(error.localizedDescription)"
            }
        }
    }

    func fetchRunHistory(limit: Int = 50) async throws -> [FirestoreRunRecord] {
        guard let uid = userId, let runsCollection = runsCollection else { return [] }
        let snapshot = try await runsCollection
            .whereField("userId", isEqualTo: uid)
            .order(by: "startDate", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreRunRecord.self) }
    }

    func syncChallengeProgress(records: [RunRecord], monthlyGoal: MonthlyGoal) async {
        guard let uid = userId, let challengeProgressCollection = challengeProgressCollection(for: uid) else { return }

        let weekly = FirestoreChallengeProgress.weeklySnapshot(
            userId: uid,
            records: records,
            monthlyGoal: monthlyGoal
        )
        let monthly = FirestoreChallengeProgress.monthlySnapshot(
            userId: uid,
            records: records,
            monthlyGoal: monthlyGoal
        )

        do {
            try challengeProgressCollection.document(weekly.id).setData(from: weekly, merge: true)
            try challengeProgressCollection.document(monthly.id).setData(from: monthly, merge: true)
            currentWeeklyChallenge = weekly
            currentMonthlyChallenge = monthly
        } catch {
            self.error = "챌린지 동기화 실패: \(error.localizedDescription)"
        }
    }

    func loadCurrentChallengeProgress(monthlyGoal: MonthlyGoal) async {
        guard let uid = userId, let challengeProgressCollection = challengeProgressCollection(for: uid) else { return }

        let weeklyId = FirestoreChallengeProgress.weeklySnapshot(
            userId: uid,
            records: [],
            monthlyGoal: monthlyGoal
        ).id
        let monthlyId = FirestoreChallengeProgress.monthlySnapshot(
            userId: uid,
            records: [],
            monthlyGoal: monthlyGoal
        ).id

        do {
            async let weeklyDocument = challengeProgressCollection.document(weeklyId).getDocument()
            async let monthlyDocument = challengeProgressCollection.document(monthlyId).getDocument()

            let (weeklySnapshot, monthlySnapshot) = try await (weeklyDocument, monthlyDocument)
            currentWeeklyChallenge = try? weeklySnapshot.data(as: FirestoreChallengeProgress.self)
            currentMonthlyChallenge = try? monthlySnapshot.data(as: FirestoreChallengeProgress.self)
        } catch {
            self.error = "챌린지 로드 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Mate Posts

    func createMatePost(_ post: FirestoreMatePost) async throws {
        guard let matePostsCollection = matePostsCollection else { return }
        try matePostsCollection.document(post.id).setData(from: post)
    }

    func fetchMatePosts(limit: Int = 30) async throws -> [FirestoreMatePost] {
        guard let matePostsCollection = matePostsCollection else { return [] }
        let snapshot = try await matePostsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreMatePost.self) }
    }

    func toggleJoinMatePost(postId: String) async throws {
        guard let uid = userId, let matePostsCollection = matePostsCollection else { return }
        let ref = matePostsCollection.document(postId)
        let doc = try await ref.getDocument()
        guard let post = try? doc.data(as: FirestoreMatePost.self) else { return }

        if post.joinedUserIds.contains(uid) {
            try await ref.updateData([
                "joinedUserIds": FieldValue.arrayRemove([uid]),
                "currentMembers": FieldValue.increment(Int64(-1)),
            ])
        } else if post.currentMembers < post.maxMembers {
            try await ref.updateData([
                "joinedUserIds": FieldValue.arrayUnion([uid]),
                "currentMembers": FieldValue.increment(Int64(1)),
            ])
        }
    }

    // MARK: - Feed Posts

    func createFeedPost(_ post: FirestoreFeedPost) async throws {
        guard let feedPostsCollection = feedPostsCollection else { return }
        try feedPostsCollection.document(post.id).setData(from: post)
    }

    func fetchFeedPosts(limit: Int = 30) async throws -> [FirestoreFeedPost] {
        guard let feedPostsCollection = feedPostsCollection else { return [] }
        let snapshot = try await feedPostsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreFeedPost.self) }
    }

    func toggleLikeFeedPost(postId: String) async throws {
        guard let uid = userId, let feedPostsCollection = feedPostsCollection else { return }
        let ref = feedPostsCollection.document(postId)
        let doc = try await ref.getDocument()
        guard let post = try? doc.data(as: FirestoreFeedPost.self) else { return }

        if post.likedUserIds.contains(uid) {
            try await ref.updateData([
                "likedUserIds": FieldValue.arrayRemove([uid]),
            ])
        } else {
            try await ref.updateData([
                "likedUserIds": FieldValue.arrayUnion([uid]),
            ])
        }
    }

    func addCommentToFeedPost(postId: String, comment: FirestoreComment) async throws {
        guard let feedPostsCollection = feedPostsCollection else { return }
        let ref = feedPostsCollection.document(postId)
        let commentData = try Firestore.Encoder().encode(comment)
        try await ref.updateData([
            "comments": FieldValue.arrayUnion([commentData]),
        ])
    }

    // MARK: - Photo Upload

    func uploadPhoto(data: Data, path: String, contentType: String = "image/jpeg") async throws -> String {
        guard let storage = storage else { throw NSError(domain: "BackendService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"]) }
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Real-time Listeners

    func listenToMatePosts(onChange: @escaping ([FirestoreMatePost]) -> Void) {
        guard let matePostsCollection = matePostsCollection else { return }
        let listener = matePostsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let posts = docs.compactMap { try? $0.data(as: FirestoreMatePost.self) }
                Task { @MainActor in
                    onChange(posts)
                }
            }
        listeners.append(listener)
    }

    func listenToFeedPosts(onChange: @escaping ([FirestoreFeedPost]) -> Void) {
        guard let feedPostsCollection = feedPostsCollection else { return }
        let listener = feedPostsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let posts = docs.compactMap { try? $0.data(as: FirestoreFeedPost.self) }
                Task { @MainActor in
                    onChange(posts)
                }
            }
        listeners.append(listener)
    }

    func removeAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    private func detachUserFromCommunity(uid: String) async throws {
        guard let matePostsCollection, let feedPostsCollection else { return }

        let joinedMateSnapshot = try await matePostsCollection
            .whereField("joinedUserIds", arrayContains: uid)
            .getDocuments()

        let feedSnapshot = try await feedPostsCollection.getDocuments()
        let commentEncoder = Firestore.Encoder()
        var feedUpdates: [FeedInteractionUpdate] = []

        for document in feedSnapshot.documents {
            guard let post = try? document.data(as: FirestoreFeedPost.self), post.authorId != uid else {
                continue
            }

            let nextLikedUserIds = post.likedUserIds.filter { $0 != uid }
            let nextComments = post.comments.filter { $0.authorId != uid }

            guard nextLikedUserIds.count != post.likedUserIds.count || nextComments.count != post.comments.count else {
                continue
            }

            let encodedComments = try nextComments.map { try commentEncoder.encode($0) }
            feedUpdates.append(
                FeedInteractionUpdate(
                    reference: document.reference,
                    likedUserIds: nextLikedUserIds,
                    comments: encodedComments
                )
            )
        }

        if !joinedMateSnapshot.documents.isEmpty {
            try await commitDocumentChunks(joinedMateSnapshot.documents, chunkSize: 200) { batch, document in
                guard let post = try? document.data(as: FirestoreMatePost.self), post.authorId != uid else {
                    return
                }

                batch.updateData([
                    "joinedUserIds": FieldValue.arrayRemove([uid]),
                    "currentMembers": FieldValue.increment(Int64(-1)),
                ], forDocument: document.reference)
            }
        }

        if !feedUpdates.isEmpty {
            try await commitChunks(feedUpdates, chunkSize: 120) { batch, update in
                batch.updateData([
                    "likedUserIds": update.likedUserIds,
                    "comments": update.comments,
                ], forDocument: update.reference)
            }
        }
    }

    private func deleteUserOwnedDocuments(uid: String) async throws {
        var references: [DocumentReference] = []

        if let runsCollection {
            let snapshot = try await runsCollection.whereField("userId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: snapshot.documents.map(\.reference))
        }

        if let matePostsCollection {
            let snapshot = try await matePostsCollection.whereField("authorId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: snapshot.documents.map(\.reference))
        }

        if let feedPostsCollection {
            let snapshot = try await feedPostsCollection.whereField("authorId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: snapshot.documents.map(\.reference))
        }

        if let friendRequestsCollection {
            let incomingSnapshot = try await friendRequestsCollection.whereField("receiverId", isEqualTo: uid).getDocuments()
            let outgoingSnapshot = try await friendRequestsCollection.whereField("senderId", isEqualTo: uid).getDocuments()
            let legacyIncomingSnapshot = try await friendRequestsCollection.whereField("toUserId", isEqualTo: uid).getDocuments()
            let legacyOutgoingSnapshot = try await friendRequestsCollection.whereField("fromUserId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: incomingSnapshot.documents.map(\.reference))
            references.append(contentsOf: outgoingSnapshot.documents.map(\.reference))
            references.append(contentsOf: legacyIncomingSnapshot.documents.map(\.reference))
            references.append(contentsOf: legacyOutgoingSnapshot.documents.map(\.reference))
        }

        if let followsCollection {
            let followerSnapshot = try await followsCollection.whereField("followerId", isEqualTo: uid).getDocuments()
            let followingSnapshot = try await followsCollection.whereField("followingId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: followerSnapshot.documents.map(\.reference))
            references.append(contentsOf: followingSnapshot.documents.map(\.reference))
        }

        if let blocksCollection {
            let blockerSnapshot = try await blocksCollection.whereField("blockerId", isEqualTo: uid).getDocuments()
            let blockedSnapshot = try await blocksCollection.whereField("blockedId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: blockerSnapshot.documents.map(\.reference))
            references.append(contentsOf: blockedSnapshot.documents.map(\.reference))
        }

        try await deleteDocuments(references)
    }

    private func deleteFriendLinks(uid: String) async throws {
        var references: [DocumentReference] = []

        if let usersCollection {
            let friendsSnapshot = try await usersCollection.document(uid).collection("friends").getDocuments()
            references.append(contentsOf: friendsSnapshot.documents.map(\.reference))
            references.append(contentsOf: friendsSnapshot.documents.map {
                usersCollection.document($0.documentID).collection("friends").document(uid)
            })
        }

        if let friendshipsCollection {
            let friendshipsSnapshot = try await friendshipsCollection.whereField("users", arrayContains: uid).getDocuments()
            references.append(contentsOf: friendshipsSnapshot.documents.map(\.reference))
        }

        if let followsCollection {
            let followerSnapshot = try await followsCollection.whereField("followerId", isEqualTo: uid).getDocuments()
            let followingSnapshot = try await followsCollection.whereField("followingId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: followerSnapshot.documents.map(\.reference))
            references.append(contentsOf: followingSnapshot.documents.map(\.reference))
        }

        try await deleteDocuments(references)
    }

    private func deleteDocuments(_ references: [DocumentReference]) async throws {
        guard !references.isEmpty else { return }
        let uniqueReferences = Dictionary(grouping: references, by: \.path).compactMap { $0.value.first }
        try await commitChunks(uniqueReferences, chunkSize: 250) { batch, reference in
            batch.deleteDocument(reference)
        }
    }

    private func commitDocumentChunks(
        _ documents: [QueryDocumentSnapshot],
        chunkSize: Int,
        operation: (WriteBatch, QueryDocumentSnapshot) throws -> Void
    ) async throws {
        try await commitChunks(documents, chunkSize: chunkSize, operation)
    }

    private func commitChunks<T>(
        _ items: [T],
        chunkSize: Int,
        _ operation: (WriteBatch, T) throws -> Void
    ) async throws {
        guard let db, !items.isEmpty else { return }

        var startIndex = 0
        while startIndex < items.count {
            let endIndex = min(startIndex + chunkSize, items.count)
            let batch = db.batch()
            for item in items[startIndex..<endIndex] {
                try operation(batch, item)
            }
            try await batch.commit()
            startIndex = endIndex
        }
    }

    private func deleteStorageFolder(path: String) async throws {
        guard let storage else { return }
        try await deleteStorageTree(reference: storage.reference().child(path))
    }

    private func deleteStorageTree(reference: StorageReference) async throws {
        let result = try await listAll(reference: reference)
        for item in result.items {
            try await deleteStorageItem(reference: item)
        }
        for childReference in result.prefixes {
            try await deleteStorageTree(reference: childReference)
        }
    }

    private func listAll(reference: StorageReference) async throws -> StorageListResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageListResult, Error>) in
            reference.listAll { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: self.makeError("스토리지 목록을 불러오지 못했습니다."))
                }
            }
        }
    }

    private func deleteStorageItem(reference: StorageReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func presentableAccountDeletionError(_ error: Error) -> String {
        let nsError = error as NSError
        if AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
            return "보안을 위해 다시 로그인한 뒤 계정을 삭제해주세요."
        }
        return "계정 삭제 실패: \(error.localizedDescription)"
    }

    // MARK: - Report / Block

    /// 게시글 또는 사용자를 신고합니다.
    /// - Parameters:
    ///   - targetId: 신고 대상 문서 ID (postId 또는 userId)
    ///   - targetType: "feedPost" | "matePost" | "user"
    ///   - reason: 신고 사유 (최대 500자)
    func reportContent(targetId: String, targetType: String, reason: String) async throws {
        guard let uid = userId, let reportsCollection else {
            throw makeError("신고 기능은 로그인 후 사용할 수 있습니다.")
        }
        let report = FirestoreReport(
            id: UUID().uuidString,
            reporterId: uid,
            targetId: targetId,
            targetType: targetType,
            reason: reason,
            createdAt: Date()
        )
        try reportsCollection.document(report.id).setData(from: report)
    }

    /// 사용자를 차단합니다. 차단하면 친구/팔로우/대기 요청이 함께 정리됩니다.
    func blockUser(uid blockedUid: String) async throws {
        guard let uid = userId, uid != blockedUid else {
            throw FriendshipServiceError.loginRequired
        }
        guard let db, let blocksCollection else {
            throw FriendshipServiceError.unavailable
        }

        let now = Date()
        let blockId = blockKey(blockerId: uid, blockedId: blockedUid)
        let batch = db.batch()

        batch.setData([
            "id": blockId,
            "blockerId": uid,
            "blockedId": blockedUid,
            "createdAt": Timestamp(date: now),
        ], forDocument: blocksCollection.document(blockId), merge: true)

        if let legacyCollection = blockedUsersCollection(for: uid) {
            let entry = FirestoreBlockedUser(
                id: blockedUid,
                blockedUid: blockedUid,
                createdAt: now
            )
            try batch.setData(from: entry, forDocument: legacyCollection.document(blockedUid), merge: true)
        }

        if let friendshipsCollection {
            let friendshipId = friendshipKey(uid, blockedUid)
            batch.setData([
                "id": friendshipId,
                "friendshipId": friendshipId,
                "users": [uid, blockedUid].sorted(),
                "status": "removed",
                "updatedAt": Timestamp(date: now),
                "removedBy": uid,
                "removedAt": Timestamp(date: now),
            ], forDocument: friendshipsCollection.document(friendshipId), merge: true)
        }

        if let followsCollection {
            let followRef = followsCollection.document(followKey(followerId: uid, followingId: blockedUid))
            batch.setData([
                "id": followRef.documentID,
                "followerId": uid,
                "followingId": blockedUid,
                "isActive": false,
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
            ], forDocument: followRef, merge: true)
        }

        if let friendRequestsCollection {
            for requestId in [friendRequestDocumentId(senderId: uid, receiverId: blockedUid), friendRequestDocumentId(senderId: blockedUid, receiverId: uid), friendshipKey(uid, blockedUid)] {
                let requestRef = friendRequestsCollection.document(requestId)
                let snapshot = try await requestRef.getDocument()
                guard let request = try? snapshot.data(as: FirestoreFriendRequest.self).normalized(documentId: snapshot.documentID),
                      request.status == "pending" else {
                    continue
                }

                batch.updateData([
                    "status": request.resolvedSenderId == uid ? "canceled" : "rejected",
                    "updatedAt": Timestamp(date: now),
                    "respondedAt": Timestamp(date: now),
                ], forDocument: requestRef)
            }
        }

        try await batch.commit()
    }

    /// 차단을 해제합니다.
    func unblockUser(uid blockedUid: String) async throws {
        guard let uid = userId else {
            throw FriendshipServiceError.loginRequired
        }
        guard let db else {
            throw FriendshipServiceError.unavailable
        }

        let batch = db.batch()
        var hasPendingDelete = false

        if let blocksCollection {
            let snapshot = try await blocksCollection
                .whereField("blockerId", isEqualTo: uid)
                .whereField("blockedId", isEqualTo: blockedUid)
                .getDocuments()

            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
                hasPendingDelete = true
            }
        }

        if let collection = blockedUsersCollection(for: uid) {
            batch.deleteDocument(collection.document(blockedUid))
            hasPendingDelete = true
        }

        if hasPendingDelete {
            try await batch.commit()
        }
    }

    /// 내가 차단한 사용자 uid 목록을 반환합니다.
    func fetchBlockedUsers() async throws -> [String] {
        let blocks = try await fetchBlocks()
        guard let uid = userId else { return [] }
        return blocks
            .filter { $0.blockerId == uid }
            .map(\.blockedId)
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "BackendService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func publicUserExists(uid: String) async throws -> Bool {
        guard let publicUsersCollection else { return false }
        return try await publicUsersCollection.document(uid).getDocument().exists
    }

    private func isUserBlocked(blockerId: String, blockedId: String) async throws -> Bool {
        if let blocksCollection {
            return try await blocksCollection.document(blockKey(blockerId: blockerId, blockedId: blockedId)).getDocument().exists
        }
        guard blockerId == userId,
              let blockedUsersCollection = blockedUsersCollection(for: blockerId) else { return false }
        return try await blockedUsersCollection.document(blockedId).getDocument().exists
    }

    private func queryFriendRequests(field: String, value: String) async throws -> QuerySnapshot {
        guard let friendRequestsCollection else {
            throw FriendshipServiceError.unavailable
        }
        return try await friendRequestsCollection
            .whereField(field, isEqualTo: value)
            .order(by: "createdAt", descending: true)
            .getDocuments()
    }

    private func logFriendshipFailure(
        operation: String,
        uid: String?,
        targetUid: String? = nil,
        path: String,
        error: Error
    ) {
        let nsError = error as NSError
        print(
            "[Friendship] operation=\(operation) uid=\(uid ?? "-") targetUid=\(targetUid ?? "-") path=\(path) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)"
        )
    }

    private func friendRequestDocumentId(senderId: String, receiverId: String) -> String {
        "\(senderId)_\(receiverId)"
    }

    private func followKey(followerId: String, followingId: String) -> String {
        "\(followerId)_\(followingId)"
    }

    private func blockKey(blockerId: String, blockedId: String) -> String {
        "\(blockerId)_\(blockedId)"
    }

    private func friendshipKey(_ firstUserId: String, _ secondUserId: String) -> String {
        [firstUserId, secondUserId].sorted().joined(separator: "_")
    }
}

extension FirestoreRunRecord {
    static func from(record: RunRecord, userId: String) -> FirestoreRunRecord {
        let quality = record.resolvedDataQuality
        return FirestoreRunRecord(
            docId: record.id.uuidString,
            id: record.id.uuidString,
            userId: userId,
            startDate: record.startDate,
            endDate: record.endDate ?? record.startDate.addingTimeInterval(record.elapsedSeconds),
            totalDistanceMeters: record.totalDistanceMeters,
            elapsedSeconds: record.elapsedSeconds,
            targetPaceMinutes: record.targetPace?.minutesPerKm,
            targetPaceSeconds: record.targetPace?.secondsPerKm,
            goalType: record.runGoal?.type.rawValue,
            goalDistanceKm: record.runGoal?.targetDistanceKm,
            goalTimeMinutes: record.runGoal?.targetTimeMinutes,
            averageCadenceSpm: record.averageCadenceSpm,
            averageHeartRateBpm: record.averageHeartRateBpm,
            caloriesEstimatedKcal: record.estimatedCaloriesKcal,
            heartRateSource: quality.heartRateSource.rawValue,
            cadenceSource: quality.cadenceSource.rawValue,
            elevationSource: quality.elevationSource.rawValue,
            gpsQuality: quality.gpsQuality.rawValue,
            hasReliableElevation: quality.hasReliableElevation,
            hasReliableSpeed: quality.hasReliableSpeed,
            hasReliableHeartRate: quality.hasReliableHeartRate,
            hasReliableCadence: quality.hasReliableCadence,
            routeEncoded: encodeRoute(record.routePoints),
            createdAt: record.startDate
        )
    }

    func toRunRecord() -> RunRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }

        let hasStoredQuality = heartRateSource != nil
            || cadenceSource != nil
            || elevationSource != nil
            || gpsQuality != nil
            || hasReliableElevation != nil
            || hasReliableSpeed != nil
            || hasReliableHeartRate != nil
            || hasReliableCadence != nil
        let quality = RunDataQuality(
            heartRateSource: RunSensorSource(rawValue: heartRateSource ?? "") ?? .none,
            cadenceSource: RunSensorSource(rawValue: cadenceSource ?? "") ?? .none,
            elevationSource: RunSensorSource(rawValue: elevationSource ?? "") ?? .none,
            gpsQuality: RunGPSQuality(rawValue: gpsQuality ?? "") ?? .poor,
            hasReliableElevation: hasReliableElevation ?? false,
            hasReliableSpeed: hasReliableSpeed ?? false,
            hasReliableHeartRate: hasReliableHeartRate ?? false,
            hasReliableCadence: hasReliableCadence ?? false
        )

        return RunRecord(
            id: uuid,
            startDate: startDate,
            endDate: endDate,
            routePoints: decodeRoute(routeEncoded),
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            targetPace: targetPaceMinutes.flatMap { minutes in
                targetPaceSeconds.map { seconds in
                    PaceTarget(minutesPerKm: minutes, secondsPerKm: seconds)
                }
            },
            runGoal: goalType.flatMap { rawValue in
                RunGoalType(rawValue: rawValue).map {
                    RunGoal(type: $0, targetDistanceKm: goalDistanceKm, targetTimeMinutes: goalTimeMinutes)
                }
            },
            intervalProgram: nil,
            averageCadenceSpm: averageCadenceSpm,
            averageHeartRateBpm: averageHeartRateBpm,
            caloriesEstimatedKcal: caloriesEstimatedKcal,
            dataQuality: hasStoredQuality ? quality : nil
        )
    }

    private static func encodeRoute(_ routePoints: [RoutePoint]) -> String? {
        guard !routePoints.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(routePoints) else { return nil }
        return data.base64EncodedString()
    }

    private func decodeRoute(_ encodedRoute: String?) -> [RoutePoint] {
        guard
            let encodedRoute,
            let data = Data(base64Encoded: encodedRoute),
            let decoded = try? JSONDecoder().decode([RoutePoint].self, from: data)
        else {
            return []
        }

        return decoded
    }
}
