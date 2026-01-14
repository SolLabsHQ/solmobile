//
//  EvidenceView.swift
//  SolMobile
//
//  Evidence UI container (PR #8 MVP)
//

import SwiftUI

struct EvidenceView: View {
    let message: Message
    let urlOpener: URLOpening
    
    @State private var expandedCaptures: Set<String> = []
    @State private var expandedSupports: Set<String> = []
    @State private var expandedClaims: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Captures Section
            if let captures = message.captures, !captures.isEmpty {
                CapturesSection(
                    captures: captures,
                    expandedIds: $expandedCaptures,
                    urlOpener: urlOpener
                )
            }
            
            // Supports Section
            if let supports = message.supports, !supports.isEmpty {
                SupportsSection(
                    supports: supports,
                    expandedIds: $expandedSupports
                )
            }
            
            // Claims Section
            if let claims = message.claims, !claims.isEmpty {
                ClaimsSection(
                    claims: claims,
                    expandedIds: $expandedClaims
                )
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Captures Section

struct CapturesSection: View {
    let captures: [Capture]
    @Binding var expandedIds: Set<String>
    let urlOpener: URLOpening
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Captures", count: captures.count)
            
            ForEach(captures, id: \.captureId) { capture in
                CaptureCard(
                    capture: capture,
                    isExpanded: expandedIds.contains(capture.captureId),
                    urlOpener: urlOpener,
                    onToggle: {
                        if expandedIds.contains(capture.captureId) {
                            expandedIds.remove(capture.captureId)
                        } else {
                            expandedIds.insert(capture.captureId)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Supports Section

struct SupportsSection: View {
    let supports: [ClaimSupport]
    @Binding var expandedIds: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Supports", count: supports.count)
            
            ForEach(supports, id: \.supportId) { support in
                SupportCard(
                    support: support,
                    isExpanded: expandedIds.contains(support.supportId),
                    onToggle: {
                        if expandedIds.contains(support.supportId) {
                            expandedIds.remove(support.supportId)
                        } else {
                            expandedIds.insert(support.supportId)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Claims Section

struct ClaimsSection: View {
    let claims: [ClaimMapEntry]
    @Binding var expandedIds: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Claims", count: claims.count)
            
            ForEach(claims, id: \.claimId) { claim in
                ClaimCard(
                    claim: claim,
                    isExpanded: expandedIds.contains(claim.claimId),
                    onToggle: {
                        if expandedIds.contains(claim.claimId) {
                            expandedIds.remove(claim.claimId)
                        } else {
                            expandedIds.insert(claim.claimId)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Capture Card

struct CaptureCard: View {
    let capture: Capture
    let isExpanded: Bool
    let urlOpener: URLOpening
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SourceBadge(source: capture.source)
                    
                    Text(truncatedURL)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(capture.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button(action: { urlOpener.open(capture.url) }) {
                        Label("Open in Safari", systemImage: "safari")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.leading, 24)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var truncatedURL: String {
        if capture.url.count > 50 {
            return String(capture.url.prefix(47)) + "..."
        }
        return capture.url
    }
}

// MARK: - Support Card

struct SupportCard: View {
    let support: ClaimSupport
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TypeBadge(type: support.type)
                    
                    Text(previewText)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if support.type == "url_capture", let captureId = support.captureId {
                        Text("Capture: \(captureId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if support.type == "text_snippet", let snippetText = support.snippetText {
                        Text(snippetText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var previewText: String {
        if support.type == "url_capture" {
            return "URL Capture"
        } else if let snippetText = support.snippetText {
            return snippetText.count > 50 ? String(snippetText.prefix(47)) + "..." : snippetText
        }
        return "Support"
    }
}

// MARK: - Claim Card

struct ClaimCard: View {
    let claim: ClaimMapEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(previewText)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(claim.claimText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    if !claim.supportIds.isEmpty {
                        Text("Supports: \(claim.supportIds.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var previewText: String {
        claim.claimText.count > 50 ? String(claim.claimText.prefix(47)) + "..." : claim.claimText
    }
}

// MARK: - Badges

struct SourceBadge: View {
    let source: String
    
    var body: some View {
        Text(source == "user_provided" ? "User" : "Auto")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(source == "user_provided" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
            .foregroundColor(source == "user_provided" ? .blue : .green)
            .cornerRadius(4)
    }
}

struct TypeBadge: View {
    let type: String
    
    var body: some View {
        Text(type == "url_capture" ? "URL" : "Text")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type == "url_capture" ? Color.purple.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundColor(type == "url_capture" ? .purple : .orange)
            .cornerRadius(4)
    }
}

// MARK: - URL Opening Protocol

protocol URLOpening {
    func open(_ urlString: String)
}

struct SystemURLOpener: URLOpening {
    func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
