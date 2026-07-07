import Foundation
import Security

enum PoplurKeychain {
    private static let service = "com.apptists.poplur2025"
    private static let emailDefaultsKey = "poplur_biometric_email"

    // MARK: - Saved email (UserDefaults — not sensitive)

    static var savedEmail: String? {
        get { UserDefaults.standard.string(forKey: emailDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: emailDefaultsKey) }
    }

    // MARK: - Password (Keychain)

    @discardableResult
    static func saveCredentials(email: String, password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        deleteCredentials(for: email)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: email,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            savedEmail = email
        }
        return status == errSecSuccess
    }

    static func retrievePassword(for email: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: email,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
    }

    static func deleteCredentials(for email: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: email
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearSavedCredentials() {
        if let email = savedEmail {
            deleteCredentials(for: email)
        }
        savedEmail = nil
    }

    static var hasCredentials: Bool {
        guard let email = savedEmail else { return false }
        return retrievePassword(for: email) != nil
    }
}
