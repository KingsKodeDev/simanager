import Foundation
import Testing
import SimanagerCore

@Test func simctlKeepsBootedOnly() {
    let d = parseSimctlDevices(fixture("simctl-devices.json"), testClones: false)!
    #expect(d.map(\.udid).sorted() == [A, B, C].sorted())
    #expect(d.first { $0.udid == B }!.runtime == "iOS 26.4")
    #expect(d.first { $0.udid == A }!.name == "ACME main iOS 27 - iPhone 17 Pro")
    #expect(parseSimctlDevices(fixture("simctl-devices.json"), testClones: true)!.allSatisfy { $0.isTestClone })
}
@Test func simctlGarbageIsNil() { #expect(parseSimctlDevices(Data("Using Parallel".utf8), testClones: false) == nil) }
@Test func psParsesColumnsAndElapsed() {
    let p = parsePS(fixtureText("ps.txt"))
    #expect(p.count == 16)
    let root = p.first { $0.pid == 14986 }!
    #expect(root.ppid == 1 && root.tty == nil && root.elapsed == 169_237)      // 1d 23:00:37
    #expect(p.first { $0.pid == 25816 }!.tty == "ttys003")
    #expect(p.first { $0.pid == 25901 }!.elapsed == 598)                       // 09:58
    #expect(p.first { $0.pid == 25901 }!.command == "xcodebuild test -destination id=\(A)")
}
@Test func lsofMapsPidToCwd() {
    let c = parseLsofCwd(fixtureText("lsof.txt"))
    #expect(c[25816] == "/Users/dev/projects/acme-app" && c[3100] == "/Users/dev")
}
@Test func worktreesIncludeDetached() {
    let w = parseWorktrees(fixtureText("worktrees.txt"))
    #expect(w.count == 4 && w[0].branch == "acme-764-feedback")
    #expect(w.first { $0.path == "/Users/dev/w/acme-triage" }!.branch == nil)
}
@Test func zellijMapsResumeIdToTab() {
    let t = parseZellijTabs(fixtureText("zellij-layout.kdl"))
    #expect(t == ["0a0a0a0a-1111-4111-8111-000000000001": "acme", "0b0b0b0b-2222-4222-8222-000000000002": "feedback"])
}
@Test func sessionFileParsesAndRejectsPartial() {
    #expect(parseSessionFile(fixture("session.json")) == ClaudeSessionFile(pid: 25816, sessionId: "0a0a0a0a-1111-4111-8111-000000000001", name: "acme", status: "busy", kind: "interactive"))
    #expect(parseSessionFile(Data(#"{"pid": 25816, "sess"#.utf8)) == nil)      // caught mid-write
    #expect(parseSessionFile(Data(#"{"pid": 1}"#.utf8)) == nil)                // no sessionId
}
@Test func procArgs2SplitsArgvFromEnv() {
    // buffer: Int32 argc=2, exec path, NUL padding, "claude\0--resume\0", then "A=1\0B=x=y\0\0"
    let r = parseProcArgs2(makeProcArgs2(exec: "/x/claude", argv: ["claude", "--resume"], env: ["A=1", "B=x=y"]))!
    #expect(r.argv == ["claude", "--resume"] && r.env == ["A": "1", "B": "x=y"])
    #expect(parseProcArgs2(Data([1, 0])) == nil)
}
