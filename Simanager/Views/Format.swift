import Foundation

enum Format {
    static func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824) }

    static func uptime(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        let m = Int(seconds) / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d)d \(h % 24)h" }
        if h > 0 { return "\(h)h \(m % 60)m" }
        return "\(m)m"
    }

    static func path(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
