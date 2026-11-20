import Foundation

public struct SimRow: Identifiable, Hashable, Sendable {
    public let device: SimDevice
    /// `nil` when the device is booted but has no process (stale boot state).
    public let footprint: UInt64?
    public let uptime: TimeInterval?
    public let checkout: Checkout?
    public let live: [Evidence]
    public var id: String { device.udid }
    public var hasLiveOwner: Bool { !live.isEmpty }
    public init(device: SimDevice, footprint: UInt64?, uptime: TimeInterval?, checkout: Checkout?, live: [Evidence]) {
        self.device = device; self.footprint = footprint; self.uptime = uptime; self.checkout = checkout; self.live = live
    }
}

/// Everything one refresh read from the machine. A `nil` field is a probe that failed.
public struct RawProbe: Sendable {
    public let simctl: Data?, testing: Data?
    public let ps: String?, lsof: String?
    public let lanes: [LaneProbe]
    public let env: [Int32: [String: String]]
    public let sessionFiles: [Int32: ClaudeSessionFile]
    /// zellij session name → `dump-layout` text
    public let zellijLayouts: [String: String]
    public let ownPID: Int32
    public let taken: Date
    public init(simctl: Data?, testing: Data?, ps: String?, lsof: String?, lanes: [LaneProbe], env: [Int32: [String: String]],
                sessionFiles: [Int32: ClaudeSessionFile], zellijLayouts: [String: String], ownPID: Int32, taken: Date) {
        self.simctl = simctl; self.testing = testing; self.ps = ps; self.lsof = lsof; self.lanes = lanes; self.env = env
        self.sessionFiles = sessionFiles; self.zellijLayouts = zellijLayouts; self.ownPID = ownPID; self.taken = taken
    }
}

public struct Snapshot: Sendable {
    public let rows: [SimRow]
    /// False when any probe failed: its "no owner" rows prove nothing and must not feed the reaper.
    public let complete: Bool
    public let taken: Date
    public var totalFootprint: UInt64 { rows.reduce(0) { $0 + ($1.footprint ?? 0) } }
    public init(rows: [SimRow], complete: Bool, taken: Date) { self.rows = rows; self.complete = complete; self.taken = taken }
}

public func buildSnapshot(_ raw: RawProbe, footprint: (Int32) -> UInt64?) -> Snapshot {
    let devices = raw.simctl.flatMap { parseSimctlDevices($0, testClones: false) }
    let clones = raw.testing.flatMap { parseSimctlDevices($0, testClones: true) } ?? []
    let procs = raw.ps.map(parsePS) ?? []
    let cwd = raw.lsof.map(parseLsofCwd) ?? [:]
    let complete = devices != nil && !procs.isEmpty && !cwd.isEmpty && raw.lanes.allSatisfy { $0.worktrees != nil }

    let facts = ProcessFacts(table: ProcTable(procs), cwd: cwd, env: raw.env, sessionFiles: raw.sessionFiles,
                             zellijTabs: raw.zellijLayouts.mapValues(parseZellijTabs), ownPID: raw.ownPID)
    let roots = simRoots(procs)
    let worktreePaths = raw.lanes.flatMap { $0.worktrees ?? [] }.map(\.path)

    let rows = ((devices ?? []) + clones).map { device in
        let root = roots[device.udid]
        let checkout = resolveCheckout(simName: device.name, lanes: raw.lanes)
        return SimRow(device: device,
                      footprint: root.map { treeFootprint(root: $0, table: facts.table, footprint: footprint) },
                      uptime: root.flatMap { facts.table[$0]?.elapsed }, checkout: checkout,
                      live: liveEvidence(sim: device, simRoot: root, checkout: checkout, worktreePaths: worktreePaths, facts: facts))
    }.sorted { a, b in
        switch (a.footprint, b.footprint) {         // largest first, no-process rows last
        case let (x?, y?) where x != y: return x > y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.device.name < b.device.name
        }
    }
    return Snapshot(rows: rows, complete: complete, taken: raw.taken)
}
