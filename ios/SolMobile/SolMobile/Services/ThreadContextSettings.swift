//
//  ThreadContextSettings.swift
//  SolMobile
//

import Foundation

enum ThreadContextSettings {
    static let modeKey = "sol.thread_context.mode"
    static let showKey = "sol.thread_context.show"

    enum Mode: String {
        case off
        case auto
    }

    static func normalized(_ raw: String?) -> Mode {
        Mode(rawValue: raw ?? "") ?? .auto
    }
}
