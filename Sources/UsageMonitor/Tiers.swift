import SwiftUI

/// One rung of the company token-usage scoreboard. The middle three are
/// real (per the scoreboard); the rest are extrapolated with confidence.
struct Tier {
    let name: String
    let emoji: String
    let floor: Int64
    let colors: [Color]
    let flavor: [String]
    let promotionLine: String

    func randomFlavor() -> String {
        flavor.randomElement() ?? ""
    }
}

enum TierLadder {
    static let tiers: [Tier] = [
        Tier(
            name: "Token Tourist",
            emoji: "🚶",
            floor: 0,
            colors: [Color.gray, Color.gray.opacity(0.6)],
            flavor: [
                "Your entire month fits in one context window.",
                "Have you tried asking it anything?",
                "The scoreboard cannot see you yet.",
            ],
            promotionLine: "Technically on the board."
        ),
        Tier(
            name: "AI Curious",
            emoji: "👀",
            floor: 1_000_000,
            colors: [Color.teal, Color.cyan],
            flavor: [
                "You've heard of agents. You're pretty sure you haven't met one.",
                "A million tokens. The model remembers you. Barely.",
                "Dipping a toe into the inference ocean.",
            ],
            promotionLine: "Seven figures. The journey begins."
        ),
        Tier(
            name: "AI Adopter",
            emoji: "🌱",
            floor: 10_000_000,
            colors: [Color.green, Color.mint],
            flavor: [
                "Officially scoreboard-visible. The intern tier.",
                "Eight figures of tokens and a dream.",
                "You adopt AI. AI has not yet adopted you.",
            ],
            promotionLine: "Welcome to the official scoreboard."
        ),
        Tier(
            name: "Deeply Connected",
            emoji: "🔌",
            floor: 100_000_000,
            colors: [Color.blue, Color.purple],
            flavor: [
                "You and the model finish each other's sentences. Mostly it finishes yours.",
                "Nine figures. Your standup updates are co-authored now.",
                "The cache knows your codebase better than you do.",
            ],
            promotionLine: "The plug is in. You are the plug."
        ),
        Tier(
            name: "Agentic",
            emoji: "🤖",
            floor: 1_000_000_000,
            colors: [Color.orange, Color.pink],
            flavor: [
                "You don't write code. You emit intent.",
                "A billion tokens. HR has questions. The scoreboard has answers.",
                "Your subagents have subagents.",
            ],
            promotionLine: "ONE BILLION TOKENS. You are the workflow now."
        ),
        Tier(
            name: "Post-Scarcity",
            emoji: "🌌",
            floor: 10_000_000_000,
            colors: [Color.purple, Color.pink, Color.yellow],
            flavor: [
                "The scoreboard has no name for this. We made one up.",
                "Ten billion tokens. Somewhere, a datacenter hums your name.",
                "At this point you may legally claim the GPUs as dependents.",
            ],
            promotionLine: "Beyond the scoreboard. Beyond reason."
        ),
    ]

    static func tierIndex(for tokens: Int64) -> Int {
        var index = 0
        for (i, tier) in tiers.enumerated() where tokens >= tier.floor {
            index = i
        }
        return index
    }

    static func tier(for tokens: Int64) -> Tier {
        tiers[tierIndex(for: tokens)]
    }

    static func next(after index: Int) -> Tier? {
        index + 1 < tiers.count ? tiers[index + 1] : nil
    }

    /// 0…1 progress through the current tier toward the next floor.
    static func progressWithinTier(tokens: Int64) -> Double {
        let index = tierIndex(for: tokens)
        let floor = tiers[index].floor
        guard let next = next(after: index) else { return 1 }
        let span = Double(next.floor - floor)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(tokens - floor) / span))
    }
}
