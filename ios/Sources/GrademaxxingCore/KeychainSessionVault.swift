import Foundation
import Security

/// Holds only encrypted server session state and its identity, never the StudentVUE password.
public actor KeychainSessionVault: SessionVault {
  private let service: String
  public init(service: String) { self.service = service }
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "app-session", kSecAttrSynchronizable as String: false,
    ]
  }
  public func load() throws -> SavedSession? {
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw APIError.secureStorage }
    guard let session = try? JSONDecoder().decode(SavedSession.self, from: data) else {
      try clear()
      return nil
    }
    return session
  }
  public func save(_ session: SavedSession) throws {
    let data = try JSONEncoder().encode(session)
    let updates: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
      let attributes = query.merging(updates, uniquingKeysWith: { _, value in value })
      guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
        throw APIError.secureStorage
      }
    } else if status != errSecSuccess {
      throw APIError.secureStorage
    }
  }
  public func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw APIError.secureStorage
    }
  }
}
