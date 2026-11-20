import Foundation

public struct SimDevice: Hashable, Sendable {
    public let udid, name, runtime: String
    public let isTestClone: Bool
    public init(udid: String, name: String, runtime: String, isTestClone: Bool) {
        self.udid = udid; self.name = name; self.runtime = runtime; self.isTestClone = isTestClone
    }
}

public struct Proc: Hashable, Sendable {
    public let pid, ppid: Int32
    public let tty: String?
    public let elapsed: TimeInterval
    public let command: String
    public init(pid: Int32, ppid: Int32, tty: String?, elapsed: TimeInterval, command: String) {
        self.pid = pid; self.ppid = ppid; self.tty = tty; self.elapsed = elapsed; self.command = command
    }
}

/// `branch == nil` means a detached HEAD.
public struct Worktree: Hashable, Sendable {
    public let path: String
    public let branch: String?
    public init(path: String, branch: String?) { self.path = path; self.branch = branch }
}

public struct ClaudeSessionFile: Hashable, Sendable {
    public let pid: Int32
    public let sessionId: String
    public let name, status, kind: String?
    public init(pid: Int32, sessionId: String, name: String?, status: String?, kind: String?) {
        self.pid = pid; self.sessionId = sessionId; self.name = name; self.status = status; self.kind = kind
    }
}

public let udidPattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
