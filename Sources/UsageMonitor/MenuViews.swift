import SwiftUI

// SwiftUI views hosted inside NSMenuItems. Non-interactive; the menu
// chrome stays native (Refresh, Quit) while the data rows get real
// rendering instead of attributed-string box-drawing.

let menuContentWidth: CGFloat = 340

// MARK: - Pill progress bar

struct PillBar: View {
    let fraction: Double
    let colors: [Color]
    var height: CGFloat = 9
    var glow: Bool = false

    @State private var pulsing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(
                        colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .shadow(
                        color: glow ? (colors.last ?? .red).opacity(pulsing ? 0.9 : 0.3) : .clear,
                        radius: glow ? 6 : 0)
            }
        }
        .frame(height: height)
        .onAppear {
            guard glow else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Rate-limit bucket row

struct BucketRowView: View {
    let label: String
    let utilization: Double   // 0–100
    let detail: String?

    private var colors: [Color] {
        if utilization >= 95 { return [.red, .orange] }
        if utilization >= 80 { return [.orange, .yellow] }
        return [.green, .mint]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.1f%%", utilization))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(utilization >= 95 ? Color.red : Color.secondary)
            }
            PillBar(fraction: utilization / 100, colors: colors, glow: utilization >= 95)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(width: menuContentWidth, alignment: .leading)
    }
}

// MARK: - 30-day sparkline

struct SparklineView: View {
    let samples: [DaySample]
    let accent: [Color]

    private var maxTotal: Int64 { max(samples.map(\.total).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let isToday = index == samples.count - 1
                    let h = max(2.5, 34 * CGFloat(sample.total) / CGFloat(maxTotal))
                    Capsule()
                        .fill(isToday
                              ? AnyShapeStyle(LinearGradient(
                                    colors: accent, startPoint: .bottom, endPoint: .top))
                              : AnyShapeStyle(Color.primary.opacity(
                                    sample.total == 0 ? 0.10 : 0.35)))
                        .frame(height: h)
                        .frame(maxHeight: 34, alignment: .bottom)
                }
            }
            .frame(height: 34, alignment: .bottom)
            HStack {
                Text("last 30 days")
                Spacer()
                Text("peak \(compactTokens(maxTotal))/day")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Token composition (stacked pill)

struct CompositionBar: View {
    let breakdown: DayTokens

    private struct Slice: Identifiable {
        let id: String
        let value: Int64
        let color: Color
    }

    private var slices: [Slice] {
        [
            Slice(id: "cache read", value: breakdown.cacheRead, color: .indigo),
            Slice(id: "cache write", value: breakdown.cacheCreate, color: .blue),
            Slice(id: "output", value: breakdown.output, color: .orange),
            Slice(id: "input", value: breakdown.input, color: .green),
        ].filter { $0.value > 0 }
    }

    var body: some View {
        let total = max(breakdown.total, 1)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(slices) { slice in
                        Capsule()
                            .fill(slice.color.gradient)
                            .frame(width: max(3, geo.size.width * CGFloat(slice.value) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 3) {
                        Circle().fill(slice.color).frame(width: 5, height: 5)
                        Text("\(slice.id) \(compactTokens(slice.value))")
                    }
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Tier ladder dots

struct TierLadderView: View {
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(TierLadder.tiers.enumerated()), id: \.offset) { index, tier in
                Text(tier.emoji)
                    .font(.system(size: index == currentIndex ? 16 : 11))
                    .opacity(index == currentIndex ? 1 : index < currentIndex ? 0.7 : 0.25)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - The scoreboard card

struct TierCardView: View {
    let stats: TokenStats
    let flavor: String

    private var tierIndex: Int { TierLadder.tierIndex(for: stats.monthTokens) }
    private var tier: Tier { TierLadder.tiers[tierIndex] }
    private var nextTier: Tier? { TierLadder.next(after: tierIndex) }

    private var paceLine: String {
        let projected = stats.projectedMonthTokens
        let projectedTier = TierLadder.tier(for: projected)
        var line = "🔥 \(compactTokens(Int64(stats.dailyPace)))/day · projected \(compactTokens(projected))"
        line += " (\(projectedTier.name))"
        return line
    }

    private var comparisonLine: String? {
        guard stats.prevMonthTokens > 0 else { return nil }
        let ratio = Double(stats.monthTokens) / Double(stats.prevMonthTokens)
        if ratio >= 1 {
            return String(format: "↑ %.1f× last month's total, %d days in", ratio, stats.daysIntoMonth)
        }
        return String(format: "%.0f%% of last month so far", ratio * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Identity row
            HStack(alignment: .center, spacing: 10) {
                Text(tier.emoji)
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tier.name.uppercased())
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient(
                            colors: tier.colors, startPoint: .leading, endPoint: .trailing))
                    Text("this month")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(compactTokens(stats.monthTokens))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    Text("tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            TierLadderView(currentIndex: tierIndex)

            // Progress to next rung
            if let nextTier {
                VStack(alignment: .leading, spacing: 4) {
                    PillBar(
                        fraction: TierLadder.progressWithinTier(tokens: stats.monthTokens),
                        colors: tier.colors, height: 11)
                    HStack {
                        Text(paceLine)
                        Spacer()
                        Text("\(compactTokens(nextTier.floor - stats.monthTokens)) to \(nextTier.name) \(nextTier.emoji)")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("🏁 The ladder ends here. The tokens don't have to.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            SparklineView(samples: stats.last30, accent: tier.colors)

            CompositionBar(breakdown: stats.monthBreakdown)

            VStack(alignment: .leading, spacing: 2) {
                if let comparisonLine {
                    Text(comparisonLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("today \(compactTokens(stats.todayTokens))")
                    if let best = stats.bestDay {
                        Text("·  best day \(compactTokens(best.total))")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Text(flavor)
                .font(.system(size: 10, weight: .medium).italic())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: menuContentWidth, alignment: .leading)
    }
}

// MARK: - Extra usage row

struct ExtraUsageRowView: View {
    let extra: ExtraUsage
    let detail: String

    var body: some View {
        BucketRowView(
            label: "Extra usage (this month)",
            utilization: extra.utilization,
            detail: detail)
    }
}
