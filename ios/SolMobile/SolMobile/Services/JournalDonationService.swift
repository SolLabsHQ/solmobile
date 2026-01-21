//
//  JournalDonationService.swift
//  SolMobile
//

import CoreLocation
import Foundation
import UIKit

final class JournalDonationService {
    static let shared = JournalDonationService()

    func donateMoment(summaryText: String, location: CLLocationCoordinate2D?, moodAnchor: String?) async -> Bool {
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
            return false
        }

        // TODO: Wire actual JournalingSuggestions donation API once confirmed.
        _ = summaryText
        _ = location
        _ = moodAnchor
        return false
    }
}
