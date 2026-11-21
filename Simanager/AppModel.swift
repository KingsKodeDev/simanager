import AppKit
import Observation
import ServiceManagement
import SimanagerCore

@MainActor @Observable final class AppModel {
    var snapshot: Snapshot?
    /// The last snapshot every probe succeeded for; shown while a newer one is incomplete.
    var lastComplete: Snapshot?
    var apps: [AppRow] = []
    var stats: MachineStats?
    var lanesError: String?
    /// True while a confirmation is open, so the row under the pointer cannot change.
    var isPaused: Bool { confirmRequest != nil || bulkAction != nil || quitRequest != nil }

    // MARK: actions

    var confirmRequest: ConfirmRequest?
    var bulkAction: SimAction?
    var quitRequest: AppRow?
    private(set) var pinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedUDIDs") ?? [])
    /// The last command a Claude session ran against each simulator, filled by history scans.
    private(set) var history: [String: HistoryHit] = [:]
    private(set) var historyScannedAt: [String: Date] = [:]
    /// A count, not a flag: the reaper's scan and one asked for by hand can overlap.
    private var activeScans = 0
    var isScanning: Bool { activeScans > 0 }
    /// Newest first, capped at 100.
    private(set) var activity: [ActivityEntry] = (UserDefaults.standard.data(forKey: "activity"))
        .flatMap { try? JSONDecoder().decode([ActivityEntry].self, from: $0) } ?? []
    private(set) var rowErrors: [String: String] = [:]

    // MARK: auto-reaping

    private(set) var reapSettings = AppModel.loadReapSettings()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?
    /// How long each simulator has gone without a live owner, as seen by this run of the app.
    private var clock = ReapClock()
    @ObservationIgnored private var isReaping = false
    @ObservationIgnored private var loggedScanFailure = false
    /// A history scan greps a week of transcripts; one that keeps failing is not retried every refresh.
    @ObservationIgnored private var scanBackoff = Backoff()
    /// The newest probe, kept even while a confirmation freezes `snapshot`; actions are checked against this one.
    @ObservationIgnored private var newest: Snapshot?

    @ObservationIgnored private var runningSessions: [String: String?] = [:]
    @ObservationIgnored private var configDirs: [URL] = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var napGuard: NSObjectProtocol?

    /// What the table shows: the newest snapshot, or the last complete one while a probe is failing.
    var shown: Snapshot? { snapshot?.complete == true ? snapshot : lastComplete ?? snapshot }
    var isStale: Bool { snapshot?.complete == false }
    /// Names of the probes that failed in the newest refresh, for the header.
    var failedProbes: [String] = []

    nonisolated static func failedProbes(_ raw: RawProbe) -> [String] {
        var out: [String] = []
        if raw.simctl == nil { out.append("simctl list") }
        if raw.ps == nil { out.append("ps") }
        if raw.lsof == nil { out.append("lsof") }
        out += raw.lanes.filter { $0.worktrees == nil }.map { $0.rule.repo.isEmpty ? "lanes.json" : "git worktree list in \($0.rule.repo)" }
        return out
    }

    func start() {
        guard loop == nil else { return }
        // Without this, App Nap may stretch the 5 s loop once the window is closed; gaps over 15 s reset every
        // idle clock, and nothing would ever be reaped from the menu bar.
        napGuard = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Watching simulators and reaping abandoned ones")
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refreshNow() async {
        let lanes = SystemProbe.loadLanes()
        switch lanes {
        case .success: lanesError = nil
        case .failure(let error): lanesError = "lanes.json could not be read (\(error.localizedDescription)). Checkouts are not shown until it is fixed."
        }
        let rules = try? lanes.get().lanes
        let (snap, failed, running, dirs) = await Task.detached(priority: .utility) {
            let raw = await SystemProbe.capture(lanes: rules)
            // Session ids of Claude processes that are alive now, for "is that session still running".
            let running = Dictionary(raw.sessionFiles.values.filter { kill($0.pid, 0) == 0 || errno == EPERM }
                .map { ($0.sessionId, $0.name) }, uniquingKeysWith: { a, _ in a })
            return (buildSnapshot(raw, footprint: SystemProbe.footprint), Self.failedProbes(raw), running,
                    SystemProbe.configDirs(env: raw.env))
        }.value
        // Every snapshot feeds the idle clocks, incomplete ones included: that is what clears them.
        clock.observe(snap)
        newest = snap
        runningSessions = running
        configDirs = dirs
        // While a confirmation is open the table is frozen, so the row under the pointer cannot change.
        guard !isPaused else { return }
        snapshot = snap
        failedProbes = failed
        if snap.complete { lastComplete = snap }
        stats = SystemProbe.stats()
        apps = SystemProbe.simulatorApps()
        Task { await reapIfDue() }      // not awaited: a history scan must not hold up the next refresh
    }
}

// MARK: - Actions

struct ConfirmRequest: Identifiable {
    let row: SimRow
    let action: SimAction
    var id: String { row.id + action.rawValue }
}

struct ActivityEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let time: Date
    let simulator: String
    let action: String
    let automatic: Bool
    let reason: String?
    let error: String?
}

extension SimAction {
    var title: String { self == .shutdown ? "Shut down" : "Delete" }
}

extension AppModel {
    func setPinned(_ udid: String, _ on: Bool) {
        if on { pinned.insert(udid) } else { pinned.remove(udid) }
        UserDefaults.standard.set(pinned.sorted(), forKey: "pinnedUDIDs")
    }

    /// `nil` = every row. False when the scan failed: history is then unknown, not empty.
    @discardableResult func scanHistory(for udids: [String]?) async -> Bool {
        let rows = (shown?.rows ?? []).filter { udids?.contains($0.id) ?? true }
        activeScans += 1
        defer { activeScans -= 1 }
        guard let hits = await HistoryScanner.scan(targets: rows.map { HistoryTarget(udid: $0.id, checkoutPath: $0.checkout?.path) },
                                                   running: runningSessions, configDirs: configDirs) else { return false }
        let now = Date()
        for row in rows {
            history[row.id] = hits[row.id]
            historyScannedAt[row.id] = now
        }
        return true
    }

    func perform(_ action: SimAction, udid: String, automatic: Bool, reason: String?) async {
        await run(action, udid: udid, automatic: automatic, reason: reason)
        await refreshNow()
    }

    /// Runs one after another; one failure does not stop the rest.
    func performAll(_ action: SimAction, targets: [SimRow]) async {
        for row in targets { await run(action, udid: row.id, automatic: false, reason: nil) }
        await refreshNow()
    }

    private func run(_ action: SimAction, udid: String, automatic: Bool, reason: String?) async {
        let name = shown?.rows.first { $0.id == udid }?.device.name ?? udid
        let error: String?
        // Built only for a well-formed UDID that is booted in the newest probe, which is newer than the table
        // while a confirmation holds it frozen.
        if let newest, let arguments = simctlArguments(action, udid: udid, in: newest) {
            error = switch await runCommand("/usr/bin/xcrun", arguments, timeout: 60) {
            case nil: "simctl did not finish in 60 s"
            case let r? where r.status != 0:
                r.stderr.split(separator: "\n").last.map(String.init) ?? "simctl exited with status \(r.status)"
            default: nil
            }
        } else {
            // Logged below as well: the row has usually left the table, so a row error alone would never be seen.
            error = newest?.complete == false ? "not done: a probe failed, so it could not be confirmed as booted" : "no longer booted"
        }
        rowErrors[udid] = error
        log(ActivityEntry(id: UUID(), time: Date(), simulator: name, action: action.title, automatic: automatic, reason: reason, error: error))
    }

    func log(_ entry: ActivityEntry) {
        activity = Array(([entry] + activity).prefix(100))
        UserDefaults.standard.set(try? JSONEncoder().encode(activity), forKey: "activity")
    }

    /// Asks the app to quit normally; never force-quits.
    func quit(_ app: AppRow) {
        NSRunningApplication(processIdentifier: app.id)?.terminate()
        log(ActivityEntry(id: UUID(), time: Date(), simulator: app.name, action: "Quit", automatic: false, reason: nil, error: nil))
    }
}

// MARK: - Auto-reaping

extension AppModel {
    /// Registered defaults, so `-reapEnabled NO` on the command line overrides them.
    nonisolated static func loadReapSettings() -> ReapSettings {
        let d = UserDefaults.standard, base = ReapSettings.default
        d.register(defaults: ["reapEnabled": base.enabled, "reapIdlePeriod": base.idlePeriod, "reapAction": base.action.rawValue])
        let period = d.double(forKey: "reapIdlePeriod")
        return ReapSettings(enabled: d.bool(forKey: "reapEnabled"),
                            idlePeriod: ReapSettings.idlePeriods.contains(period) ? period : base.idlePeriod,
                            action: SimAction(rawValue: d.string(forKey: "reapAction") ?? "") ?? base.action)
    }

    func updateReapSettings(_ change: (inout ReapSettings) -> Void) {
        change(&reapSettings)
        let d = UserDefaults.standard
        d.set(reapSettings.enabled, forKey: "reapEnabled")
        d.set(reapSettings.idlePeriod, forKey: "reapIdlePeriod")
        d.set(reapSettings.action.rawValue, forKey: "reapAction")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch { launchAtLoginError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Seconds until this simulator is reaped; `nil` when it has a live owner, is pinned, or auto-reap is off.
    func reapsIn(_ udid: String) -> TimeInterval? {
        clock.reapsIn(udid, pinned: pinned, settings: reapSettings, now: Date())
    }

    /// Reaps what has been ownerless for the idle period, after a history scan confirms no running session used it.
    private func reapIfDue() async {
        guard !isPaused, !isReaping else { return }
        let due = clock.due(pinned: pinned, settings: reapSettings, now: Date())
        guard !due.isEmpty, scanBackoff.ready(now: Date()) else { return }
        isReaping = true
        defer { isReaping = false }
        guard await scanHistory(for: due) else {
            scanBackoff.failed(now: Date())
            // Unknown history is not "no history": nothing is reaped on a failed scan.
            if !loggedScanFailure {
                log(ActivityEntry(id: UUID(), time: Date(), simulator: "Auto-reap", action: "Skipped", automatic: true,
                                  reason: "history scan failed, not reaped", error: nil))
                loggedScanFailure = true
            }
            return
        }
        loggedScanFailure = false
        scanBackoff.succeeded()
        for udid in due {
            // The scan and each earlier action took time. Ask again at the moment of acting: a pin, the off switch,
            // a new owner or a failed probe since the list was made each take the simulator off it.
            guard !isPaused, clock.due(pinned: pinned, settings: reapSettings, now: Date()).contains(udid) else { continue }
            switch reapVerdict(hit: history[udid], settings: reapSettings, now: Date()) {
            case .wait(let resetTo): clock.reset(udid, to: resetTo)
            case .reap:
                await perform(reapSettings.action, udid: udid, automatic: true,
                              reason: "no live owner for \(Int(reapSettings.idlePeriod / 60)) min")
            }
        }
    }
}
