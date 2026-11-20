import Foundation
import Testing
import SimanagerCore

@Test func pathComponentsNotPrefixes() {
    #expect(isAtOrBelow("/Users/dev/w/acme/ios", "/Users/dev/w/acme"))
    #expect(isAtOrBelow("/Users/dev/w/acme", "/Users/dev/w/acme"))
    #expect(!isAtOrBelow("/Users/dev/w/acme-triage", "/Users/dev/w/acme"))
    #expect(!isAtOrBelow("/Users/dev", "/Users/dev/w/acme"))               // above never counts
}
@Test func nestedWorktreeBelongsToItself() {
    let w = ["/Users/dev/w/acme-triage", "/Users/dev/w/acme"]
    #expect(owningWorktree(of: "/Users/dev/w/acme-triage/ios", worktreePaths: w) == "/Users/dev/w/acme-triage")
    #expect(owningWorktree(of: "/Users/dev/w/acme-triage/.claude/worktrees/x", worktreePaths: w) == nil)
    #expect(owningWorktree(of: "/Users/dev", worktreePaths: w) == nil)
}
@Test func simAIsDirectAndCheckoutOwned() {
    let e = liveEvidence(sim: simA, simRoot: 14986, checkout: mainCheckout, worktreePaths: paths, facts: facts())
    #expect(e.contains { if case .direct(25901, _, let s?) = $0 { s.pid == 25816 } else { false } })
    #expect(e.contains { if case .checkout(let s) = $0 { s.pid == 25816 } else { false } })
    #expect(!e.contains { if case .direct(15002, _, _) = $0 { true } else { false } })     // its own app process
}
@Test func simBHasNoLiveOwner() {      // DTServiceHub daemon, Simanager's own simctl child, shell in a nested worktree
    #expect(liveEvidence(sim: simB, simRoot: 18532, checkout: triageCheckout, worktreePaths: paths, facts: facts()).isEmpty)
}
