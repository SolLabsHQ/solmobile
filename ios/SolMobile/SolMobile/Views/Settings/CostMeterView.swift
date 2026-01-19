//
//  CostMeterView.swift
//  SolMobile
//

import SwiftUI

struct CostMeterView: View {
    @ObservedObject private var budgetStore = BudgetStore.shared

    var body: some View {
        List {
            Section("Usage") {
                StatRow(label: "Usage", value: "Unavailable")
                StatRow(label: "Last Updated", value: formattedLastUpdated)
            }

            Section("Budget") {
                StatRow(label: "Status", value: budgetStatus)
                if let blockedUntil = budgetStore.state.blockedUntil {
                    StatRow(label: "Resets", value: blockedUntil.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("Cost Meter")
        .onAppear {
            budgetStore.refreshIfExpired()
        }
    }

    private var formattedLastUpdated: String {
        guard let last = budgetStore.state.lastUpdatedAt else { return "Never" }
        return last.formatted(date: .abbreviated, time: .shortened)
    }

    private var budgetStatus: String {
        budgetStore.state.isBlocked ? "Budget limit reached" : "OK"
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
