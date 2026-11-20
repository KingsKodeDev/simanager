import Foundation

/// The most recent command a Claude session ran that names a simulator or its checkout.
public struct HistoryHit: Hashable, Sendable {
    public let sessionID: String
    public let sessionName: String?
    public let time: Date
    public let command: String
    public let sessionRunning: Bool
    public init(sessionID: String, sessionName: String?, time: Date, command: String, sessionRunning: Bool) {
        self.sessionID = sessionID; self.sessionName = sessionName; self.time = time
        self.command = command; self.sessionRunning = sessionRunning
    }

    /// A running session's command outranks any ended session's, then the newer wins: the reaper asks
    /// "did a session that is still running use this?", and a later command from an ended one must not hide that.
    public func outranks(_ other: HistoryHit) -> Bool {
        sessionRunning != other.sessionRunning ? sessionRunning : time > other.time
    }
}

public enum Evidence: Hashable, Sendable {
    /// A running process whose arguments name the simulator.
    case direct(pid: Int32, command: String, session: Session?)
    /// A session with a process working inside the simulator's checkout.
    case checkout(session: Session)
    case history(HistoryHit)
}

func pathComponents(_ path: String) -> [Substring] { path.split(separator: "/") }

/// Compares whole path components: `/w/acme-triage` is not below `/w/acme`.
public func isAtOrBelow(_ path: String, _ root: String) -> Bool {
    pathComponents(path).starts(with: pathComponents(root))
}

/// The longest worktree `cwd` is at or below. A nested `.claude/worktrees/*` belongs to itself, not its container.
public func owningWorktree(of cwd: String, worktreePaths: [String]) -> String? {
    guard let owner = worktreePaths.filter({ isAtOrBelow(cwd, $0) }).max(by: { $0.count < $1.count }) else { return nil }
    let below = pathComponents(cwd).dropFirst(pathComponents(owner).count)
    return below.count >= 3 && below.starts(with: [".claude", "worktrees"]) ? nil : owner
}

public func liveEvidence(sim: SimDevice, simRoot: Int32?, checkout: Checkout?, worktreePaths: [String], facts: ProcessFacts) -> [Evidence] {
    // The simulator's own processes and our own simctl children all name the UDID; neither is a user of it.
    let notUsers = Set((simRoot.map(facts.table.subtree) ?? []) + facts.table.subtree(of: facts.ownPID))
    var out: [Evidence] = []
    for pid in facts.table.pids(mentioning: sim.udid) where !notUsers.contains(pid) {
        guard let p = facts.table[pid] else { continue }
        let session = owningSession(of: p.pid, facts: facts)
        if session == nil && p.ppid == 1 { continue }       // a daemon (DTServiceHub) is not an owner
        out.append(.direct(pid: p.pid, command: p.command, session: session))
    }
    if let checkout {
        var seen: Set<Int32> = []
        for p in facts.table.all {
            // hasPrefix first: a cheap necessary condition that spares splitting paths for thousands of processes.
            guard let cwd = facts.cwd[p.pid], cwd.hasPrefix(checkout.path),
                  owningWorktree(of: cwd, worktreePaths: worktreePaths) == checkout.path,
                  let session = owningSession(of: p.pid, facts: facts), seen.insert(session.pid).inserted else { continue }
            out.append(.checkout(session: session))
        }
    }
    return out
}
