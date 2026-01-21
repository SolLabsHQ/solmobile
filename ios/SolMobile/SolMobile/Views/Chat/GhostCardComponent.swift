//
//  GhostCardComponent.swift
//  SolMobile
//

import CoreLocation
import SwiftUI
import UIKit
import SwiftData

struct GhostCardActions {
    var onEdit: (() -> Void)?
    var onForget: (() -> Void)?
    var onAscend: (() async -> Bool)?
    var onAddToCalendar: (() -> Void)?
    var onAddToReminder: (() -> Void)?
    var onGoToThread: (() -> Void)?

    init(
        onEdit: (() -> Void)? = nil,
        onForget: (() -> Void)? = nil,
        onAscend: (() async -> Bool)? = nil,
        onAddToCalendar: (() -> Void)? = nil,
        onAddToReminder: (() -> Void)? = nil,
        onGoToThread: (() -> Void)? = nil
    ) {
        self.onEdit = onEdit
        self.onForget = onForget
        self.onAscend = onAscend
        self.onAddToCalendar = onAddToCalendar
        self.onAddToReminder = onAddToReminder
        self.onGoToThread = onGoToThread
    }
}

struct GhostCardModel: Identifiable {
    let id: UUID
    let kind: GhostKind
    let title: String?
    let body: String?
    let summary: String?
    let snippet: String?
    let memoryId: String?
    let rigorLevel: GhostRigorLevel?
    let moodAnchor: MoodAnchor?
    let factNull: Bool
    let captureSuggestion: CaptureSuggestion?
    let hapticKey: String?
    let actions: GhostCardActions

    init(
        id: UUID = UUID(),
        kind: GhostKind,
        title: String? = nil,
        body: String? = nil,
        summary: String? = nil,
        snippet: String? = nil,
        memoryId: String? = nil,
        rigorLevel: GhostRigorLevel? = nil,
        moodAnchor: MoodAnchor? = nil,
        factNull: Bool = false,
        captureSuggestion: CaptureSuggestion? = nil,
        hapticKey: String? = nil,
        actions: GhostCardActions = GhostCardActions()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.summary = summary
        self.snippet = snippet
        self.memoryId = memoryId
        self.rigorLevel = rigorLevel
        self.moodAnchor = moodAnchor
        self.factNull = factNull
        self.captureSuggestion = captureSuggestion
        self.hapticKey = hapticKey
        self.actions = actions
    }
}

struct GhostCardComponent: View {
    private enum AscendStage {
        case idle
        case lift
        case dissolve
    }

    private static let ledgerMaxAgeSeconds: TimeInterval = 60 * 60 * 24 * 30
    private static let ledgerMaxEntries = 500

    let card: GhostCardModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    @State private var isVisible = false
    @State private var ascendStage: AscendStage = .idle
    @State private var isHidden = false
    @State private var showAscendReceipt = false
    @State private var isAscending = false

    var body: some View {
        if isHidden {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let title = resolvedTitle, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }

                if let bodyText = resolvedBody, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                actionRow
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentTint)
            )
            .opacity(isVisible ? ascendOpacity : 0.0)
            .scaleEffect(isVisible ? ascendScale : entryScale)
            .offset(y: ascendOffset)
            .blur(radius: ascendBlur)
            .animation(entryAnimation, value: isVisible)
            .animation(.easeInOut(duration: 0.1), value: ascendStage)
            .onAppear {
                guard !isVisible else { return }
                isVisible = true
                fireHeartbeatIfNeeded()
            }
            .overlay(alignment: .bottomLeading) {
                if showAscendReceipt {
                    Text("Moment donated to iOS Journal")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .offset(y: 36)
                }
            }
        }
    }

    private var resolvedTitle: String? {
        switch card.kind {
        case .actionProposal:
            return card.captureSuggestion?.title ?? card.title
        case .journalMoment:
            return card.title
        default:
            return card.title
        }
    }

    private var resolvedBody: String? {
        if card.factNull {
            return "I didn't catch a specific fact. Is there something you want me to remember?"
        }

        switch card.kind {
        case .journalMoment:
            return card.snippet ?? card.body ?? card.summary
        case .actionProposal:
            return card.captureSuggestion?.body ?? card.snippet ?? card.summary
        default:
            return card.snippet ?? card.body ?? card.summary
        }
    }

    private var accentTint: Color {
        let base = Color.accentColor
        let opacity = colorScheme == .dark ? 0.08 : 0.05
        return base.opacity(opacity)
    }

    private var entryAnimation: Animation {
        reduceMotion ? .easeIn(duration: 0.6) : .easeIn(duration: 1.2)
    }

    private var entryScale: CGFloat {
        (reduceMotion || !PhysicalityManager.isPhysicalityEnabled) ? 1.0 : 0.98
    }

    private var ascendOffset: CGFloat {
        switch ascendStage {
        case .idle:
            return 0
        case .lift:
            return -20
        case .dissolve:
            return reduceMotion || !PhysicalityManager.isPhysicalityEnabled ? 0 : -40
        }
    }

    private var ascendScale: CGFloat {
        switch ascendStage {
        case .dissolve:
            return reduceMotion || !PhysicalityManager.isPhysicalityEnabled ? 1.0 : 0.9
        default:
            return 1.0
        }
    }

    private var ascendOpacity: Double {
        switch ascendStage {
        case .dissolve:
            return 0.0
        default:
            return 1.0
        }
    }

    private var ascendBlur: CGFloat {
        switch ascendStage {
        case .idle:
            return 0
        case .lift:
            return reduceMotion || !PhysicalityManager.isPhysicalityEnabled ? 0 : 6
        case .dissolve:
            return reduceMotion || !PhysicalityManager.isPhysicalityEnabled ? 0 : 12
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch card.kind {
        case .memoryArtifact:
            HStack(spacing: 12) {
                if let onEdit = card.actions.onEdit {
                    Button("Edit", action: onEdit)
                        .frame(minHeight: 44)
                }
                if let onForget = card.actions.onForget {
                    Button("Forget", role: .destructive) {
                        performForget(onForget)
                    }
                    .frame(minHeight: 44)
                }
            }
        case .journalMoment:
            HStack(spacing: 12) {
                Button("Ascend") {
                    Task { await performAscend() }
                }
                .frame(minHeight: 44)

                if let onForget = card.actions.onForget {
                    Button("Forget", role: .destructive) {
                        performForget(onForget)
                    }
                    .frame(minHeight: 44)
                }
            }
        case .actionProposal:
            Menu {
                if let onAddToCalendar = card.actions.onAddToCalendar {
                    Button("Add to Calendar", action: onAddToCalendar)
                }
                if let onAddToReminder = card.actions.onAddToReminder {
                    Button("Set Reminder", action: onAddToReminder)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
            }
        case .reverieInsight, .conflictResolver, .evidenceReceipt:
            if let onGoToThread = card.actions.onGoToThread {
                Button("Go to Thread", action: onGoToThread)
                    .frame(minHeight: 44)
            }
        }
    }

    private func performForget(_ action: @escaping () -> Void) {
        if PhysicalityManager.isPhysicalityEnabled {
            GhostCardHaptics.forget()
        }
        withAnimation(.easeOut(duration: 0.2)) {
            isHidden = true
        }
        action()
    }

    private func fireHeartbeatIfNeeded() {
        pruneLedgerIfNeeded()
        let key = card.hapticKey ?? card.memoryId ?? card.id.uuidString

        if let ledger = fetchLedger(key: key) {
            if ledger.arrivalHapticFired {
                try? modelContext.save()
                return
            }
            ledger.arrivalHapticFired = true
        } else {
            let ledger = GhostCardLedger(key: key, arrivalHapticFired: true)
            modelContext.insert(ledger)
        }

        if PhysicalityManager.canFireHaptics() {
            let intensity = PhysicalityManager.heartbeatIntensity(for: card.moodAnchor)
            GhostCardHaptics.heartbeat(intensity: intensity)
        }

        if card.kind == .journalMoment {
            captureJournalLocation()
        }

        try? modelContext.save()
    }

    private func pruneLedgerIfNeeded() {
        let cutoff = Date().addingTimeInterval(-Self.ledgerMaxAgeSeconds)
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
        let overflow = allEntries.count - Self.ledgerMaxEntries
        guard overflow > 0 else { return }
        for entry in allEntries.prefix(overflow) {
            modelContext.delete(entry)
        }
    }

    private func captureJournalLocation() {
        guard let memoryId = card.memoryId else { return }

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

    private func fetchLedger(key: String) -> GhostCardLedger? {
        let descriptor = FetchDescriptor<GhostCardLedger>(predicate: #Predicate { $0.key == key })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func performAscend() async {
        guard !isAscending else { return }
        isAscending = true

        if PhysicalityManager.isPhysicalityEnabled && !reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                ascendStage = .lift
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeInOut(duration: 0.6)) {
                ascendStage = .dissolve
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                ascendStage = .dissolve
            }
        }

        let success = await (card.actions.onAscend?() ?? false)

        if success {
            GhostCardHaptics.releaseTick()
            showAscendReceipt = true
            markAscended()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showAscendReceipt = false
                    isHidden = true
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                ascendStage = .idle
            }
        }

        isAscending = false
    }

    private func markAscended() {
        guard let memoryId = card.memoryId else { return }
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        if let artifact = try? modelContext.fetch(descriptor).first {
            artifact.ascendedAt = Date()
            try? modelContext.save()
        }
    }
}

private enum GhostCardHaptics {
    static func heartbeat(intensity: Double) {
        guard PhysicalityManager.canFireHaptics() else { return }
        let clamped = max(0.0, min(intensity, 1.0))
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(clamped * 0.6))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred(intensity: CGFloat(clamped * 0.9))
        }
    }

    static func releaseTick() {
        guard PhysicalityManager.canFireHaptics() else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func forget() {
        guard PhysicalityManager.canFireHaptics() else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
}
