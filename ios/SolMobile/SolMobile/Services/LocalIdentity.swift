//
//  LocalIdentity.swift
//  SolMobile
//

import Foundation

enum LocalIdentity {
    static func localUserUuid() -> String {
        if let existing = KeychainStore.read(key: KeychainKeys.localUserUuid),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let created = UUID().uuidString.lowercased()
        _ = KeychainStore.write(created, key: KeychainKeys.localUserUuid)
        return created
    }
}
