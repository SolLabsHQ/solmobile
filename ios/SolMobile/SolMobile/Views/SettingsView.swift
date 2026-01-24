//
//  SettingsView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/23/25.
//
import SwiftUI
import os

struct SettingsView: View {
    // Persisted dev knob (UserDefaults via @AppStorage)
    @AppStorage(SolServerBaseURL.storageKey) private var solserverBaseURL: String = SolServerBaseURL.defaultBaseURLString
    @AppStorage(JournalStyleSettings.offersEnabledKey) private var journalOffersEnabled: Bool = true
    @AppStorage(JournalStyleSettings.cooldownMinutesKey) private var journalCooldownMinutes: Int = 60
    @AppStorage(JournalStyleSettings.avoidPeakOverwhelmKey) private var journalAvoidPeakOverwhelm: Bool = true
    @AppStorage(JournalStyleSettings.defaultModeKey) private var journalDefaultMode: String = JournalDraftMode.assist.rawValue
    @AppStorage(JournalStyleSettings.maxLinesDefaultKey) private var journalMaxLinesDefault: Int = 12
    @AppStorage(JournalStyleSettings.toneNotesKey) private var journalToneNotes: String = "Warm, grounded, concise."
    @AppStorage(JournalStyleSettings.cpbIdKey) private var journalCpbId: String = ""
    @AppStorage(AppleIntelligenceSettings.enabledKey) private var appleIntelligenceEnabled: Bool = false

    // Light tracing for debugging (non-sensitive)
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "Settings")

    @State private var stagingApiKey: String = ""
    @State private var stagingKeyStatus: String = "No key set"
    @State private var stagingKeyError: String? = nil
    @FocusState private var stagingKeyFocused: Bool

    // Use seconds for dev ergonomics (makes retries/latency easier to reason about).
    private static let timeWithSecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private func formatTimeWithSeconds(_ d: Date) -> String {
        Self.timeWithSecondsFormatter.string(from: d)
    }

    private func snippet(_ text: String, limit: Int = 400) -> String {
        guard text.count > limit else { return text }
        let idx = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<idx])
    }

    // Last chat transport status (written by TransmissionAction/Transport).
    private let lastChatStatusCodeKey = "sol.dev.lastChatStatusCode"
    private let lastChatStatusAtKey = "sol.dev.lastChatStatusAt"
    private let lastChatURLKey = "sol.dev.lastChatURL"
    private let lastChatMethodKey = "sol.dev.lastChatMethod"

    private var lastChatStatusCode: Int? {
        UserDefaults.standard.object(forKey: lastChatStatusCodeKey) as? Int
    }

    private var lastChatStatusAt: Date? {
        let t = UserDefaults.standard.double(forKey: lastChatStatusAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private var lastChatURL: String? {
        UserDefaults.standard.string(forKey: lastChatURLKey)
    }

    private var lastChatMethod: String? {
        UserDefaults.standard.string(forKey: lastChatMethodKey)
    }

    // Connection test state (dev ergonomics)
    @State private var isTestingConnection: Bool = false
    @State private var lastHealthCheck: String? = nil
    @State private var lastHealthCheckError: String? = nil
    @State private var lastHealthCheckAt: Date? = nil
    @State private var healthTask: Task<Void, Never>? = nil

    // Normalize and validate the URL string the user types
    private var trimmedBaseURL: String {
        solserverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidBaseURL: Bool {
        URL(string: trimmedBaseURL) != nil
    }

    private var overrideBaseURL: String {
        trimmedBaseURL.isEmpty ? "(none)" : trimmedBaseURL
    }

    private var effectiveBaseURL: String {
        SolServerBaseURL.effectiveURLString()
    }

    private var healthzURL: URL? {
        guard let base = URL(string: effectiveBaseURL) else { return nil }
        return base.appendingPathComponent("healthz")
    }

    private func runHealthCheck() {
        // Cancel any in-flight test to avoid races in UI updates
        healthTask?.cancel()

        guard let url = healthzURL else {
            lastHealthCheck = nil
            lastHealthCheckError = "Invalid base URL"
            return
        }

        isTestingConnection = true
        lastHealthCheck = nil
        lastHealthCheckError = nil

        let started = Date()
        log.info("[healthz] start url=\(url.absoluteString, privacy: .public)")

        healthTask = Task {
            // A couple quick retries helps with transient local network flakiness.
            let backoffsNs: [UInt64] = [0, 250_000_000, 750_000_000]

            for attempt in 1...backoffsNs.count {
                if Task.isCancelled { return }

                let backoff = backoffsNs[attempt - 1]
                if backoff > 0 {
                    try? await Task.sleep(nanoseconds: backoff)
                }

                do {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.timeoutInterval = 4
                    req.cachePolicy = .reloadIgnoringLocalCacheData
                    req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let body = snippet(String(data: data, encoding: .utf8) ?? "")

                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    DiagnosticsStore.shared.record(
                        method: "GET",
                        url: url,
                        responseURL: (resp as? HTTPURLResponse)?.url,
                        redirectChain: [],
                        status: status,
                        latencyMs: ms,
                        retryableInferred: nil,
                        retryableSource: nil,
                        parsedErrorCode: nil,
                        traceRunId: nil,
                        attemptId: nil,
                        threadId: nil,
                        localTransmissionId: nil,
                        transmissionId: nil,
                        error: nil,
                        responseData: data,
                        responseHeaders: (resp as? HTTPURLResponse)?.allHeaderFields,
                        requestHeaders: req.allHTTPHeaderFields,
                        requestBody: req.httpBody,
                        hadAuthorization: false
                    )

                    if HealthCheckPolicy.isSuccess(status: status) {
                        await MainActor.run {
                            isTestingConnection = false
                            lastHealthCheckError = nil
                            lastHealthCheck = "GET \(url.absoluteString) — HTTP \(status) — \(ms)ms"
                            lastHealthCheckAt = Date()
                        }

                        log.info("[healthz] ok status=\(status, privacy: .public) attempt=\(attempt, privacy: .public) ms=\(ms, privacy: .public)")
                        return
                    } else {
                        log.warning("[healthz] non-200 status=\(status, privacy: .public) attempt=\(attempt, privacy: .public)")

                        // If it's the last attempt, surface the error.
                        if attempt == backoffsNs.count {
                            await MainActor.run {
                                isTestingConnection = false
                                lastHealthCheck = nil
                                lastHealthCheckError = "GET \(url.absoluteString) — HTTP \(status) — \(ms)ms. \(body)"
                                lastHealthCheckAt = Date()
                            }
                            return
                        }
                    }
                } catch {
                    log.error("[healthz] error attempt=\(attempt, privacy: .public) err=\(String(describing: error), privacy: .public)")

                    if attempt == backoffsNs.count {
                        let ms = Int(Date().timeIntervalSince(started) * 1000)
                        DiagnosticsStore.shared.record(
                            method: "GET",
                            url: url,
                            responseURL: nil,
                            redirectChain: [],
                            status: nil,
                            latencyMs: ms,
                            retryableInferred: nil,
                            retryableSource: nil,
                            parsedErrorCode: nil,
                            traceRunId: nil,
                            attemptId: nil,
                            threadId: nil,
                            localTransmissionId: nil,
                            transmissionId: nil,
                            error: error,
                            responseData: nil,
                            responseHeaders: nil,
                            requestHeaders: nil,
                            requestBody: nil,
                            hadAuthorization: false
                        )
                        await MainActor.run {
                            isTestingConnection = false
                            lastHealthCheck = nil
                            lastHealthCheckError = "GET \(url.absoluteString) — error. \(String(describing: error))"
                            lastHealthCheckAt = Date()
                        }
                        return
                    }
                }
            }

            await MainActor.run {
                isTestingConnection = false
            }
        }
    }

    private func loadStagingApiKey() {
        if let key = KeychainStore.read(key: KeychainKeys.stagingApiKey), !key.isEmpty {
            stagingApiKey = key
            stagingKeyStatus = "Key saved"
            stagingKeyError = nil
        } else {
            stagingApiKey = ""
            stagingKeyStatus = "No key set"
            stagingKeyError = nil
        }
    }

    private func persistStagingApiKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if KeychainStore.delete(key: KeychainKeys.stagingApiKey) {
                stagingKeyStatus = "No key set"
                stagingKeyError = nil
            } else {
                stagingKeyStatus = "Save failed"
                stagingKeyError = "Unable to clear key"
            }
            return
        }

        if KeychainStore.write(trimmed, key: KeychainKeys.stagingApiKey) {
            stagingKeyStatus = "Key saved"
            stagingKeyError = nil
        } else {
            stagingKeyStatus = "Save failed"
            stagingKeyError = "Unable to save key"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SolMobile Settings")
                            .font(.headline)

                        Text("Developer knobs are for local testing (simulator/phone) and should be set to a SolServer URL you control.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Staging") {
                    SecureField("Staging API Key", text: $stagingApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($stagingKeyFocused)
                        .onSubmit {
                            persistStagingApiKey(stagingApiKey)
                        }
                        .onChange(of: stagingKeyFocused) { _, focused in
                            if !focused {
                                persistStagingApiKey(stagingApiKey)
                            }
                        }

                    Text("Replace this key anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Status")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(stagingKeyStatus)
                            .foregroundStyle(.secondary)
                    }

                    if let stagingKeyError {
                        Text(stagingKeyError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Clear key", role: .destructive) {
                        stagingApiKey = ""
                        persistStagingApiKey("")
                    }
                }

                Section("Developer") {
                    TextField("SolServer base URL", text: $solserverBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        Text("Override")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(overrideBaseURL)
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // Show what the app will actually use (helps when the field is invalid)
                    HStack {
                        Text("Effective")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(effectiveBaseURL)
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // Presets: vertical to avoid Form/HStack hit-target weirdness
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            solserverBaseURL = "https://solserver-staging.sollabshq.com"
                        } label: {
                            Label("Staging", systemImage: "network")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            solserverBaseURL = "https://api.sollabshq.com"
                        } label: {
                            Label("Production", systemImage: "globe")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            solserverBaseURL = "http://127.0.0.1:3333"
                        } label: {
                            Label("Simulator", systemImage: "laptopcomputer")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            // Replace with your Mac’s LAN IP (same Wi‑Fi) once you’re ready.
                            solserverBaseURL = "http://192.168.50.240:3333"
                        } label: {
                            Label("Phone (LAN)", systemImage: "iphone")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(role: .destructive) {
                            solserverBaseURL = "http://127.0.0.1:3333"
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            runHealthCheck()
                        } label: {
                            Label(isTestingConnection ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTestingConnection)

                        if let ok = lastHealthCheck {
                            Text(ok)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let err = lastHealthCheckError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let at = lastHealthCheckAt {
                            Text("Last checked: \(formatTimeWithSeconds(at))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let code = lastChatStatusCode {
                            let method = lastChatMethod ?? "POST"
                            let url = lastChatURL ?? "(unknown url)"
                            if let at = lastChatStatusAt {
                                Text("Last chat: \(method) \(url) — HTTP \(code) @ \(formatTimeWithSeconds(at))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            } else {
                                Text("Last chat: \(method) \(url) — HTTP \(code)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }

                        Text("Tip: Simulator can use 127.0.0.1. A physical phone must use your Mac’s LAN IP on the same Wi‑Fi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !isValidBaseURL {
                        Text("Invalid URL. Example: http://127.0.0.1:3333")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .onChange(of: solserverBaseURL) { _, newValue in
                    let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    log.info("[baseURL] changed -> \(v, privacy: .public)")

                    // Reset health state so we don't show stale results for a new URL.
                    lastHealthCheck = nil
                    lastHealthCheckError = nil
                    lastHealthCheckAt = nil
                }

                Section("Journaling") {
                    Toggle("Journal offers enabled", isOn: $journalOffersEnabled)

                    Stepper(value: $journalCooldownMinutes, in: 0...1440, step: 15) {
                        Text("Cooldown \(journalCooldownMinutes) min")
                    }

                    Toggle("Avoid peak overwhelm", isOn: $journalAvoidPeakOverwhelm)

                    Picker("Default mode", selection: $journalDefaultMode) {
                        ForEach(JournalDraftMode.allCases, id: \.rawValue) { mode in
                            Text(mode.rawValue.capitalized).tag(mode.rawValue)
                        }
                    }

                    Stepper(value: $journalMaxLinesDefault, in: 1...50, step: 1) {
                        Text("Max lines \(journalMaxLinesDefault)")
                    }

                    TextField("Tone notes", text: $journalToneNotes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)

                    TextField("Journal style CPB ID (optional)", text: $journalCpbId)

                    Text("Cooldown applies to new offers. Tone notes are used for assist drafts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Intelligence") {
                    Toggle("Device hints (trace only)", isOn: $appleIntelligenceEnabled)
                    Text("Runs in background and sends mechanism-only hints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data Management") {
                    NavigationLink(destination: MemoryVaultView()) {
                        Label("Memory Vault", systemImage: "brain")
                    }
                    NavigationLink(destination: StorageAuditView()) {
                        Label("Storage Audit", systemImage: "tray.full")
                    }
                    Text("Review local storage counts and run TTL cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Cost") {
                    NavigationLink(destination: CostMeterView()) {
                        Label("Cost Meter", systemImage: "creditcard")
                    }
                    Text("Usage is unavailable until the server reports budget data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Diagnostics") {
                    NavigationLink(destination: DiagnosticsView()) {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    Text("Share redacted request/response diagnostics for the last 50 calls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadStagingApiKey()
            }
        }
    }

}
