import Foundation
import Testing
import SimanagerCore

func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

/// One transcript line in the real shape: an assistant message carrying a Bash tool call.
func line(session: String, cwd: String, time: String, command: String) -> String {
    let object: [String: Any] = [
        "type": "assistant", "sessionId": session, "cwd": cwd, "timestamp": time,
        "message": ["role": "assistant", "content": [
            ["type": "text", "text": "Running it."],
            ["type": "tool_use", "id": "toolu_01", "name": "Bash", "input": ["command": command, "description": "run"]],
        ]],
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

/// A tool result (command output) that lists a UDID, as `simctl list` output would.
func toolResultLineMentioning(udid: String) -> String {
    let object: [String: Any] = [
        "type": "user", "sessionId": "s9", "cwd": "/Users/dev", "timestamp": "2026-11-18T14:15:01.000Z",
        "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "toolu_01", "content": "iPhone 17 Pro (\(udid)) (Booted)"]]],
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

@Test func parsesBashToolCallsOnly() {
    let l = line(session: "s1", cwd: "/Users/dev/w/acme", time: "2026-11-18T14:15:00.000Z", command: "xcrun simctl list")
    #expect(parseTranscriptLine(l) == [TranscriptCommand(sessionID: "s1", cwd: "/Users/dev/w/acme", time: date("2026-11-18T14:15:00Z"), command: "xcrun simctl list")])
    #expect(parseTranscriptLine(#"{"type":"api-request-shape","shape":"\"name\":\"Bash\""}"#).isEmpty)
    #expect(parseTranscriptLine(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","inp"#).isEmpty)   // truncated
    #expect(parseTranscriptLine(toolResultLineMentioning(udid: A)).isEmpty)       // output is never read
}
@Test func hitRules() {
    let t = [HistoryTarget(udid: A, checkoutPath: "/Users/dev/w/acme"), HistoryTarget(udid: B, checkoutPath: "/Users/dev/w/acme-triage")]
    let cmds = [
        TranscriptCommand(sessionID: "s1", cwd: "/Users/dev", time: date("2026-11-18T10:00:00Z"), command: "cd ~/w/acme-triage && ./scripts/test_env.sh"),
        TranscriptCommand(sessionID: "s2", cwd: "/Users/dev", time: date("2026-11-18T11:00:00Z"), command: "xcrun simctl boot \(B)"),
        TranscriptCommand(sessionID: "s3", cwd: "/Users/dev/w/acme/ios", time: date("2026-11-18T09:00:00Z"), command: "make test"),
        TranscriptCommand(sessionID: "s4", cwd: "/Users/dev", time: date("2026-11-19T09:00:00Z"), command: "ls ~/w/acme-triage-old"),
    ]
    let h = historyHits(cmds, targets: t, running: ["s2": "triage"], home: "/Users/dev")
    #expect(h[B]?.sessionID == "s2" && h[B]?.sessionRunning == true && h[B]?.sessionName == "triage")   // newest counting command; s4 does not count
    #expect(h[A]?.sessionID == "s3" && h[A]?.sessionRunning == false)                                   // cwd inside the checkout: any command counts
}
@Test func noTargetsNoHits() { #expect(historyHits([TranscriptCommand](), targets: [], running: [:], home: "/Users/dev").isEmpty) }
@Test func runningSessionsCommandOutranksANewerEndedOne() {     // spec rule 3 asks about running sessions; an ended one must not mask it
    let t = [HistoryTarget(udid: B, checkoutPath: nil)]
    let cmds = [
        TranscriptCommand(sessionID: "live", cwd: nil, time: date("2026-11-18T10:00:00Z"), command: "xcrun simctl launch \(B) app"),
        TranscriptCommand(sessionID: "gone", cwd: nil, time: date("2026-11-18T11:00:00Z"), command: "xcrun simctl boot \(B)"),
    ]
    #expect(historyHits(cmds, targets: t, running: ["live": nil], home: "/Users/dev")[B]?.sessionID == "live")
    #expect(historyHits(cmds.reversed(), targets: t, running: ["live": nil], home: "/Users/dev")[B]?.sessionID == "live")
    let live = HistoryHit(sessionID: "live", sessionName: nil, time: date("2026-11-18T10:00:00Z"), command: "x", sessionRunning: true)
    let gone = HistoryHit(sessionID: "gone", sessionName: nil, time: date("2026-11-18T11:00:00Z"), command: "x", sessionRunning: false)
    #expect(live.outranks(gone) && !gone.outranks(live))
}
