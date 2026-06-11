import Foundation

/// Token totals for one local-time day.
struct DayTokens: Codable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheCreate: Int64 = 0
    var cacheRead: Int64 = 0

    var total: Int64 { input + output + cacheCreate + cacheRead }

    mutating func add(_ other: DayTokens) {
        input += other.input
        output += other.output
        cacheCreate += other.cacheCreate
        cacheRead += other.cacheRead
    }
}

struct DaySample {
    let date: Date
    let dayKey: String
    let total: Int64
}

/// Everything the UI needs about local token consumption, precomputed.
struct TokenStats {
    let monthTokens: Int64
    let monthBreakdown: DayTokens
    let prevMonthTokens: Int64
    let todayTokens: Int64
    let bestDay: DaySample?
    let last30: [DaySample]
    let daysIntoMonth: Int
    let daysInMonth: Int
    let fetchedAt: Date

    var dailyPace: Double {
        guard daysIntoMonth > 0 else { return 0 }
        return Double(monthTokens) / Double(daysIntoMonth)
    }

    var projectedMonthTokens: Int64 {
        Int64(dailyPace * Double(daysInMonth))
    }
}

/// Reads token usage out of Claude Code's local transcripts
/// (~/.claude/projects/**/*.jsonl). Each assistant message carries a
/// `usage` block; we count all four categories — input, output, cache
/// creation, cache read — because tokens are tokens and the scoreboard
/// respects volume.
///
/// A per-file (size, mtime) cache means only new/changed transcripts are
/// re-parsed after the first scan. Messages are deduped globally on
/// message.id + requestId since forked/resumed sessions duplicate history
/// across files.
enum TokenLedger {
    private struct MsgEntry: Codable {
        let k: String   // dedupe key ("" when message has no ids)
        let d: String   // local day "yyyy-MM-dd"
        let i: Int64    // input
        let o: Int64    // output
        let cc: Int64   // cache creation
        let cr: Int64   // cache read
    }

    private struct FileCache: Codable {
        let size: Int64
        let mtime: Double
        let entries: [MsgEntry]
    }

    private struct CacheRoot: Codable {
        var files: [String: FileCache] = [:]
    }

    private static let projectsPath = NSHomeDirectory() + "/.claude/projects"

    private static var cachePath: String {
        let dir = NSHomeDirectory() + "/Library/Application Support/UsageMonitor"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        return dir + "/token-ledger.json"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction = ISO8601DateFormatter()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Scans transcripts and returns aggregated stats, or nil when there is
    /// no ~/.claude/projects directory. Heavy on first run; cheap after.
    static func collect() -> TokenStats? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsPath) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now))!
        let startOfPrevMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth)!
        // Anything in the sparkline or month comparisons lives after this.
        let cutoff = min(
            startOfPrevMonth,
            calendar.date(byAdding: .day, value: -30, to: now)!
        ).timeIntervalSince1970

        var cache = loadCache()
        var dirty = false
        var livePaths = Set<String>()

        if let enumerator = fm.enumerator(atPath: projectsPath) {
            while let rel = enumerator.nextObject() as? String {
                guard rel.hasSuffix(".jsonl") else { continue }
                let path = projectsPath + "/" + rel
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = (attrs[.size] as? NSNumber)?.int64Value,
                      let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
                else { continue }
                // A file last written before the window can't contain
                // entries inside it.
                if mtime < cutoff { continue }
                livePaths.insert(path)
                if let cached = cache.files[path],
                   cached.size == size, cached.mtime == mtime { continue }
                cache.files[path] = FileCache(
                    size: size, mtime: mtime,
                    entries: parseFile(path, cutoff: cutoff))
                dirty = true
            }
        }
        for stale in cache.files.keys where !livePaths.contains(stale) {
            cache.files.removeValue(forKey: stale)
            dirty = true
        }
        if dirty { saveCache(cache) }

        // Aggregate with global dedupe across files.
        var seen = Set<String>()
        var days: [String: DayTokens] = [:]
        for file in cache.files.values {
            for e in file.entries {
                if !e.k.isEmpty {
                    if !seen.insert(e.k).inserted { continue }
                }
                days[e.d, default: DayTokens()].add(
                    DayTokens(input: e.i, output: e.o, cacheCreate: e.cc, cacheRead: e.cr))
            }
        }

        let monthPrefix = String(dayFormatter.string(from: now).prefix(7))
        let prevMonthPrefix = String(dayFormatter.string(from: startOfPrevMonth).prefix(7))

        var monthBreakdown = DayTokens()
        var prevMonthTokens: Int64 = 0
        var bestDay: DaySample?
        for (key, tokens) in days {
            if key.hasPrefix(monthPrefix) {
                monthBreakdown.add(tokens)
                if tokens.total > (bestDay?.total ?? 0),
                   let date = dayFormatter.date(from: key) {
                    bestDay = DaySample(date: date, dayKey: key, total: tokens.total)
                }
            } else if key.hasPrefix(prevMonthPrefix) {
                prevMonthTokens += tokens.total
            }
        }

        var last30: [DaySample] = []
        for offset in stride(from: 29, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            let key = dayFormatter.string(from: date)
            last30.append(DaySample(
                date: date, dayKey: key, total: days[key]?.total ?? 0))
        }

        let todayKey = dayFormatter.string(from: now)
        return TokenStats(
            monthTokens: monthBreakdown.total,
            monthBreakdown: monthBreakdown,
            prevMonthTokens: prevMonthTokens,
            todayTokens: days[todayKey]?.total ?? 0,
            bestDay: bestDay,
            last30: last30,
            daysIntoMonth: calendar.component(.day, from: now),
            daysInMonth: calendar.range(of: .day, in: .month, for: now)!.count,
            fetchedAt: now
        )
    }

    // MARK: - Parsing

    private static func parseFile(_ path: String, cutoff: TimeInterval) -> [MsgEntry] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        var entries: [MsgEntry] = []
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            // Cheap precheck before paying for JSON decoding.
            guard line.contains("\"usage\""),
                  line.contains("\"type\":\"assistant\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let raw = obj["timestamp"] as? String,
                  let date = isoFormatter.date(from: raw) ?? isoNoFraction.date(from: raw),
                  date.timeIntervalSince1970 >= cutoff
            else { continue }

            let msgId = msg["id"] as? String ?? ""
            let reqId = obj["requestId"] as? String ?? ""
            let key = (msgId.isEmpty && reqId.isEmpty) ? "" : msgId + ":" + reqId
            func count(_ field: String) -> Int64 {
                (usage[field] as? NSNumber)?.int64Value ?? 0
            }
            entries.append(MsgEntry(
                k: key,
                d: dayFormatter.string(from: date),
                i: count("input_tokens"),
                o: count("output_tokens"),
                cc: count("cache_creation_input_tokens"),
                cr: count("cache_read_input_tokens")
            ))
        }
        return entries
    }

    // MARK: - Cache persistence

    private static func loadCache() -> CacheRoot {
        guard let data = FileManager.default.contents(atPath: cachePath),
              let cache = try? JSONDecoder().decode(CacheRoot.self, from: data)
        else { return CacheRoot() }
        return cache
    }

    private static func saveCache(_ cache: CacheRoot) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
    }
}

/// "1,234" / "56.7K" / "247.3M" / "1.24B" — the scoreboard dialect.
func compactTokens(_ n: Int64) -> String {
    let v = Double(n)
    switch v {
    case ..<1_000: return "\(n)"
    case ..<1_000_000: return trimmed(v / 1_000, 1) + "K"
    case ..<1_000_000_000: return trimmed(v / 1_000_000, 1) + "M"
    default: return trimmed(v / 1_000_000_000, 2) + "B"
    }
}

private func trimmed(_ value: Double, _ places: Int) -> String {
    var s = String(format: "%.\(places)f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
