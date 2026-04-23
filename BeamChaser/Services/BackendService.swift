import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - Firestore Data Models

struct FirestoreUser: Codable {
    let uid: String
    var displayName: String
    var email: String
    var level: String
    var totalDistanceKm: Double
    var totalRuns: Int
    var totalTimeSeconds: Double
    var heightCm: Double?
    var photoURL: String?
    var createdAt: Date
    var updatedAt: Date

    static func from(authUser: User, name: String) -> FirestoreUser {
        FirestoreUser(
            uid: authUser.uid,
            displayName: name,
            email: authUser.email ?? "",
            level: RunnerLevel.starter.rawValue,
            totalDistanceKm: 0,
            totalRuns: 0,
            totalTimeSeconds: 0,
            heightCm: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
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

struct FirestoreFriendLink: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let friendId: String
    let createdAt: Date
}

struct FirestoreFriendRequest: Codable, Identifiable {
    @DocumentID var docId: String?
    var id: String
    let fromUserId: String
    let toUserId: String
    let status: String
    let source: String
    let createdAt: Date
    let respondedAt: Date?
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
    private var runsCollection: CollectionReference? { db?.collection("runs") }
    private var matePostsCollection: CollectionReference? { db?.collection("matePosts") }
    private var feedPostsCollection: CollectionReference? { db?.collection("feedPosts") }
    private var reportsCollection: CollectionReference? { db?.collection("reports") }
    private var friendRequestsCollection: CollectionReference? { db?.collection("friendRequests") }

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
                currentUser = try doc.data(as: FirestoreUser.self)
            } else {
                let newUser = FirestoreUser.from(authUser: authUser, name: displayName)
                try usersCollection.document(authUser.uid).setData(from: newUser)
                currentUser = newUser
            }
        } catch {
            self.error = "프로필 로드 실패: \(error.localizedDescription)"
        }
    }

    func updateUserProfile(_ updates: [String: Any]) async {
        guard let uid = userId, let usersCollection = usersCollection else { return }
        var merged = updates
        merged["updatedAt"] = FieldValue.serverTimestamp()
        do {
            try await usersCollection.document(uid).updateData(merged)
            if var currentUser {
                if let displayName = updates["displayName"] as? String {
                    currentUser.displayName = displayName
                }
                if let level = updates["level"] as? String {
                    currentUser.level = level
                }
                if let totalDistanceKm = updates["totalDistanceKm"] as? Double {
                    currentUser.totalDistanceKm = totalDistanceKm
                }
                if let totalRuns = updates["totalRuns"] as? Int {
                    currentUser.totalRuns = totalRuns
                }
                if let totalTimeSeconds = updates["totalTimeSeconds"] as? Double {
                    currentUser.totalTimeSeconds = totalTimeSeconds
                }
                if let heightCm = updates["heightCm"] as? Double {
                    currentUser.heightCm = heightCm
                }
                currentUser.updatedAt = Date()
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

        let ref = storage.reference().child("profilePhotos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        let urlString = downloadURL.absoluteString

        await updateUserProfile(["photoURL": urlString])
        return urlString
    }

    func fetchUsers(limit: Int = 100) async throws -> [FirestoreUser] {
        guard let usersCollection = usersCollection else { return [] }
        let snapshot = try await usersCollection
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) }
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

            if let usersCollection {
                try await usersCollection.document(uid).delete()
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

    func fetchFriends() async throws -> [FirestoreFriendLink] {
        guard let uid = userId, let friendsCollection = friendsCollection(for: uid) else { return [] }
        let snapshot = try await friendsCollection.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreFriendLink.self) }
    }

    func fetchFriendRequests() async throws -> [FirestoreFriendRequest] {
        guard let uid = userId, let friendRequestsCollection else { return [] }

        async let incomingTask = friendRequestsCollection
            .whereField("toUserId", isEqualTo: uid)
            .getDocuments()
        async let outgoingTask = friendRequestsCollection
            .whereField("fromUserId", isEqualTo: uid)
            .getDocuments()

        let incomingSnapshot = try await incomingTask
        let outgoingSnapshot = try await outgoingTask
        var requestsById: [String: FirestoreFriendRequest] = [:]

        for snapshot in [incomingSnapshot, outgoingSnapshot] {
            for document in snapshot.documents {
                if let request = try? document.data(as: FirestoreFriendRequest.self) {
                    requestsById[request.id] = request
                }
            }
        }

        return requestsById.values.sorted { $0.createdAt > $1.createdAt }
    }

    func sendFriendRequest(toUserId: String, source: String = "manual") async throws {
        guard let uid = userId, uid != toUserId, let friendRequestsCollection else {
            throw makeError(AppLanguage.current.text("친구 요청은 로그인 후 사용할 수 있어요.", "Friend requests are available after sign-in."))
        }

        let requestId = friendRequestKey(uid, toUserId)
        let ref = friendRequestsCollection.document(requestId)
        let snapshot = try await ref.getDocument()

        if let existing = try? snapshot.data(as: FirestoreFriendRequest.self) {
            switch existing.status {
            case "pending":
                throw makeError(AppLanguage.current.text("이미 요청이 진행 중입니다.", "A friend request is already pending."))
            case "accepted":
                throw makeError(AppLanguage.current.text("이미 친구로 연결되어 있어요.", "You're already connected as friends."))
            default:
                throw makeError(AppLanguage.current.text("이 사용자와의 이전 요청 기록이 있어 지금은 새 요청을 보낼 수 없어요.", "There is a previous request record with this user, so a new request can't be sent right now."))
            }
        }

        let request = FirestoreFriendRequest(
            id: requestId,
            fromUserId: uid,
            toUserId: toUserId,
            status: "pending",
            source: source,
            createdAt: Date(),
            respondedAt: nil
        )
        try ref.setData(from: request)
    }

    func respondToFriendRequest(requestId: String, accept: Bool) async throws {
        guard let uid = userId, let friendRequestsCollection else {
            throw makeError(AppLanguage.current.text("친구 요청 응답은 로그인 후 사용할 수 있어요.", "Responding to a friend request is available after sign-in."))
        }

        let ref = friendRequestsCollection.document(requestId)
        let snapshot = try await ref.getDocument()
        guard let request = try? snapshot.data(as: FirestoreFriendRequest.self) else {
            throw makeError(AppLanguage.current.text("친구 요청을 찾지 못했어요.", "Couldn't find the friend request."))
        }
        guard request.toUserId == uid else {
            throw makeError(AppLanguage.current.text("이 요청에 응답할 권한이 없어요.", "You don't have permission to respond to this request."))
        }
        guard request.status == "pending" else {
            throw makeError(AppLanguage.current.text("이미 처리된 친구 요청입니다.", "This friend request has already been handled."))
        }

        try await ref.updateData([
            "status": accept ? "accepted" : "rejected",
            "respondedAt": Timestamp(date: Date()),
        ])
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
            "totalRuns": FieldValue.increment(Int64(1)),
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
                onChange(posts)
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
                onChange(posts)
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
            let incomingSnapshot = try await friendRequestsCollection.whereField("toUserId", isEqualTo: uid).getDocuments()
            let outgoingSnapshot = try await friendRequestsCollection.whereField("fromUserId", isEqualTo: uid).getDocuments()
            references.append(contentsOf: incomingSnapshot.documents.map(\.reference))
            references.append(contentsOf: outgoingSnapshot.documents.map(\.reference))
        }

        try await deleteDocuments(references)
    }

    private func deleteFriendLinks(uid: String) async throws {
        guard let usersCollection else { return }
        let friendsSnapshot = try await usersCollection.document(uid).collection("friends").getDocuments()

        var references = friendsSnapshot.documents.map(\.reference)
        references.append(contentsOf: friendsSnapshot.documents.map {
            usersCollection.document($0.documentID).collection("friends").document(uid)
        })

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

    /// 사용자를 차단합니다. 차단하면 해당 유저의 게시물이 피드에 표시되지 않습니다.
    func blockUser(uid blockedUid: String) async throws {
        guard let uid = userId, uid != blockedUid,
              let collection = blockedUsersCollection(for: uid) else {
            throw makeError("차단 기능은 로그인 후 사용할 수 있습니다.")
        }
        let entry = FirestoreBlockedUser(
            id: blockedUid,
            blockedUid: blockedUid,
            createdAt: Date()
        )
        try collection.document(blockedUid).setData(from: entry, merge: true)
    }

    /// 차단을 해제합니다.
    func unblockUser(uid blockedUid: String) async throws {
        guard let uid = userId,
              let collection = blockedUsersCollection(for: uid) else { return }
        try await collection.document(blockedUid).delete()
    }

    /// 내가 차단한 사용자 uid 목록을 반환합니다.
    func fetchBlockedUsers() async throws -> [String] {
        guard let uid = userId,
              let collection = blockedUsersCollection(for: uid) else { return [] }
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap {
            (try? $0.data(as: FirestoreBlockedUser.self))?.blockedUid
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "BackendService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func friendRequestKey(_ firstUserId: String, _ secondUserId: String) -> String {
        [firstUserId, secondUserId].sorted().joined(separator: "_")
    }
}

extension FirestoreRunRecord {
    static func from(record: RunRecord, userId: String) -> FirestoreRunRecord {
        FirestoreRunRecord(
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
            routeEncoded: encodeRoute(record.routePoints),
            createdAt: record.startDate
        )
    }

    func toRunRecord() -> RunRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }

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
            averageHeartRateBpm: averageHeartRateBpm
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
