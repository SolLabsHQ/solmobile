//
//  DiagnosticsView.swift
//  SolMobile
//
//  Created by SolMobile Diagnostics.
//

import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @ObservedObject private var store = DiagnosticsStore.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    @State private var showCopiedAlert = false
    @State private var copiedMessage = ""

    var body: some View {
        List {
            Section("Actions") {
                ShareLink(item: store.exportText()) {
                    Label("Share diagnostics", systemImage: "square.and.arrow.up")
                }

                Button {
                    UIPasteboard.general.string = environmentSnapshot()
                    copiedMessage = "Copied environment snapshot"
                    showCopiedAlert = true
                } label: {
                    Label("Copy environment snapshot", systemImage: "doc.text")
                }

                Button {
                    if let entry = store.lastFailureEntry() {
                        let curl = store.curlCommand(for: entry)
                        UIPasteboard.general.string = curl
                        copiedMessage = "Copied curl for \(entry.method) \(entry.url)"
                        showCopiedAlert = true
                    }
                } label: {
                    Label("Copy curl (last failure)", systemImage: "doc.on.doc")
                }
                .disabled(store.lastFailureEntry() == nil)

                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear diagnostics", systemImage: "trash")
                }
            }

            Section("Recent") {
                if store.entries.isEmpty {
                    Text("No diagnostics captured yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entry.method) \(entry.url)")
                            .font(.subheadline)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: 12) {
                            if let status = entry.status {
                                Text("HTTP \(status)")
                                    .font(.caption)
                                    .foregroundStyle(status >= 400 ? .red : .secondary)
                            } else {
                                Text("No response")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let latency = entry.latencyMs {
                                Text("\(latency)ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let errorDescription = entry.errorDescription, !errorDescription.isEmpty {
                            Text(errorDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if let errorDomain = entry.errorDomain, let errorCode = entry.errorCode {
                            Text("\(errorDomain) (\(errorCode))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let snippet = entry.responseSnippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        if !entry.safeResponseHeaders.isEmpty {
                            let sortedHeaders = entry.safeResponseHeaders
                                .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(sortedHeaders, id: \.key) { key, value in
                                    Text("\(key): \(value)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(copiedMessage)
        }
    }

    private func environmentSnapshot() -> String {
        let baseURL = DiagnosticsStore.redactedURLString(from: URL(string: effectiveBaseURL()))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let osVersion = UIDevice.current.systemVersion
        let network = networkMonitor.connectionType
        let lastFailure = lastFailureSummary()
        let lastRequest = lastRequestTime()

        return [
            "SolMobile Environment Snapshot",
            "Base URL: \(baseURL)",
            "App version: \(version) (\(build))",
            "iOS: \(osVersion)",
            "Network: \(network)",
            "Last failure: \(lastFailure)",
            "Last request: \(lastRequest)"
        ].joined(separator: "\n")
    }

    private func effectiveBaseURL() -> String {
        let raw = UserDefaults.standard.string(forKey: "solserver.baseURL") ?? "http://127.0.0.1:3333"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: trimmed) != nil {
            return trimmed
        }
        return "http://127.0.0.1:3333"
    }

    private func lastFailureSummary() -> String {
        guard let entry = store.lastFailureEntry() else { return "None" }
        var parts: [String] = ["\(entry.method) \(entry.url)"]
        if let status = entry.status {
            parts.append("HTTP \(status)")
        }
        if let latency = entry.latencyMs {
            parts.append("\(latency)ms")
        }
        if let errorDescription = entry.errorDescription {
            parts.append("Error: \(errorDescription)")
        }
        return parts.joined(separator: " — ")
    }

    private func lastRequestTime() -> String {
        guard let timestamp = store.entries.first?.timestamp else { return "Unknown" }
        return DiagnosticsView.snapshotFormatter.string(from: timestamp)
    }

    private static let snapshotFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
}
