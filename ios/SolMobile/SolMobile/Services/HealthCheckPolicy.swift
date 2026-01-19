//
//  HealthCheckPolicy.swift
//  SolMobile
//
//  Created by SolMobile Diagnostics.
//

import Foundation

enum HealthCheckPolicy {
    static func isSuccess(status: Int) -> Bool {
        (200...299).contains(status)
    }
}
