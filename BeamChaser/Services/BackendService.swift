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
    let routeEncoded: String?
    let createdAt: Date
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
    let content: String
    let distanceKm: Double?
    let paceFormatted: String?
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
    @Published var isLoading = false
    @Published var error: String?

    private var listeners: [ListenerRegistration] = []

    // MARK: - Collections

    private var usersCollection: CollectionReference? { db?.collection("users") }
    private var runsCollection: CollectionReference? { db?.collection("runs") }
    private var matePostsCollection: CollectionReference? { db?.collection("matePosts") }
    private var feedPostsCollection: CollectionReference? { db?.collection("feedPosts") }
    private var reportsCollection: CollectionReference? { db?.collection("reports") }

    private func friendsCollection(for userId: String) -> CollectionReference? {
        usersCollection?.document(userId).collection("friends")
    }

    private func blockedUsersCollection(for userId: String) -> CollectionReference? {
        usersCollection?.document(userId).collection("blockedUsers")
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

    func addFriend(friendId: String) async throws {
        guard
            let uid = userId,
            uid != friendId,
            let db = db,
            let currentFriendsCollection = friendsCollection(for: uid),
            let targetFriendsCollection = friendsCollection(for: friendId)
        else { return }

        let encoder = Firestore.Encoder()
        let now = Date()
        let currentLink = FirestoreFriendLink(id: friendId, friendId: friendId, createdAt: now)
        let targetLink = FirestoreFriendLink(id: uid, friendId: uid, createdAt: now)

        let batch = db.batch()
        try batch.setData(
            encoder.encode(currentLink),
            forDocument: currentFriendsCollection.document(friendId),
            merge: true
        )
        try batch.setData(
            encoder.encode(targetLink),
            forDocument: targetFriendsCollection.document(uid),
            merge: true
        )
        try await batch.commit()
    }

    // MARK: - Run Records

    func saveRunRecord(_ record: FirestoreRunRecord) async throws {
        guard let runsCollection = runsCollection, let usersCollection = usersCollection else { return }
        try runsCollection.document(record.id).setData(from: record)

        // 누적 통계 업데이트
        guard let uid = userId else { return }
        try await usersCollection.document(uid).updateData([
            "totalDistanceKm": FieldValue.increment(record.totalDistanceMeters / 1000.0),
            "totalRuns": FieldValue.increment(Int64(1)),
            "totalTimeSeconds": FieldValue.increment(record.elapsedSeconds),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
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

    func uploadPhoto(data: Data, path: String) async throws -> String {
        guard let storage = storage else { throw NSError(domain: "BackendService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"]) }
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
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
}
