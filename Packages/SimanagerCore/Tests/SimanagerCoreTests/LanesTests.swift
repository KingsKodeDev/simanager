import Foundation
import Testing
import SimanagerCore

@Test func longestTagWins() {
    let tags = ["main", "acme", "acme-triage", "acme-855"]
    #expect(matchTag(simName: "ACME acme-triage shard 2 - iPhone 17 Pro", prefix: "ACME", tags: tags) == "acme-triage")
    #expect(matchTag(simName: "ACME acme - iPhone 17 Pro", prefix: "ACME", tags: tags) == "acme")
    #expect(matchTag(simName: "ACME main watch - Apple Watch Ultra 3 (49mm)", prefix: "ACME", tags: tags) == "main")
    #expect(matchTag(simName: "ACME main iOS 27 - iPhone 17 Pro", prefix: "ACME", tags: tags) == "main")
    #expect(matchTag(simName: "ACME acme-9 - iPhone 17 Pro", prefix: "ACME", tags: tags) == nil)     // "acme" is followed by "-", not a space
    #expect(matchTag(simName: "ACMEX main - iPhone", prefix: "ACME", tags: tags) == nil)
    #expect(matchTag(simName: "Scratch - iPhone 17", prefix: "ACME", tags: tags) == nil)
}
@Test func resolveCheckoutMapsMainAndWorktrees() {
    let lanes = [LaneProbe(rule: acmeLane, worktrees: parseWorktrees(fixtureText("worktrees.txt")))]
    #expect(resolveCheckout(simName: "ACME main iOS 27 - iPhone 17 Pro", lanes: lanes)
            == Checkout(path: "/Users/dev/projects/acme-app", branch: "acme-764-feedback"))
    #expect(resolveCheckout(simName: "ACME acme-triage shard 2 - iPhone 17 Pro", lanes: lanes) == Checkout(path: "/Users/dev/w/acme-triage", branch: nil))
    #expect(resolveCheckout(simName: "Scratch - iPhone 17", lanes: lanes) == nil)
    #expect(resolveCheckout(simName: "ACME main - iPhone", lanes: [LaneProbe(rule: acmeLane, worktrees: nil)]) == nil)
}
@Test func seedHasNoLanes() {      // lanes are per machine: the file starts empty and is filled in by hand
    #expect(LanesFile.seed.lanes.isEmpty)
}
