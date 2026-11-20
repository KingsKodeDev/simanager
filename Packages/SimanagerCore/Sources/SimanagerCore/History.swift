import Foundation

/// Fixed string for `grep -F`: a line holding a Bash tool call.
public let transcriptGrepNeedle = #""name":"Bash","input":{"command""#

public struct TranscriptCommand: Hashable, Sendable {
    public let sessionID: String
    public let cwd: String?
    public let time: Date
    public let command: String
    public init(sessionID: String, cwd: String?, time: Date, command: String) {
        self.sessionID = sessionID; self.cwd = cwd; self.time = time; self.command = command
    }
}

/// Every Bash tool call on one transcript line; `[]` for anything else, including a truncated line.
/// Only commands are read, never tool output: a session that ran `simctl list` has every UDID in its output.
public func parseTranscriptLine(_ line: String) -> [TranscriptCommand] {
    guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          d["type"] as? String == "assistant",
          let session = d["sessionId"] as? String,
          let stamp = d["timestamp"] as? String,
          let time = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp))
              ?? (try? Date.ISO8601FormatStyle().parse(stamp)),
          let content = (d["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return [] }
    return content.compactMap { item in
        guard item["type"] as? String == "tool_use", item["name"] as? String == "Bash",
              let command = (item["input"] as? [String: Any])?["command"] as? String else { return nil }
        return TranscriptCommand(sessionID: session, cwd: d["cwd"] as? String, time: time, command: command)
    }
}

public struct HistoryTarget: Hashable, Sendable {
    public let udid: String
    public let checkoutPath: String?
    public init(udid: String, checkoutPath: String?) { self.udid = udid; self.checkoutPath = checkoutPath }
}

/// True when `text` names `path` as a whole path: `~/w/acme` is not named by `~/w/acme-triage`.
func mentionsPath(_ text: String, _ path: String) -> Bool {
    var from = text.startIndex
    while let r = text.range(of: path, range: from..<text.endIndex) {
        guard r.upperBound < text.endIndex else { return true }
        let next = text[r.upperBound]
        if !(next.isLetter || next.isNumber || "-_.".contains(next)) { return true }
        from = r.upperBound
    }
    return false
}

/// The best counting command per UDID (see `HistoryHit.outranks`). `running` maps the session ids of live Claude processes to their names.
public func historyHits<S: Sequence>(_ commands: S, targets: [HistoryTarget], running: [String: String?], home: String)
    -> [String: HistoryHit] where S.Element == TranscriptCommand {
    var best: [String: HistoryHit] = [:]
    for c in commands {
        let hit = HistoryHit(sessionID: c.sessionID, sessionName: running[c.sessionID] ?? nil, time: c.time,
                             command: c.command, sessionRunning: running.keys.contains(c.sessionID))
        for t in targets where best[t.udid].map(hit.outranks) ?? true {
            var counts = c.command.contains(t.udid)
            if !counts, let path = t.checkoutPath {
                let short = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
                counts = mentionsPath(c.command, path) || mentionsPath(c.command, short)
                    || (c.cwd.map { isAtOrBelow($0, path) } ?? false)   // a session sitting in the checkout: any command counts
            }
            if counts { best[t.udid] = hit }
        }
    }
    return best
}
