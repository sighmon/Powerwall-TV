//
//  KeychainWrapper.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//

import SwiftUI
import Security

class KeychainWrapper {
    static let standard = KeychainWrapper()

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        if Self.suppressesInteractivePrompts {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let data = value.data(using: .utf8) else { return false }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func string(forKey key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if Self.suppressesInteractivePrompts {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == noErr, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    /// Unit tests launch the host app, whose init reads the keychain. An interactive
    /// prompt blocks `SecItemCopyMatching` with nobody to click Allow. Fail that prompt
    /// only while XCTest is driving the process.
    private static var suppressesInteractivePrompts: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFile"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
