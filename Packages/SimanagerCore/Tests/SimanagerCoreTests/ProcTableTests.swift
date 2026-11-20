import Foundation
import Testing
import SimanagerCore

@Test func subtreeAndAncestors() {
    let t = ProcTable(parsePS(fixtureText("ps.txt")))
    #expect(Set(t.subtree(of: 14986)) == [14986, 15001, 15002])
    #expect(t.ancestors(of: 25901).map(\.pid) == [25900, 25816, 2000])
    #expect(t.subtree(of: 999_999).isEmpty)
}
@Test func ancestorsSurviveACycle() {
    let t = ProcTable([Proc(pid: 5, ppid: 6, tty: nil, elapsed: 0, command: "a"), Proc(pid: 6, ppid: 5, tty: nil, elapsed: 0, command: "b")])
    #expect(t.ancestors(of: 5).map(\.pid) == [6])
}
@Test func simRootsFindLaunchdSimByUDID() {
    #expect(simRoots(parsePS(fixtureText("ps.txt"))) == [A: 14986, B: 18532])   // C has none; 15002 has /Devices/<A>/ but is not launchd_sim
}
@Test func footprintSumsTreeAndSkipsUnreadable() {
    let t = ProcTable(parsePS(fixtureText("ps.txt")))
    #expect(treeFootprint(root: 14986, table: t) { [14986: 100, 15001: 20][$0] } == 120)   // 15002 unreadable
}
@Test func pidsMentioningAUdid() {
    let t = ProcTable(parsePS(fixtureText("ps.txt")))
    #expect(t.pids(mentioning: A) == [14986, 15002, 25901])
    #expect(t.pids(mentioning: B) == [18532, 7718, 4243])
    #expect(t.pids(mentioning: C).isEmpty)
    let odd = ProcTable([Proc(pid: 1, ppid: 0, tty: nil, elapsed: 0, command: "x \(A.lowercased()) \(A.dropLast()) \(A)Z id=\(B)")])
    #expect(odd.pids(mentioning: A) == [1] && odd.pids(mentioning: B) == [1])     // "<A>Z" still names A; lower case and short forms do not
    #expect(odd.pids(mentioning: A.lowercased()).isEmpty)
}
@Test func simRootsFindTestClones() {      // Xcode's clone set lives under XCTestDevices, not CoreSimulator/Devices
    let clone = "22222222-3333-4444-5555-666666666666"
    let p = Proc(pid: 900, ppid: 1, tty: nil, elapsed: 5, command: "launchd_sim /Users/dev/Library/Developer/XCTestDevices/\(clone)/data/var/run/launchd_bootstrap.plist")
    #expect(simRoots([p]) == [clone: 900])
}
