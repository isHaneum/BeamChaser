import Foundation
import Contacts

@MainActor
final class ContactsService: ObservableObject {
    @Published private(set) var authorizationStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var contactEmailDirectory: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let contactStore = CNContactStore()

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccessIfNeeded() async {
        refreshAuthorizationStatus()

        guard authorizationStatus == .notDetermined else {
            if isAuthorized {
                await loadContacts()
            }
            return
        }

        do {
            let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                contactStore.requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }

            refreshAuthorizationStatus()

            if granted {
                await loadContacts()
            } else {
                errorMessage = AppLanguage.current.text(
                    "연락처 접근이 거부되어 연락처 기반 친구 찾기를 사용할 수 없어요.",
                    "Contacts access was denied, so contact-based friend discovery is unavailable."
                )
            }
        } catch {
            refreshAuthorizationStatus()
            errorMessage = AppLanguage.current.text(
                "연락처 권한을 요청하지 못했어요.",
                "Couldn't request contact permission."
            )
        }
    }

    func loadContacts() async {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            contactEmailDirectory = [:]
            return
        }

        isLoading = true
        defer { isLoading = false }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        var nextDirectory: [String: String] = [:]

        do {
            let request = CNContactFetchRequest(keysToFetch: keys)
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let fullName = [contact.familyName, contact.givenName]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                for emailValue in contact.emailAddresses {
                    let normalized = Self.normalize(emailValue.value as String)
                    guard !normalized.isEmpty else { continue }
                    nextDirectory[normalized] = fullName.isEmpty ? normalized : fullName
                }
            }

            contactEmailDirectory = nextDirectory
            errorMessage = nil
        } catch {
            errorMessage = AppLanguage.current.text(
                "연락처를 불러오지 못했어요.",
                "Couldn't load contacts."
            )
        }
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}