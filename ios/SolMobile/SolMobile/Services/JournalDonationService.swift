//
//  JournalDonationService.swift
//  SolMobile
//

import CoreLocation
import Foundation
import UIKit

enum JournalDonationResult {
    case success
    case notAuthorized
    case unavailable
    case failed(String?)
}

final class JournalDonationService {
    static let shared = JournalDonationService()
    static let supportsDirectDonation = false

    static var isJournalAvailable: Bool {
        if supportsDirectDonation {
            return true
        }
        if #available(iOS 17.2, *) {
            return true
        }
        return false
    }

    func donateMoment(summaryText: String, location: CLLocationCoordinate2D?, moodAnchor: String?) async -> JournalDonationResult {
        guard Self.supportsDirectDonation else {
            return .unavailable
        }
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "JournalDonate") {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        defer {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }

        guard #available(iOS 17.2, *) else {
            return .unavailable
        }

        // TODO: Wire actual JournalingSuggestions donation API once confirmed.
        _ = summaryText
        _ = location
        _ = moodAnchor
        return .unavailable
    }

    func donateEntry(title: String, body: String) async -> JournalDonationResult {
        guard Self.supportsDirectDonation else {
            return .unavailable
        }
        _ = title
        _ = body
        guard #available(iOS 17.2, *) else {
            return .unavailable
        }
        return .unavailable
    }
}
