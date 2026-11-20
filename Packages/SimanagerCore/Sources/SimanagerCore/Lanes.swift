import Foundation

public struct LaneRule: Codable, Hashable, Sendable {
    public let namePrefix, repo, mainTag: String
    public init(namePrefix: String, repo: String, mainTag: String) {
        self.namePrefix = namePrefix; self.repo = repo; self.mainTag = mainTag
    }
}

public struct LanesFile: Codable, Sendable {
    public let lanes: [LaneRule]
    public init(lanes: [LaneRule]) { self.lanes = lanes }
    /// What a first launch writes: no lanes. Rules are per machine and added by hand.
    public static let seed = LanesFile(lanes: [])
}

/// `worktrees == nil` means `git worktree list` failed for this lane.
public struct LaneProbe: Sendable {
    public let rule: LaneRule
    public let worktrees: [Worktree]?
    public init(rule: LaneRule, worktrees: [Worktree]?) { self.rule = rule; self.worktrees = worktrees }
}

public struct Checkout: Hashable, Sendable {
    public let path: String
    public let branch: String?
    public init(path: String, branch: String?) { self.path = path; self.branch = branch }
}

/// The longest tag that is the whole text between `prefix` and " - ", or is followed there by a space.
public func matchTag(simName: String, prefix: String, tags: [String]) -> String? {
    guard simName.hasPrefix(prefix + " ") else { return nil }
    let rest = simName.dropFirst(prefix.count + 1)
    let text = rest.range(of: " - ").map { rest[..<$0.lowerBound] } ?? rest
    return tags.filter { text == $0 || text.hasPrefix($0 + " ") }.max { $0.count < $1.count }
}

public func resolveCheckout(simName: String, lanes: [LaneProbe]) -> Checkout? {
    for lane in lanes {
        guard let worktrees = lane.worktrees else { continue }
        let folder = { (w: Worktree) in (w.path as NSString).lastPathComponent }
        guard let tag = matchTag(simName: simName, prefix: lane.rule.namePrefix,
                                 tags: [lane.rule.mainTag] + worktrees.map(folder)) else { continue }
        let match = tag == lane.rule.mainTag ? worktrees.first { $0.path == lane.rule.repo }
                                             : worktrees.first { folder($0) == tag }
        if let match { return Checkout(path: match.path, branch: match.branch) }
    }
    return nil
}
