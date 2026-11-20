import Foundation
import SimanagerCore

/// Finds the last command a Claude session ran against each simulator, by streaming `grep` over recent transcripts.
/// Transcripts are about 2 GB a week: only matching lines are read, one at a time, and only the best hit per UDID is kept.
enum HistoryScanner {
    /// `nil` = the scan failed, which callers must treat as "unknown", never as "no history".
    static func scan(targets: [HistoryTarget], running: [String: String?], configDirs: [URL]) async -> [String: HistoryHit]? {
        guard !targets.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let files = recentTranscripts(in: configDirs)
            var best: [String: HistoryHit] = [:]
            for start in stride(from: 0, to: files.count, by: 200) {
                let ok = grep(Array(files[start..<min(start + 200, files.count)])) { line in
                    let hits = historyHits(parseTranscriptLine(line), targets: targets, running: running, home: home)
                    for (udid, hit) in hits where best[udid].map(hit.outranks) ?? true { best[udid] = hit }
                }
                if !ok { return nil }
            }
            return best
        }.value
    }

    /// `*.jsonl` under each config directory's `projects/`, modified in the last 7 days.
    private static func recentTranscripts(in dirs: [URL]) -> [String] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        var out: [String] = []
        for dir in dirs {
            guard let walker = FileManager.default.enumerator(at: dir.appendingPathComponent("projects"),
                                                              includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified >= cutoff { out.append(url.path) }
            }
        }
        return out
    }

    /// Feeds each matching line to `consume` as it arrives. False on a launch failure or grep status ≥ 2 (1 = no match, fine).
    private static func grep(_ files: [String], consume: (String) -> Void) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-h", "-F", "-e", transcriptGrepNeedle, "--"] + files
        process.environment = ["LC_ALL": "C"]       // byte matching: several times faster than a UTF-8 locale
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }

        var pending = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            var start = pending.startIndex
            while let newline = pending[start...].firstIndex(of: 0x0A) {
                consume(String(decoding: pending[start..<newline], as: UTF8.self))
                start = newline + 1
            }
            pending = Data(pending[start...])
        }
        if !pending.isEmpty { consume(String(decoding: pending, as: UTF8.self)) }
        process.waitUntilExit()
        return process.terminationStatus < 2
    }
}
