import Foundation

public struct Config: Equatable {
    public var host: String
    public var refreshSeconds: Int
    /// Non-nil when the file was auto-created or was invalid (shown in the card).
    public var note: String?

    public init(host: String, refreshSeconds: Int, note: String? = nil) {
        self.host = host
        self.refreshSeconds = refreshSeconds
        self.note = note
    }

    public static let defaultHost = "gpu-server"
    public static let defaultRefresh = 5

    public static let defaultConfigURL: URL =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gpu-stat-card/config.json")

    private static let minRefresh = 2
    private static let maxRefresh = 60

    public static func load(at url: URL = defaultConfigURL) -> Config {
        if !FileManager.default.fileExists(atPath: url.path) {
            let def = Config(host: defaultHost, refreshSeconds: defaultRefresh,
                             note: "Created default config at \(url.path). Edit it to change the SSH host.")
            write(def, to: url)
            return def
        }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = obj["host"] as? String, !host.isEmpty else {
            return Config(host: defaultHost, refreshSeconds: defaultRefresh,
                          note: "Config at \(url.path) is invalid; using default host.")
        }
        let rawRefresh = (obj["refresh_seconds"] as? NSNumber)?.intValue ?? defaultRefresh
        let refresh = min(max(rawRefresh, minRefresh), maxRefresh)
        return Config(host: host, refreshSeconds: refresh, note: nil)
    }

    public static func write(_ config: Config, to url: URL = defaultConfigURL) {
        guard let dir = url.deletingLastPathComponent() as URL? else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = ["host": config.host, "refresh_seconds": config.refreshSeconds]
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
