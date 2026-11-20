import AppKit
import Darwin
import SimanagerCore

/// Device Hub or Simulator.app, when running.
struct AppRow: Identifiable, Hashable {
    let id: pid_t
    let name: String
}

struct MachineStats {
    let swapUsed: UInt64
    let swapTotal: UInt64
    var swapFraction: Double { swapTotal == 0 ? 0 : Double(swapUsed) / Double(swapTotal) }
}

/// Everything that reads the machine. Parsing and deciding live in SimanagerCore.
enum SystemProbe {
    static let lanesURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/simanager/lanes.json")

    /// `lanes == nil` means lanes.json could not be read: the probe is marked failed, so nothing is reaped on its word.
    static func capture(lanes: [LaneRule]?) async -> RawProbe {
        async let simctl = runCommand("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        async let testing = runCommand("/usr/bin/xcrun", ["simctl", "--set", "testing", "list", "devices", "-j"])
        async let ps = runCommand("/bin/ps", ["-axww", "-o", "pid=,ppid=,tty=,etime=,command="])
        async let lsof = runCommand("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn"])
        async let laneProbes = probeLanes(lanes)

        let psText = await ps.flatMap { $0.status == 0 ? String(decoding: $0.stdout, as: UTF8.self) : nil }
        let procs = psText.map(parsePS) ?? []

        // Session files name the Claude processes; their environments may name more config directories.
        var sessionFiles = loadSessionFiles(in: configDirs(env: [:]))
        var env: [Int32: [String: String]] = [:]
        for pid in sessionCandidatePIDs(procs, sessionFiles: sessionFiles) {
            if let e = procArgs(pid).flatMap(parseProcArgs2)?.env { env[pid] = e }
        }
        for (pid, e) in env {       // a session's own config directory wins
            guard let dir = e["CLAUDE_CONFIG_DIR"] else { continue }
            let file = URL(fileURLWithPath: dir).appendingPathComponent("sessions/\(pid).json")
            if let s = (try? Data(contentsOf: file)).flatMap(parseSessionFile) { sessionFiles[pid] = s }
        }

        var layouts: [String: String] = [:]
        if let zellij {
            for name in Set(env.values.compactMap { $0["ZELLIJ_SESSION_NAME"] }) {
                if let r = await runCommand(zellij, ["-s", name, "action", "dump-layout"], timeout: 5), r.status == 0 {
                    layouts[name] = String(decoding: r.stdout, as: UTF8.self)
                }
            }
        }

        let lsofOut = await lsof.map { String(decoding: $0.stdout, as: UTF8.self) }    // exit 1 with output is normal
        return RawProbe(simctl: await simctl.flatMap { $0.status == 0 ? $0.stdout : nil },
                        testing: await testing.flatMap { $0.status == 0 && !$0.stdout.isEmpty ? $0.stdout : nil },
                        ps: psText, lsof: lsofOut.flatMap { $0.isEmpty ? nil : $0 },
                        lanes: await laneProbes, env: env, sessionFiles: sessionFiles, zellijLayouts: layouts,
                        ownPID: getpid(), taken: Date())
    }

    private static func probeLanes(_ rules: [LaneRule]?) async -> [LaneProbe] {
        guard let rules else { return [LaneProbe(rule: LaneRule(namePrefix: "", repo: "", mainTag: ""), worktrees: nil)] }
        var out: [LaneProbe] = []
        for rule in rules {
            // lsof reports resolved paths, so worktree paths are resolved before they are compared.
            let canonical = LaneRule(namePrefix: rule.namePrefix, repo: resolved(rule.repo), mainTag: rule.mainTag)
            let r = await runCommand("/usr/bin/git", ["-C", rule.repo, "worktree", "list", "--porcelain"])
            let trees = r.flatMap { $0.status == 0 ? parseWorktrees(String(decoding: $0.stdout, as: UTF8.self)) : nil }
            out.append(LaneProbe(rule: canonical, worktrees: trees?.map { Worktree(path: resolved($0.path), branch: $0.branch) }))
        }
        return out
    }

    private static func resolved(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    private static let zellij: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/zellij", "/usr/local/bin/zellij", home + "/.cargo/bin/zellij"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }()

    /// Every `~/.claude*` directory with a `sessions` or `projects` folder, plus any `CLAUDE_CONFIG_DIR` in a captured environment.
    static func configDirs(env: [Int32: [String: String]]) -> [URL] {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        var dirs = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(".claude") }
        dirs += env.values.compactMap { $0["CLAUDE_CONFIG_DIR"] }.map { URL(fileURLWithPath: $0) }
        var seen: Set<String> = []
        return dirs.map { $0.resolvingSymlinksInPath() }.filter { dir in
            seen.insert(dir.path).inserted && ["sessions", "projects"].contains {
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: dir.appendingPathComponent($0).path, isDirectory: &isDir) && isDir.boolValue
            }
        }
    }

    private static func loadSessionFiles(in dirs: [URL]) -> [Int32: ClaudeSessionFile] {
        var out: [Int32: ClaudeSessionFile] = [:]
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                guard let pid = Int32(file.deletingPathExtension().lastPathComponent), out[pid] == nil,
                      let s = (try? Data(contentsOf: file)).flatMap(parseSessionFile) else { continue }
                out[pid] = s
            }
        }
        return out
    }

    /// The `KERN_PROCARGS2` buffer: argv and environment of a process this user owns.
    private static func procArgs(_ pid: Int32) -> Data? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Data(buffer[0..<size])
    }

    /// Physical footprint, the figure Activity Monitor shows as Memory.
    static func footprint(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }

    static func stats() -> MachineStats {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return MachineStats(swapUsed: usage.xsu_used, swapTotal: usage.xsu_total)
    }

    static func simulatorApps() -> [AppRow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.iphonesimulator" || $0.bundleURL?.lastPathComponent == "DeviceHub.app" }
            .map { AppRow(id: $0.processIdentifier, name: $0.localizedName ?? "Simulator") }
    }

    /// Writes the seed when the file is missing; never overwrites an existing file, readable or not.
    static func loadLanes() -> Result<LanesFile, Error> {
        let fm = FileManager.default
        if !fm.fileExists(atPath: lanesURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try? fm.createDirectory(at: lanesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoder.encode(LanesFile.seed).write(to: lanesURL)
            return .success(.seed)
        }
        return Result { try JSONDecoder().decode(LanesFile.self, from: Data(contentsOf: lanesURL)) }
    }
}
