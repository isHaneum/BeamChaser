// Firestore Security Rules for RunBeam
// Deploy via Firebase Console > Firestore > Rules
//
// rules_version = '2';
// service cloud.firestore {
//   match /databases/{database}/documents {
//
//     // ── Users ──
//     match /users/{userId} {
//       allow read: if request.auth != null;
//       allow create: if request.auth != null && request.auth.uid == userId;
//       allow update: if request.auth != null && request.auth.uid == userId;
//       allow delete: if false;
//     }
//
//     // ── Run Records ──
//     match /runs/{runId} {
//       allow read: if request.auth != null && resource.data.userId == request.auth.uid;
//       allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
//       allow update, delete: if false;
//     }
//
//     // ── Mate Posts ──
//     match /matePosts/{postId} {
//       allow read: if request.auth != null;
//       allow create: if request.auth != null;
//       allow update: if request.auth != null;
//       allow delete: if request.auth != null && resource.data.authorId == request.auth.uid;
//     }
//
//     // ── Feed Posts ──
//     match /feedPosts/{postId} {
//       allow read: if request.auth != null;
//       allow create: if request.auth != null;
//       allow update: if request.auth != null;
//       allow delete: if request.auth != null && resource.data.authorId == request.auth.uid;
//     }
//   }
// }
//
// ── Storage Rules ──
// Deploy via Firebase Console > Storage > Rules
//
// rules_version = '2';
// service firebase.storage {
//   match /b/{bucket}/o {
//     match /feed_photos/{userId}/{allPaths=**} {
//       allow read: if request.auth != null;
//       allow write: if request.auth != null && request.auth.uid == userId
//                    && request.resource.size < 10 * 1024 * 1024
//                    && request.resource.contentType.matches('image/.*');
//     }
//   }
// }

import Foundation

// MARK: - Firebase Setup Guide
//
// 1. Firebase Console (https://console.firebase.google.com) 에서 프로젝트 생성
//    - 프로젝트 이름: "RunBeam"
//    - Google Analytics: 선택 사항
//
// 2. iOS 앱 등록
//    - Bundle ID: com.goldmine.runbeam
//    - 앱 닉네임: RunBeam
//    - GoogleService-Info.plist 다운로드 → RunBeam/Resources/ 에 추가
//
// 3. Firebase 서비스 활성화
//    - Authentication > Sign-in method > Apple 활성화
//    - Firestore Database > 데이터베이스 만들기 > 프로덕션 모드
//    - Storage > 시작하기
//
// 4. Firestore Indexes (Firebase Console > Firestore > Indexes)
//    - Collection: runs | Fields: userId ASC, startDate DESC
//    - Collection: matePosts | Fields: createdAt DESC
//    - Collection: feedPosts | Fields: createdAt DESC
//
// 5. 위의 Security Rules를 Firebase Console에 배포
//
// 6. 앱 실행 전 GoogleService-Info.plist가 프로젝트에 포함되었는지 확인

enum FirebaseSetup {
    static let bundleId = "com.goldmine.runbeam"
    static let firestoreCollections = [
        "users",       // 사용자 프로필
        "runs",        // 러닝 기록
        "matePosts",   // 러닝 메이트 모집
        "feedPosts",   // 커뮤니티 피드
    ]
}
