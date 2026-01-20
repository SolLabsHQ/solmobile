//
//  EnvironmentKeys.swift
//  SolMobile
//
//  Created by SolMobile Environment.
//

import SwiftUI

private struct OutboxServiceKey: EnvironmentKey {
    static let defaultValue: OutboxService? = nil
}

extension EnvironmentValues {
    var outboxService: OutboxService? {
        get { self[OutboxServiceKey.self] }
        set { self[OutboxServiceKey.self] = newValue }
    }
}

private struct UnreadTrackerKey: EnvironmentKey {
    static let defaultValue: UnreadTrackerActor? = nil
}

extension EnvironmentValues {
    var unreadTracker: UnreadTrackerActor? {
        get { self[UnreadTrackerKey.self] }
        set { self[UnreadTrackerKey.self] = newValue }
    }
}
