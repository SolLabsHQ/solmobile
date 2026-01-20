//
//  AppEnvironment.swift
//  SolMobile
//
//  Created by SolMobile Environment.
//

import Foundation

enum AppEnvironment: String, CaseIterable {
    case dev
    case staging
    case prod

    static var override: AppEnvironment?

    static var current: AppEnvironment {
        if let forced = override {
            return forced
        }

        if let raw = Bundle.main.infoDictionary?["SOL_ENV"] as? String,
           let env = AppEnvironment(rawValue: raw.lowercased()) {
            return env
        }

        #if DEBUG
        return .dev
        #else
        return .staging
        #endif
    }

    var requiresHTTPS: Bool {
        self != .dev
    }

    var defaultBaseURLString: String {
        switch self {
        case .dev:
            return Bundle.main.infoDictionary?["SOLSERVER_BASE_URL_DEV"] as? String
                ?? "http://127.0.0.1:3333"
        case .staging:
            return Bundle.main.infoDictionary?["SOLSERVER_BASE_URL_STAGING"] as? String
                ?? Bundle.main.infoDictionary?["SOLSERVER_BASE_URL"] as? String
                ?? "https://solserver-staging.fly.dev"
        case .prod:
            return Bundle.main.infoDictionary?["SOLSERVER_BASE_URL_PROD"] as? String
                ?? Bundle.main.infoDictionary?["SOLSERVER_BASE_URL"] as? String
                ?? "https://solserver-prod.example.com"
        }
    }
}

enum SolServerBaseURL {
    static let storageKey = "solserver.baseURL"

    static var defaultBaseURLString: String {
        AppEnvironment.current.defaultBaseURLString
    }

    static func effectiveURLString() -> String {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? defaultBaseURLString
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed) {
            if AppEnvironment.current.requiresHTTPS,
               url.scheme?.lowercased() != "https" {
                return defaultBaseURLString
            }
            return trimmed
        }
        return defaultBaseURLString
    }

    static func effectiveURL() -> URL {
        let url = URL(string: effectiveURLString())
        return url ?? URL(string: defaultBaseURLString)!
    }
}
