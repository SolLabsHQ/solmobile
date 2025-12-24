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
    @AppStorage("solserver.baseURL") private var solserverBaseURL: String = "http://127.0.0.1:3333"

    // Light tracing for debugging (non-sensitive)
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "Settings")

    // Normalize and validate the URL string the user types
    private var trimmedBaseURL: String {
        solserverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidBaseURL: Bool {
        URL(string: trimmedBaseURL) != nil
    }

    private var effectiveBaseURL: String {
        isValidBaseURL ? trimmedBaseURL : "http://127.0.0.1:3333"
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


                Section("Developer") {
                    TextField("SolServer base URL", text: $solserverBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

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
                            solserverBaseURL = "http://127.0.0.1:3333"
                        } label: {
                            Label("Simulator", systemImage: "laptopcomputer")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            // Replace with your Mac’s LAN IP (same Wi‑Fi) once you’re ready.
                            solserverBaseURL = "http://192.168.0.10:3333"
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

                    if !isValidBaseURL {
                        Text("Invalid URL. Example: http://127.0.0.1:3333")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .onChange(of: solserverBaseURL) { _, newValue in
                    let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    log.info("[baseURL] changed -> \(v, privacy: .public)")
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
            }
            .navigationTitle("Settings")
        }
    }

}
