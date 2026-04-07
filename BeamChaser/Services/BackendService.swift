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

// MARK: - Backend Service

@MainActor
final class BackendService: ObservableObject {

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

    // MARK: - Auth

    func signInWithFirebase(idToken: String, nonce: String) async throws {
        guard FirebaseApp.app() != nil else {
            self.error = "Firebase가 설정되지 않았습니다."
            return
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: nil
        )
        let result = try await Auth.auth().signIn(with: credential)
        await loadOrCreateUser(authUser: result.user, displayName: result.user.displayName ?? "러너")
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
        } catch {
            self.error = "프로필 업데이트 실패: \(error.localizedDescription)"
        }
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
        guard let feedPostsCollection = feedPostsCollection, let db = db else { return }
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
}
