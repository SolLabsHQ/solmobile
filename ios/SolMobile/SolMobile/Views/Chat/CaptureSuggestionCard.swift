//
//  CaptureSuggestionCard.swift
//  SolMobile
//

import SwiftUI
import SwiftData
import EventKit
import EventKitUI
import UIKit

struct CaptureSuggestionCard: View {
    private enum CaptureDestination: String {
        case journal
        case reminder
        case calendar
        case dismissed
    }

    private enum ActiveSheet: Identifiable {
        case journal(text: String)
        case reminder(reminder: EKReminder)
        case calendar(event: EKEvent)

        var id: String {
            switch self {
            case .journal:
                return "journal"
            case .reminder:
                return "reminder"
            case .calendar:
                return "calendar"
            }
        }
    }

    let message: Message
    let suggestion: CaptureSuggestion
    private let suggestionId: String

    @Environment(\.modelContext) private var modelContext
    @Query private var captured: [CapturedSuggestion]

    @State private var activeSheet: ActiveSheet?
    @State private var showSettingsAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""

    private let eventStore = EKEventStore()

    init(message: Message, suggestion: CaptureSuggestion) {
        self.message = message
        self.suggestion = suggestion
        let resolved = CaptureSuggestionCard.resolveSuggestionId(message: message, suggestion: suggestion)
        self.suggestionId = resolved
        _captured = Query(filter: #Predicate<CapturedSuggestion> { $0.suggestionId == resolved })
    }

    var body: some View {
        if isDismissed {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: suggestion.suggestionType.iconName)
                    Text(suggestion.suggestionType.label)
                        .font(.caption)
                        .foregroundStyle(BrandColors.timeLaneText)
                    Spacer()
                }

                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let body = suggestion.body, !body.isEmpty {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(BrandColors.timeLaneText)
                }

                HStack(spacing: 8) {
                    Button {
                        startCapture()
                    } label: {
                        if isCaptured {
                            Label("Captured", systemImage: "checkmark")
                        } else {
                            Text("Capture")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCaptured)

                    if !isCaptured {
                        Button("Dismiss") {
                            markCaptured(destination: .dismissed)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(BrandColors.statusText)
                    }
                }
            }
            .padding(10)
            .background(BrandColors.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .journal(let text):
                    ActivityView(activityItems: [text]) { completed in
                        if completed { markCaptured(destination: .journal) }
                    }
                case .reminder(let reminder):
                    ReminderSaveView(reminder: reminder, eventStore: eventStore) { saved in
                        if saved {
                            markCaptured(destination: .reminder)
                        }
                    }
                case .calendar(let event):
                    EventEditView(eventStore: eventStore, event: event) { action in
                        if action == .saved {
                            markCaptured(destination: .calendar)
                        }
                    }
                }
            }
            .alert("Enable Access", isPresented: $showSettingsAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Allow access in Settings to export this capture suggestion.")
            }
            .alert("Export Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var isCaptured: Bool {
        guard let record = captured.first else { return false }
        return record.destination != CaptureDestination.dismissed.rawValue
    }

    private var isDismissed: Bool {
        captured.first?.destination == CaptureDestination.dismissed.rawValue
    }

    private func startCapture() {
        switch suggestion.suggestionType {
        case .journalEntry:
            activeSheet = .journal(text: buildJournalText())
        case .reminder:
            Task { await presentReminderEditor() }
        case .calendarEvent:
            Task { await presentEventEditor() }
        }
    }

    @MainActor
    private func presentReminderEditor() async {
        guard await requestReminderAccess() else {
            showSettingsAlert = true
            return
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = suggestion.title
        reminder.notes = suggestion.body
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let alarmDate = parseSuggestedDate(suggestion.suggestedDate) {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }

        activeSheet = .reminder(reminder: reminder)
    }

    @MainActor
    private func presentEventEditor() async {
        guard let startDate = parseSuggestedStartAt(suggestion.suggestedStartAt) else {
            errorMessage = "Calendar suggestion is missing a valid start time."
            showErrorAlert = true
            return
        }

        guard await requestEventAccess() else {
            showSettingsAlert = true
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = suggestion.title
        event.notes = suggestion.body
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3600)

        activeSheet = .calendar(event: event)
    }

    @MainActor
    private func requestEventAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestWriteOnlyAccessToEvents()
            } catch {
                errorMessage = "Calendar access failed."
                showErrorAlert = true
                return false
            }
        }
        errorMessage = "Calendar access is unavailable on this iOS version."
        showErrorAlert = true
        return false
    }

    @MainActor
    private func requestReminderAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                errorMessage = "Reminders access failed."
                showErrorAlert = true
                return false
            }
        }
        errorMessage = "Reminders access is unavailable on this iOS version."
        showErrorAlert = true
        return false
    }

    private func markCaptured(destination: CaptureDestination) {
        guard !suggestionId.isEmpty else { return }
        if captured.first != nil { return }

        let record = CapturedSuggestion(
            suggestionId: suggestionId,
            capturedAt: Date(),
            destination: destination.rawValue,
            messageId: message.id
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func buildJournalText() -> String {
        if let body = suggestion.body, !body.isEmpty {
            return "\(suggestion.title)\n\n\(body)"
        }
        return suggestion.title
    }

    private func parseSuggestedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    private func parseSuggestedStartAt(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = Self.iso8601WithFractional.date(from: value) {
            return date
        }
        return Self.iso8601Basic.date(from: value)
    }

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func resolveSuggestionId(message: Message, suggestion: CaptureSuggestion) -> String {
        if let id = suggestion.suggestionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            return id
        }
        if let stored = message.captureSuggestionId, !stored.isEmpty {
            return stored
        }
        if let transmissionId = message.transmissionId, !transmissionId.isEmpty {
            return "cap_\(transmissionId)"
        }
        return "cap_local_\(message.id.uuidString)"
    }
}

private extension CaptureSuggestion.SuggestionType {
    var iconName: String {
        switch self {
        case .journalEntry:
            return "book.closed"
        case .reminder:
            return "checkmark.circle"
        case .calendarEvent:
            return "calendar"
        }
    }

    var label: String {
        switch self {
        case .journalEntry:
            return "Journal"
        case .reminder:
            return "Reminder"
        case .calendarEvent:
            return "Calendar"
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EventEditView: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let event: EKEvent
    let completion: (EKEventEditViewAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let completion: (EKEventEditViewAction) -> Void

        init(completion: @escaping (EKEventEditViewAction) -> Void) {
            self.completion = completion
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            completion(action)
            controller.dismiss(animated: true)
        }
    }
}

struct ReminderSaveView: View {
    let reminder: EKReminder
    let eventStore: EKEventStore
    let completion: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    Text(reminder.title)
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .foregroundStyle(BrandColors.timeLaneText)
                    }
                    if let alarmDate = reminder.alarms?.first?.absoluteDate {
                        Text(alarmDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(BrandColors.timeLaneText)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        completion(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try eventStore.save(reminder, commit: true)
                            completion(true)
                            dismiss()
                        } catch {
                            errorMessage = "Failed to save reminder."
                        }
                    }
                }
            }
        }
    }
}
