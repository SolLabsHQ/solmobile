//
//  Assert+Helpers.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

enum TestFetch {
    @MainActor
    static func fetchOne<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> T? {
        (try? context.fetch(FetchDescriptor<T>()))?.first
    }

    @MainActor
    static func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

enum TestAssert {
    @MainActor
    static func transmissionStatus(
        _ expected: TransmissionStatus,
        _ tx: Transmission,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(tx.status, expected, "Transmission.status mismatch", file: file, line: line)
    }

    @MainActor
    static func deliveryAttemptCount(
        _ expected: Int,
        _ tx: Transmission,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(tx.deliveryAttempts.count, expected, "deliveryAttempts.count mismatch", file: file, line: line)
    }

    static func contains(_ haystack: String?, _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue((haystack ?? "").contains(needle), "Expected to contain '\(needle)'", file: file, line: line)
    }
}
