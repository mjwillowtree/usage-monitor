import Foundation
import Security

/// One usage bucket from the OAuth usage endpoint (session, weekly, promotional, …).
struct UsageBucket {
    let key: String
    let utilization: Double
    let resetsAt: Date?

    var label: String {
        switch key {
        case "five_hour": return "Current session"
        case "seven_day": return "Current week (all models)"
        case "seven_day_opus": return "Current week (Opus)"
        case "seven_day_sonnet": return "Current week (Sonnet)"
        case "seven_day_oauth_apps": return "Current week (OAuth apps)"
        case "seven_day_cowork": return "Current week (Cowork)"
        case "omelette_promotional": return "Promotional credits"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// The pay-as-you-go monthly bucket, denominated in cents.
struct ExtraUsage {
    let isEnabled: Bool
    let monthlyLimitCents: Double
    let usedCents: Double
    let utilization: Double
    let currency: String
}

struct UsageSnapshot {
    let buckets: [UsageBucket]
    let extraUsage: ExtraUsage?
    let fetchedAt: Date

    /// The number shown in the menu bar: monthly extra usage when enabled,
    /// otherwise the most-constrained rate-limit bucket.
    var headlinePercent: Double? {
        if let extra = extraUsage, extra.isEnabled {
            return extra.utilization
        }
        return buckets.map(\.utilization).max()
    }
}

enum UsageError: Error, LocalizedError {
    case noCredentials
    case tokenExpired
    case httpError(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "No Claude Code credentials in Keychain"
        case .tokenExpired: return "Token expired — open Claude Code to refresh it"
        case .httpError(let code): return "Usage API returned HTTP \(code)"
        case .badResponse: return "Could not parse usage API response"
        }
    }
}

enum UsageClient {
    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Reads the OAuth access token Claude Code keeps in the login Keychain.
    /// Claude Code owns the refresh flow; if the token is stale we surface
    /// that instead of touching the credential.
    private static func accessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else {
            throw UsageError.noCredentials
        }
        if let expiresAt = oauth["expiresAt"] as? Double,
           Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
            throw UsageError.tokenExpired
        }
        return token
    }

    static func fetch() async throws -> UsageSnapshot {
        let token = try accessToken()
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        if http.statusCode == 401 { throw UsageError.tokenExpired }
        guard http.statusCode == 200 else { throw UsageError.httpError(http.statusCode) }
        return try parse(data)
    }

    /// Buckets are discovered dynamically (any object with a "utilization"
    /// field) so new limit types appearing in the API show up without a
    /// code change.
    static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.badResponse
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()

        var buckets: [UsageBucket] = []
        var extra: ExtraUsage?

        for (key, value) in root {
            guard let obj = value as? [String: Any] else { continue }
            if key == "extra_usage" {
                extra = ExtraUsage(
                    isEnabled: obj["is_enabled"] as? Bool ?? false,
                    monthlyLimitCents: obj["monthly_limit"] as? Double ?? 0,
                    usedCents: obj["used_credits"] as? Double ?? 0,
                    utilization: obj["utilization"] as? Double ?? 0,
                    currency: obj["currency"] as? String ?? "USD"
                )
            } else if let utilization = obj["utilization"] as? Double {
                var resetsAt: Date?
                if let raw = obj["resets_at"] as? String {
                    resetsAt = iso.date(from: raw) ?? isoNoFraction.date(from: raw)
                }
                buckets.append(UsageBucket(key: key, utilization: utilization, resetsAt: resetsAt))
            }
        }

        buckets.sort { $0.utilization > $1.utilization }
        return UsageSnapshot(buckets: buckets, extraUsage: extra, fetchedAt: Date())
    }
}
