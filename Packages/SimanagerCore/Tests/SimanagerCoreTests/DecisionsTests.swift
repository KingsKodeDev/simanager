import Foundation
import Testing
import SimanagerCore

let t0 = Date(timeIntervalSince1970: 1_795_000_000)
let s = ReapSettings.default
let cloneUDID = "22222222-3333-4444-5555-666666666666"

func row(_ udid: String, live: Bool, clone: Bool = false) -> SimRow {
    SimRow(device: SimDevice(udid: udid, name: "sim \(udid.prefix(4))", runtime: "iOS 27.0", isTestClone: clone),
           footprint: 1, uptime: 1, checkout: nil, live: live ? [.checkout(session: Session(pid: 1, kind: .shell))] : [])
}
func snap(at seconds: TimeInterval, idle: [String], live: [String] = [], complete: Bool = true) -> Snapshot {
    Snapshot(rows: idle.map { row($0, live: false) } + live.map { row($0, live: true) }, complete: complete, taken: t0 + seconds)
}
let snapWithClone = Snapshot(rows: [row(cloneUDID, live: false, clone: true)], complete: true, taken: t0)

@Test func notBeforeIdlePeriodAndNothingAtLaunch() {
    var c = ReapClock()
    for t in stride(from: 0.0, through: 1795, by: 5) { c.observe(snap(at: t, idle: [B])) }
    #expect(c.due(pinned: [], settings: s, now: t0 + 1795).isEmpty)
    #expect(c.reapsIn(B, pinned: [], settings: s, now: t0 + 1200) == 600)
    c.observe(snap(at: 1800, idle: [B]))
    #expect(c.due(pinned: [], settings: s, now: t0 + 1800) == [B])
}
@Test func oneLiveRefreshResetsTheClock() {
    var c = ReapClock()
    c.observe(snap(at: 0, idle: [B])); c.observe(snap(at: 5, idle: [], live: [B])); c.observe(snap(at: 10, idle: [B]))
    #expect(c.idleSince[B] == t0 + 10)
}
@Test func incompleteSnapshotClearsEveryClock() {
    var c = ReapClock()
    c.observe(snap(at: 0, idle: [A, B])); c.observe(snap(at: 5, idle: [A, B], complete: false))
    #expect(c.idleSince.isEmpty)
    c.observe(snap(at: 10, idle: [A, B])); #expect(c.idleSince[A] == t0 + 10)
}
@Test func observationGapClearsEveryClock() {      // sleep or a hung probe
    var c = ReapClock()
    c.observe(snap(at: 0, idle: [B])); c.observe(snap(at: 3600, idle: [B]))
    #expect(c.idleSince[B] == t0 + 3600)
}
@Test func pinnedDisabledAndGoneAreNeverDue() {
    var c = ReapClock()
    c.observe(snap(at: 0, idle: [A, B])); c.observe(snap(at: 5, idle: [A]))
    #expect(c.idleSince[B] == nil)
    #expect(c.due(pinned: [A], settings: s, now: t0 + 9999).isEmpty)
    var off = s; off.enabled = false
    #expect(c.due(pinned: [], settings: off, now: t0 + 9999).isEmpty && c.reapsIn(A, pinned: [A], settings: s, now: t0) == nil)
}
@Test func liveSessionsRecentCommandDefersTheReap() {
    let now = t0 + 4000
    func hit(_ ago: TimeInterval, running: Bool) -> HistoryHit { HistoryHit(sessionID: "s", sessionName: nil, time: now - ago, command: "x", sessionRunning: running) }
    #expect(reapVerdict(hit: hit(600, running: true), settings: s, now: now) == .wait(resetTo: now - 600))
    #expect(reapVerdict(hit: hit(600, running: false), settings: s, now: now) == .reap)
    #expect(reapVerdict(hit: hit(1800, running: true), settings: s, now: now) == .reap)
    #expect(reapVerdict(hit: nil, settings: s, now: now) == .reap)
}
@Test func allSkipsPinnedAndInUseUnlessAsked() {
    let rows = snap(at: 0, idle: [B, C], live: [A]).rows
    #expect(bulkTargets(rows: rows, pinned: [C], includeInUse: false).targets.map(\.id) == [B])
    #expect(bulkTargets(rows: rows, pinned: [C], includeInUse: false).inUse.map(\.id) == [A])
    #expect(Set(bulkTargets(rows: rows, pinned: [C], includeInUse: true).targets.map(\.id)) == [A, B])
}
@Test func commandOnlyForAValidUdidInTheSnapshot() {
    let sn = snap(at: 0, idle: [B])
    #expect(simctlArguments(.shutdown, udid: B, in: sn) == ["simctl", "shutdown", B])
    #expect(simctlArguments(.delete, udid: A, in: sn) == nil)                          // not in the snapshot
    #expect(simctlArguments(.delete, udid: "booted", in: sn) == nil)
    #expect(simctlArguments(.delete, udid: B + " ; rm -rf ~", in: sn) == nil)
    #expect(simctlArguments(.delete, udid: cloneUDID, in: snapWithClone) == ["simctl", "--set", "testing", "delete", cloneUDID])
}
@Test func repeatedFailuresWaitLongerUpToACap() {
    var b = Backoff(base: 30, cap: 100)
    #expect(b.ready(now: t0))
    b.failed(now: t0)
    #expect(!b.ready(now: t0 + 29) && b.ready(now: t0 + 30))
    b.failed(now: t0 + 30)
    #expect(!b.ready(now: t0 + 89) && b.ready(now: t0 + 90))            // 60 s after the second failure
    b.failed(now: t0 + 90)
    #expect(!b.ready(now: t0 + 189) && b.ready(now: t0 + 190))          // 120 s capped to 100
    b.succeeded()
    #expect(b.ready(now: t0 + 190))
    b.failed(now: t0 + 200)
    #expect(b.ready(now: t0 + 230))                                     // back to the base wait
}
