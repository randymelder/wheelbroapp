// OBDValueCard.swift
// Reusable dark card for displaying a single live OBD telemetry value.

import SwiftUI

struct OBDValueCard: View {
    let title: String
    let value: String
    let unit:  String
    let icon:  String              // SF Symbol name

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Header row: icon + label ─────────────────────────────────
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color.wheelBroYellow)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Value + unit ─────────────────────────────────────────────
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wheelBroYellow.opacity(0.18), lineWidth: 1)
        }
    }
}

// MARK: - Preview
#Preview {
    HStack {
        OBDValueCard(title: "RPM",   value: "1450",  unit: "",    icon: "gauge.with.needle")
        OBDValueCard(title: "Speed", value: "42",    unit: "mph", icon: "speedometer")
    }
    .padding()
    .background(Color.black)
}
