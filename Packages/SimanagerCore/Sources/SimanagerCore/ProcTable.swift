import Foundation

public struct ProcTable: Sendable {
    private let byPID: [Int32: Proc]
    private let children: [Int32: [Int32]]
    public let all: [Proc]
    private let mentions: [String: [Int32]]

    /// Processes whose command names this UDID, in table order. Found in one pass at init: `ps` is about 1 MB here.
    public func pids(mentioning udid: String) -> [Int32] { mentions[udid] ?? [] }

    public init(_ procs: [Proc]) {
        all = procs
        var mentions: [String: [Int32]] = [:]
        for p in procs { for udid in Set(udidsMentioned(in: p.command)) { mentions[udid, default: []].append(p.pid) } }
        self.mentions = mentions
        byPID = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        children = Dictionary(grouping: procs, by: \.ppid).mapValues { $0.map(\.pid) }
    }

    public subscript(pid: Int32) -> Proc? { byPID[pid] }

    /// Includes `pid`; empty if unknown.
    public func subtree(of pid: Int32) -> [Int32] {
        guard byPID[pid] != nil else { return [] }
        var seen: Set<Int32> = [pid], out = [pid], i = 0
        while i < out.count {
            for child in children[out[i]] ?? [] where seen.insert(child).inserted { out.append(child) }
            i += 1
        }
        return out
    }

    /// Nearest first, excludes self; stops at pid 1, a missing parent or a cycle.
    public func ancestors(of pid: Int32) -> [Proc] {
        var seen: Set<Int32> = [pid], out: [Proc] = []
        var current = byPID[pid]
        while let p = current, p.ppid != 1, let parent = byPID[p.ppid], seen.insert(parent.pid).inserted {
            out.append(parent)
            current = parent
        }
        return out
    }
}

/// UDID-shaped substrings (8-4-4-4-12 upper-case hex), scanned as bytes.
func udidsMentioned(in text: String) -> [String] {
    var text = text
    return text.withUTF8 { b in
        var out: [String] = []
        var i = 8                                           // index of a UDID's first dash
        while i + 27 < b.count {
            if b[i] == 45, b[i + 5] == 45, b[i + 10] == 45, b[i + 15] == 45,
               (i - 8..<i + 28).allSatisfy({ j in
                   [i, i + 5, i + 10, i + 15].contains(j) || (48...57).contains(b[j]) || (65...70).contains(b[j])
               }) {
                out.append(String(decoding: b[i - 8..<i + 28], as: UTF8.self))
                i += 28
            } else {
                i += 1
            }
        }
        return out
    }
}

func firstWordBasename(_ command: String) -> String {
    let word = command.split(separator: " ", maxSplits: 1).first ?? ""
    return String(word.split(separator: "/").last ?? "")
}

/// UDID → pid of that simulator's `launchd_sim`.
public func simRoots(_ procs: [Proc]) -> [String: Int32] {
    var out: [String: Int32] = [:]
    for p in procs where firstWordBasename(p.command) == "launchd_sim" {
        // The UDID wherever it sits in the path: the default set is …/CoreSimulator/Devices/<UDID>/, Xcode's
        // test-clone set is …/XCTestDevices/<UDID>/.
        guard let udid = udidsMentioned(in: p.command).first else { continue }
        out[udid] = p.pid
    }
    return out
}

/// Sum of physical footprint over a process tree; processes that cannot be read count as zero.
public func treeFootprint(root: Int32, table: ProcTable, footprint: (Int32) -> UInt64?) -> UInt64 {
    table.subtree(of: root).reduce(0) { $0 + (footprint($1) ?? 0) }
}
