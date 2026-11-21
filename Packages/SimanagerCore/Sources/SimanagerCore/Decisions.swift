import Foundation

public enum SimAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case shutdown, delete
    public var id: String { rawValue }
}

public struct ReapSettings: Hashable, Sendable {
    public var enabled: Bool
    public var idlePeriod: TimeInterval
    public var action: SimAction
    public init(enabled: Bool, idlePeriod: TimeInterval, action: SimAction) {
        self.enabled = enabled; self.idlePeriod = idlePeriod; self.action = action
    }
    public static let idlePeriods: [TimeInterval] = [900, 1800, 3600, 7200]
    public static let `default` = ReapSettings(enabled: true, idlePeriod: 1800, action: .shutdown)
}

/// How long each simulator has gone without a live owner, as seen by this run of the app.
public struct ReapClock: Sendable {
    private let refreshInterval: TimeInterval
    private var lastObserved: Date?
    public private(set) var idleSince: [String: Date] = [:]

    public init(refreshInterval: TimeInterval = 5) { self.refreshInterval = refreshInterval }

    public mutating func observe(_ snapshot: Snapshot) {
        defer { lastObserved = snapshot.taken }
        // An unwatched gap (sleep, a hung probe) or a failed probe proves nothing about idleness: start over.
        let gap = lastObserved.map { snapshot.taken.timeIntervalSince($0) > 3 * refreshInterval } ?? false
        guard snapshot.complete else { idleSince = [:]; return }
        var next: [String: Date] = [:]
        for row in snapshot.rows where !row.hasLiveOwner {
            next[row.id] = (gap ? nil : idleSince[row.id]) ?? snapshot.taken
        }
        idleSince = next
    }

    public mutating func reset(_ udid: String, to date: Date) {
        if idleSince[udid] != nil { idleSince[udid] = date }
    }

    public func due(pinned: Set<String>, settings: ReapSettings, now: Date) -> [String] {
        idleSince.keys.sorted().filter { reapsIn($0, pinned: pinned, settings: settings, now: now) == 0 }
    }

    public func reapsIn(_ udid: String, pinned: Set<String>, settings: ReapSettings, now: Date) -> TimeInterval? {
        guard settings.enabled, !pinned.contains(udid), let since = idleSince[udid] else { return nil }
        return max(0, settings.idlePeriod - now.timeIntervalSince(since))
    }
}

/// Spaces out retries of something that keeps failing: the wait doubles from `base` up to `cap`.
public struct Backoff: Sendable {
    private let base: TimeInterval, cap: TimeInterval
    private var failures = 0
    private var retryAt: Date?

    public init(base: TimeInterval = 30, cap: TimeInterval = 600) { self.base = base; self.cap = cap }

    public func ready(now: Date) -> Bool { retryAt.map { now >= $0 } ?? true }
    public mutating func failed(now: Date) {
        retryAt = now.addingTimeInterval(min(cap, base * pow(2, Double(failures))))
        failures += 1
    }
    public mutating func succeeded() { failures = 0; retryAt = nil }
}

public enum ReapVerdict: Equatable, Sendable { case reap; case wait(resetTo: Date) }

/// The guard for a session working in another folder command by command: its recent command defers the reap.
public func reapVerdict(hit: HistoryHit?, settings: ReapSettings, now: Date) -> ReapVerdict {
    if let hit, hit.sessionRunning, now.timeIntervalSince(hit.time) < settings.idlePeriod { return .wait(resetTo: hit.time) }
    return .reap
}

/// "All": pinned rows are in neither list; in-use rows join `targets` only when asked.
public func bulkTargets(rows: [SimRow], pinned: Set<String>, includeInUse: Bool) -> (targets: [SimRow], inUse: [SimRow]) {
    let unpinned = rows.filter { !pinned.contains($0.id) }
    let inUse = unpinned.filter(\.hasLiveOwner)
    return (unpinned.filter { !$0.hasLiveOwner } + (includeInUse ? inUse : []), inUse)
}

/// Arguments for `xcrun`, or `nil` unless the UDID is well-formed and booted in the most recent snapshot.
public func simctlArguments(_ action: SimAction, udid: String, in snapshot: Snapshot) -> [String]? {
    guard udid.range(of: udidPattern, options: .regularExpression) != nil,
          let row = snapshot.rows.first(where: { $0.id == udid }) else { return nil }
    return ["simctl"] + (row.device.isTestClone ? ["--set", "testing"] : []) + [action.rawValue, udid]
}
