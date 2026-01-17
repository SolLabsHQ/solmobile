//
//  EvidenceClaimsSheet.swift
//  SolMobile
//
//  Minimal claims viewer for OutputEnvelope meta.claims (PR #23)
//

import SwiftUI

struct EvidenceClaimsSheet: View {
    let message: Message

    var body: some View {
        NavigationStack {
            List {
                if message.claimsTruncated {
                    Section {
                        Text("Claims were too large to store on device.")
                            .foregroundStyle(.secondary)
                    }
                }

                if claims.isEmpty {
                    Section {
                        Text("No claims available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(claims.enumerated()), id: \.offset) { index, claim in
                        Section("Claim \(index + 1)") {
                            Text(claim.claimText)

                            if !claim.evidenceRefs.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Evidence refs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(claim.evidenceRefs.indices, id: \.self) { i in
                                        Text(renderEvidenceRef(claim.evidenceRefs[i]))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Evidence Claims")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var claims: [OutputEnvelopeClaimDTO] {
        guard let data = message.claimsJson else { return [] }
        return (try? JSONDecoder().decode([OutputEnvelopeClaimDTO].self, from: data)) ?? []
    }

    private func renderEvidenceRef(_ ref: OutputEnvelopeEvidenceRefDTO) -> String {
        if let spanId = ref.spanId, !spanId.isEmpty {
            return "\(ref.evidenceId):\(spanId)"
        }
        return ref.evidenceId
    }
}
