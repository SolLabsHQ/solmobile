//
//  NetworkMonitor.swift
//  SolMobile
//
//  Created by SolMobile Diagnostics.
//

import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var connectionType: String = "unknown"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sollabshq.solmobile.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let type: String
            if path.status != .satisfied {
                type = "offline"
            } else if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                type = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "ethernet"
            } else {
                type = "other"
            }

            Task { @MainActor in
                self?.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }
}
