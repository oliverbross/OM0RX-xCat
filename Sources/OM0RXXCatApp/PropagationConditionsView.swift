// Copyright © 2026 Oliver Bross OM0RX
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCatCore

struct PropagationConditionsView: View {
    @EnvironmentObject private var model: AppModel

    private let cyan = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let green = Color(red: 0.43, green: 0.91, blue: 0.72)
    private let amber = Color(red: 0.99, green: 0.79, blue: 0.39)
    private let coral = Color(red: 1.0, green: 0.45, blue: 0.40)
    private let violet = Color(red: 0.75, green: 0.35, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let conditions = model.propagationConditions {
                conditionsGrid(conditions)
                sourceLine(conditions)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.035, green: 0.09, blue: 0.14))
        .overlay(alignment: .top) {
            Rectangle().fill(cyan.opacity(0.18)).frame(height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("HF PROPAGATION")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(cyan)
            if let conditions = model.propagationConditions {
                Text(summary(conditions))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)
                .shadow(color: statusTint.opacity(0.55), radius: 3, y: 1)
            Text(model.propagationStatus)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(statusTint)
            Button {
                model.refreshPropagationConditions()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(cyan.opacity(0.78))
            .disabled(model.propagationIsRefreshing)
            .help("Refresh HF propagation conditions")
            .accessibilityLabel("Refresh HF propagation conditions")
        }
    }

    private func conditionsGrid(_ conditions: PropagationConditionsSnapshot) -> some View {
        let bands = conditions.displayBands
        return Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("")
                    .frame(width: 38)
                ForEach(bands) { band in
                    Text(band.name)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(cyan.opacity(0.72))
                        .frame(width: 82)
                }
            }
            ratingRow("DAY", ratings: bands.map(\.day))
            ratingRow("NIGHT", ratings: bands.map(\.night))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("HF band conditions by day and night")
    }

    private func ratingRow(_ label: String, ratings: [PropagationRating]) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            ForEach(Array(ratings.enumerated()), id: \.offset) { _, rating in
                Text(rating.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(ratingTint(rating))
                    .frame(width: 82, height: 17)
                    .background(ratingTint(rating).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func sourceLine(_ conditions: PropagationConditionsSnapshot) -> some View {
        HStack(spacing: 5) {
            Text("N0NBH / NOAA")
            if let updatedAt = conditions.updatedAt {
                Text("·")
                Text("updated \(Self.utcFormatter.string(from: updatedAt)) UTC")
            }
            Spacer()
            Text("Europe 6m")
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(cyan.opacity(0.52))
        .lineLimit(1)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if model.propagationIsRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(amber)
            }
            Text(model.propagationStatus == "OFFLINE"
                 ? "Solar data is unavailable. The station monitor remains fully operational."
                 : "Loading current solar and geomagnetic conditions…")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(cyan.opacity(0.72))
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var statusTint: Color {
        switch model.propagationStatus {
        case "LIVE": green
        case "STALE": amber
        case "OFFLINE": coral
        default: cyan.opacity(0.72)
        }
    }

    private func summary(_ conditions: PropagationConditionsSnapshot) -> String {
        let sfi = conditions.solarFlux.map(String.init) ?? "--"
        let a = conditions.aIndex.map(String.init) ?? "--"
        let k = conditions.kIndex.map(String.init) ?? "--"
        let x = conditions.xRay.isEmpty ? "--" : conditions.xRay
        return "SFI \(sfi)  A \(a)  K \(k)  X \(x)"
    }

    private func ratingTint(_ rating: PropagationRating) -> Color {
        switch rating {
        case .good: green
        case .fair: amber
        case .poor: coral
        case .closed: violet.opacity(0.86)
        case .unknown: .secondary
        }
    }

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
