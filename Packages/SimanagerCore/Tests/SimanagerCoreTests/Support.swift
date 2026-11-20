import Foundation
import SimanagerCore

let A = "AAAAAAAA-1111-4111-8111-00000000000A"
let B = "BBBBBBBB-2222-4222-8222-00000000000B"
let C = "CCCCCCCC-3333-4333-8333-00000000000C"

func fixture(_ name: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(name))
}
func fixtureText(_ name: String) -> String { String(decoding: fixture(name), as: UTF8.self) }

/// A KERN_PROCARGS2 buffer: argc, exec path, NUL padding, argv, env, empty string.
func makeProcArgs2(exec: String, argv: [String], env: [String]) -> Data {
    var d = withUnsafeBytes(of: Int32(argv.count)) { Data($0) }
    d.append(contentsOf: exec.utf8); d.append(contentsOf: [0, 0, 0, 0])
    for s in argv + env { d.append(contentsOf: s.utf8); d.append(0) }
    d.append(0)
    return d
}

// MARK: the fixture world's values that are not in files

let acmeRepo = "/Users/dev/projects/acme-app"
let acmeLane = LaneRule(namePrefix: "ACME", repo: acmeRepo, mainTag: "main")
let simA = SimDevice(udid: A, name: "ACME main iOS 27 - iPhone 17 Pro", runtime: "iOS 27.0", isTestClone: false)
let simB = SimDevice(udid: B, name: "ACME acme-triage shard 2 - iPhone 17 Pro", runtime: "iOS 26.4", isTestClone: false)
let mainCheckout = Checkout(path: acmeRepo, branch: "acme-764-feedback")
let triageCheckout = Checkout(path: "/Users/dev/w/acme-triage", branch: nil)
var paths: [String] { parseWorktrees(fixtureText("worktrees.txt")).map(\.path) }

let fixtureEnv: [Int32: [String: String]] = [25816: ["ZELLIJ_SESSION_NAME": "acme", "ZELLIJ_PANE_ID": "1", "TERM_PROGRAM": "ghostty"]]
var fixtureSessionFiles: [Int32: ClaudeSessionFile] {
    [25816: parseSessionFile(fixture("session.json"))!,
     77208: ClaudeSessionFile(pid: 77208, sessionId: "aaaaaaaa-0000-0000-0000-000000000001", name: "simanager", status: nil, kind: nil)]
}
var fixtureLanes: [LaneProbe] { [LaneProbe(rule: acmeLane, worktrees: parseWorktrees(fixtureText("worktrees.txt")))] }

func facts(tabs: [String: [String: String]]? = nil) -> ProcessFacts {
    ProcessFacts(table: ProcTable(parsePS(fixtureText("ps.txt"))), cwd: parseLsofCwd(fixtureText("lsof.txt")), env: fixtureEnv,
                 sessionFiles: fixtureSessionFiles,
                 zellijTabs: tabs ?? ["acme": parseZellijTabs(fixtureText("zellij-layout.kdl"))], ownPID: 4242)
}

func rawProbe(simctl: Data? = fixture("simctl-devices.json"), testing: Data? = nil,
              ps: String? = fixtureText("ps.txt"), lsof: String? = fixtureText("lsof.txt"),
              lanes: [LaneProbe] = fixtureLanes) -> RawProbe {
    RawProbe(simctl: simctl, testing: testing, ps: ps, lsof: lsof, lanes: lanes, env: fixtureEnv,
             sessionFiles: fixtureSessionFiles, zellijLayouts: ["acme": fixtureText("zellij-layout.kdl")],
             ownPID: 4242, taken: Date(timeIntervalSince1970: 1_795_000_000))
}
