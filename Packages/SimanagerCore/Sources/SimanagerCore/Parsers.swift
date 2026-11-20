import Foundation

/// Booted devices from `simctl list devices -j`. `nil` when the data is not that JSON.
public func parseSimctlDevices(_ json: Data, testClones: Bool) -> [SimDevice]? {
    guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          let runtimes = root["devices"] as? [String: [[String: Any]]] else { return nil }
    var out: [SimDevice] = []
    for (key, devices) in runtimes {
        for d in devices where d["state"] as? String == "Booted" {
            guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
            out.append(SimDevice(udid: udid, name: name, runtime: runtimeDisplay(key), isTestClone: testClones))
        }
    }
    return out
}

/// `com.apple.CoreSimulator.SimRuntime.iOS-26-4` → `iOS 26.4`.
func runtimeDisplay(_ key: String) -> String {
    let last = key.split(separator: ".").last.map(String.init) ?? key
    guard let dash = last.firstIndex(of: "-") else { return last }
    return last[..<dash] + " " + last[last.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
}

/// Lines of `ps -axww -o pid=,ppid=,tty=,etime=,command=`. Lines that do not parse are skipped.
public func parsePS(_ text: String) -> [Proc] {
    text.split(separator: "\n").compactMap { line in
        let f = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard f.count == 5, let pid = Int32(f[0]), let ppid = Int32(f[1]), let elapsed = parseEtime(f[3]) else { return nil }
        return Proc(pid: pid, ppid: ppid, tty: f[2] == "??" ? nil : String(f[2]), elapsed: elapsed,
                    command: f[4].trimmingCharacters(in: .whitespaces))
    }
}

/// `[[dd-]hh:]mm:ss`
func parseEtime(_ s: Substring) -> TimeInterval? {
    let dayAndClock = s.split(separator: "-", maxSplits: 1)
    guard let clock = dayAndClock.last, dayAndClock.count == 1 || Int(dayAndClock[0]) != nil else { return nil }
    let parts = clock.split(separator: ":").map { Int($0) }
    guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
    let days = dayAndClock.count == 2 ? Int(dayAndClock[0])! : 0
    let hms = (parts.count == 2 ? [0] : []) + parts.map { $0! }
    return TimeInterval(((days * 24 + hms[0]) * 60 + hms[1]) * 60 + hms[2])
}

/// `lsof -a -d cwd -Fpn`: a `p<pid>` line, then `n<path>`.
public func parseLsofCwd(_ text: String) -> [Int32: String] {
    var out: [Int32: String] = [:]
    var pid: Int32?
    for line in text.split(separator: "\n") {
        if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
        else if line.hasPrefix("n"), let pid { out[pid] = String(line.dropFirst()) }
    }
    return out
}

/// `git worktree list --porcelain`
public func parseWorktrees(_ text: String) -> [Worktree] {
    var out: [Worktree] = []
    for line in text.split(separator: "\n") {
        if line.hasPrefix("worktree ") {
            out.append(Worktree(path: String(line.dropFirst("worktree ".count)), branch: nil))
        } else if line.hasPrefix("branch "), let last = out.popLast() {
            let ref = line.dropFirst("branch ".count)
            out.append(Worktree(path: last.path, branch: String(ref.hasPrefix("refs/heads/") ? ref.dropFirst("refs/heads/".count) : ref)))
        }
    }
    return out
}

/// From `zellij action dump-layout`: claude session id → name of the tab whose pane resumes it.
public func parseZellijTabs(_ kdl: String) -> [String: String] {
    let tabLine = /^\s*tab\b/
    let tabName = /^\s*tab\b.*name="([^"]*)"/
    let resume = /"--resume" "([^"]+)"/
    var out: [String: String] = [:]
    var current: String?
    for line in kdl.split(separator: "\n") {
        if line.firstMatch(of: tabLine) != nil {
            current = line.firstMatch(of: tabName).map { String($0.1) }   // an unnamed tab (swap layout) clears it
        } else if let current, line.contains("args"), let m = line.firstMatch(of: resume) {
            out[String(m.1)] = current
        }
    }
    return out
}

/// `<config dir>/sessions/<pid>.json`. `nil` for a file caught mid-write or without a session id.
public func parseSessionFile(_ data: Data) -> ClaudeSessionFile? {
    guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let pid = d["pid"] as? Int, let id = d["sessionId"] as? String else { return nil }
    return ClaudeSessionFile(pid: Int32(truncatingIfNeeded: pid), sessionId: id,
                             name: d["name"] as? String, status: d["status"] as? String, kind: d["kind"] as? String)
}

/// A `KERN_PROCARGS2` buffer: argc, exec path, NUL padding, argv, then the environment.
public func parseProcArgs2(_ data: Data) -> (argv: [String], env: [String: String])? {
    guard data.count > 4 else { return nil }
    let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    let bytes = [UInt8](data.dropFirst(4))
    var i = 0
    while i < bytes.count, bytes[i] != 0 { i += 1 }     // exec path
    while i < bytes.count, bytes[i] == 0 { i += 1 }     // its padding
    func next() -> String? {
        guard i < bytes.count else { return nil }
        let start = i
        while i < bytes.count, bytes[i] != 0 { i += 1 }
        defer { i += 1 }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }
    var argv: [String] = []
    for _ in 0..<max(argc, 0) {
        guard let s = next() else { return nil }
        argv.append(s)
    }
    var env: [String: String] = [:]
    while let s = next(), !s.isEmpty {
        guard let eq = s.firstIndex(of: "=") else { continue }
        env[String(s[..<eq])] = String(s[s.index(after: eq)...])
    }
    return (argv, env)
}
