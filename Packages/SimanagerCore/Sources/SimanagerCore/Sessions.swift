import Foundation

public enum SessionKind: String, Sendable { case claudeCLI, claudeDesktop, shell }

/// What a process is run by: a Claude session, or a shell on a terminal.
public struct Session: Hashable, Sendable {
    public let pid: Int32
    public let kind: SessionKind
    public let cwd, claudeSessionID, name, status, tty, zellijSession, zellijPane, zellijTab, terminal: String?

    public init(pid: Int32, kind: SessionKind, cwd: String? = nil, claudeSessionID: String? = nil, name: String? = nil,
                status: String? = nil, tty: String? = nil, zellijSession: String? = nil, zellijPane: String? = nil,
                zellijTab: String? = nil, terminal: String? = nil) {
        self.pid = pid; self.kind = kind; self.cwd = cwd; self.claudeSessionID = claudeSessionID; self.name = name
        self.status = status; self.tty = tty; self.zellijSession = zellijSession; self.zellijPane = zellijPane
        self.zellijTab = zellijTab; self.terminal = terminal
    }

    public var label: String {
        var s: String
        switch kind {
        case .shell: s = "shell \(tty ?? String(pid))"
        case .claudeCLI, .claudeDesktop:
            s = (kind == .claudeDesktop ? "claude desktop " : "claude ") + (name.map { "\"\($0)\"" } ?? String(pid))
        }
        if let zellijSession {
            s += " · zellij \(zellijSession)"
            if let zellijTab { s += " › \(zellijTab)" } else if let zellijPane { s += " pane \(zellijPane)" }
        }
        if let terminal, let first = terminal.first { s += " · " + first.uppercased() + terminal.dropFirst() }
        return s
    }
}

public struct ProcessFacts: Sendable {
    public let table: ProcTable
    public let cwd: [Int32: String]
    public let env: [Int32: [String: String]]
    public let sessionFiles: [Int32: ClaudeSessionFile]
    /// zellij session name → (claude session id → tab)
    public let zellijTabs: [String: [String: String]]
    public let ownPID: Int32

    public init(table: ProcTable, cwd: [Int32: String], env: [Int32: [String: String]],
                sessionFiles: [Int32: ClaudeSessionFile], zellijTabs: [String: [String: String]], ownPID: Int32) {
        self.table = table; self.cwd = cwd; self.env = env; self.sessionFiles = sessionFiles
        self.zellijTabs = zellijTabs; self.ownPID = ownPID
    }
}

func isClaudeProcess(_ p: Proc, sessionFiles: [Int32: ClaudeSessionFile]) -> Bool {
    sessionFiles[p.pid] != nil || firstWordBasename(p.command) == "claude"
}

func isShellSession(_ p: Proc) -> Bool {
    let name = firstWordBasename(p.command)
    return p.tty != nil && ["zsh", "bash", "fish", "sh"].contains(name.hasPrefix("-") ? String(name.dropFirst()) : name)
}

/// The processes whose environment the probe must read.
public func sessionCandidatePIDs(_ procs: [Proc], sessionFiles: [Int32: ClaudeSessionFile]) -> [Int32] {
    procs.filter { isClaudeProcess($0, sessionFiles: sessionFiles) || isShellSession($0) }.map(\.pid)
}

/// The nearest Claude process at or above `pid`; failing that the nearest shell on a terminal; else `nil`.
public func owningSession(of pid: Int32, facts: ProcessFacts) -> Session? {
    guard let me = facts.table[pid] else { return nil }
    let chain = [me] + facts.table.ancestors(of: pid)
    let env = { (p: Proc) in facts.env[p.pid] ?? [:] }

    if let i = chain.firstIndex(where: { isClaudeProcess($0, sessionFiles: facts.sessionFiles) }) {
        let p = chain[i], file = facts.sessionFiles[p.pid], e = env(p)
        let zellij = e["ZELLIJ_SESSION_NAME"]
        return Session(pid: p.pid,
                       kind: chain[i...].contains { $0.command.contains("/Claude.app/") } ? .claudeDesktop : .claudeCLI,
                       cwd: facts.cwd[p.pid], claudeSessionID: file?.sessionId, name: file?.name, status: file?.status,
                       tty: p.tty, zellijSession: zellij, zellijPane: e["ZELLIJ_PANE_ID"],
                       zellijTab: zellij.flatMap { z in file.flatMap { facts.zellijTabs[z]?[$0.sessionId] } },
                       terminal: e["TERM_PROGRAM"])
    }
    if let p = chain.first(where: isShellSession) {
        let e = env(p)
        return Session(pid: p.pid, kind: .shell, cwd: facts.cwd[p.pid], tty: p.tty,
                       zellijSession: e["ZELLIJ_SESSION_NAME"], zellijPane: e["ZELLIJ_PANE_ID"], terminal: e["TERM_PROGRAM"])
    }
    return nil
}
