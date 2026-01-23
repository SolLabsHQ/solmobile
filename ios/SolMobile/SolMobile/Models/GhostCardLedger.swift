//
//  GhostCardLedger.swift
//  SolMobile
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class GhostCardLedger {
    @Attribute(.unique) var key: String
    var arrivalHapticFired: Bool
    var canonizationHapticFired: Bool
    var createdAt: Date

    init(
        key: String,
        arrivalHapticFired: Bool = false,
        canonizationHapticFired: Bool = false,
        createdAt: Date = Date()
    ) {
        self.key = key
        self.arrivalHapticFired = arrivalHapticFired
        self.canonizationHapticFired = canonizationHapticFired
        self.createdAt = createdAt
    }
}

enum GhostCardReceipt {
    private static let ledgerMaxAgeSeconds: TimeInterval = 60 * 60 * 24 * 30
    private static let ledgerMaxEntries = 500

    static func fireCanonizationIfNeeded(
        modelContext: ModelContext,
        previousMemoryId: String?,
        newMemoryId: String?,
        factNull: Bool,
        ghostKind: GhostKind?
    ) {
        let previousValue = (previousMemoryId?.isEmpty == false) ? previousMemoryId : nil
        guard previousValue == nil,
              let newMemoryId,
              !newMemoryId.isEmpty,
              !factNull else { return }

        pruneLedgerIfNeeded(modelContext: modelContext)

        let descriptor = FetchDescriptor<GhostCardLedger>(
            predicate: #Predicate { $0.key == newMemoryId }
        )
        if let ledger = try? modelContext.fetch(descriptor).first {
            guard !ledger.canonizationHapticFired else { return }
            ledger.canonizationHapticFired = true
        } else {
            let ledger = GhostCardLedger(
                key: newMemoryId,
                arrivalHapticFired: false,
                canonizationHapticFired: true
            )
            modelContext.insert(ledger)
        }

        if PhysicalityManager.canFireHaptics() {
            DispatchQueue.main.async {
                GhostCardHaptics.heartbeat(intensity: 1.0)
            }
        }

        if ghostKind == .journalMoment {
            captureJournalLocation(modelContext: modelContext, memoryId: newMemoryId)
        }

        try? modelContext.save()
    }

    private static func pruneLedgerIfNeeded(modelContext: ModelContext) {
        let cutoff = Date().addingTimeInterval(-ledgerMaxAgeSeconds)
        let staleDescriptor = FetchDescriptor<GhostCardLedger>(
            predicate: #Predicate { $0.createdAt < cutoff }
        )

        if let stale = try? modelContext.fetch(staleDescriptor), !stale.isEmpty {
            for entry in stale {
                modelContext.delete(entry)
            }
        }

        let allDescriptor = FetchDescriptor<GhostCardLedger>(
            sortBy: [SortDescriptor(\GhostCardLedger.createdAt, order: .forward)]
        )
        guard let allEntries = try? modelContext.fetch(allDescriptor) else { return }
        let overflow = allEntries.count - ledgerMaxEntries
        guard overflow > 0 else { return }
        for entry in allEntries.prefix(overflow) {
            modelContext.delete(entry)
        }
    }

    private static func captureJournalLocation(modelContext: ModelContext, memoryId: String) {
        Task {
            guard let location = await LocationSampler.shared.snapshotLocation() else { return }
            await MainActor.run {
                let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
                if let artifact = try? modelContext.fetch(descriptor).first {
                    artifact.locationLatitude = location.coordinate.latitude
                    artifact.locationLongitude = location.coordinate.longitude
                    try? modelContext.save()
                }
            }
        }
    }
}
