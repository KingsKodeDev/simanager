import Foundation
import os

struct ShellResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

/// Runs an executable with an argument array (never a shell string). `nil` = could not launch, or timed out and was terminated.
func runCommand(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10,
                environment: [String: String]? = nil) async -> ShellResult? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { continuation.resume(returning: nil); return }

            let timedOut = OSAllocatedUnfairLock(initialState: false)
            let killer = DispatchWorkItem {
                guard process.isRunning else { return }
                timedOut.withLock { $0 = true }
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

            // Drain stderr on its own queue so a full pipe cannot block the child.
            let errData = OSAllocatedUnfairLock(initialState: Data())
            let errDone = DispatchGroup()
            errDone.enter()
            DispatchQueue.global(qos: .utility).async {
                let d = err.fileHandleForReading.readDataToEndOfFile()
                errData.withLock { $0 = d }
                errDone.leave()
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            errDone.wait()
            process.waitUntilExit()
            killer.cancel()
            continuation.resume(returning: timedOut.withLock { $0 } ? nil
                : ShellResult(status: process.terminationStatus, stdout: outData,
                              stderr: String(decoding: errData.withLock { $0 }, as: UTF8.self)))
        }
    }
}
