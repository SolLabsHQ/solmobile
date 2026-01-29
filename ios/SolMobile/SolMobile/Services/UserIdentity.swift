//
//  UserIdentity.swift
//  SolMobile
//

import Foundation

enum UserIdentity {
    private static let storageKey = "sol.dev.user_id"

    static func resolvedId() -> String {
        if let existing = UserDefaults.standard.string(forKey: storageKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: storageKey)
        return created
    }
}
