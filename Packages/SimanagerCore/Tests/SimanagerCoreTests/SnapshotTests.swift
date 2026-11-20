import Foundation
import Testing
import SimanagerCore

@Test func snapshotFromFixtures() {
    let s = buildSnapshot(rawProbe()) { [14986: 5_000, 15001: 900, 18532: 6_300][$0] }
    #expect(s.complete && s.rows.map(\.id) == [B, A, C] && s.totalFootprint == 12_200)
    #expect(s.rows[1].hasLiveOwner && !s.rows[0].hasLiveOwner)
    #expect(s.rows[0].uptime == 163_103)                                   // 1d 21:18:23
    let c = s.rows[2]                                                      // stale boot state
    #expect(c.footprint == nil && c.uptime == nil && !c.hasLiveOwner && c.checkout?.path == "/Users/dev/w/acme-855")
}
@Test func failedProbeIsIncomplete() {
    #expect(!buildSnapshot(rawProbe(ps: nil)) { _ in nil }.complete)
    #expect(!buildSnapshot(rawProbe(lsof: nil)) { _ in nil }.complete)
    #expect(!buildSnapshot(rawProbe(simctl: Data("x".utf8))) { _ in nil }.complete)
    #expect(!buildSnapshot(rawProbe(lanes: [LaneProbe(rule: acmeLane, worktrees: nil)])) { _ in nil }.complete)
    #expect(buildSnapshot(rawProbe(testing: nil)) { _ in nil }.complete)   // no test-clone set is normal
}
