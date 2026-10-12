import Foundation

public struct Config: Equatable {
    /// The SSH destinations the card can switch between (shown by the toggle).
    public var hosts: [String]
    /// The host currently polled.
    public var activeHost: String
    public var refreshSeconds: Int
    /// Non-nil when the file was auto-created or was invalid (shown in the card).
    public var note: String?

    /// Convenience for code that polls a single destination.
    public var host: String { activeHost }

    public init(hosts: [String], activeHost: String? = nil,
                refreshSeconds: Int, note: String? = nil) {
        self.hosts = hosts
        self.activeHost = activeHost.flatMap { hosts.contains($0) ? $0 : nil }
            ?? hosts.first ?? Config.defaultHost
        self.refreshSeconds = refreshSeconds
        self.note = note
    }

    /// Legacy single-host initializer (pre-toggle configs).
    public init(host: String, refreshSeconds: Int, note: String? = nil) {
        self.init(hosts: [host], activeHost: host, refreshSeconds: refreshSeconds, note: note)
    }

    public static let defaultHost = "gpu-server"
    public static let defaultRefresh = 5

    /// Lives in the user's home dir — local to the machine, never part of the repo.
    public static let defaultConfigURL: URL =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gpu-stat-card/config.json")

    private static let minRefresh = 2
    private static let maxRefresh = 60

    public static func load(at url: URL = defaultConfigURL) -> Config {
        if !FileManager.default.fileExists(atPath: url.path) {
            let def = Config(host: defaultHost, refreshSeconds: defaultRefresh,
                             note: "Created default config at \(url.path). Edit it to change the SSH hosts.")
            write(def, to: url)
            return def
        }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Config(host: defaultHost, refreshSeconds: defaultRefresh,
                          note: "Config at \(url.path) is invalid; using default host.")
        }

        let rawHosts = obj["hosts"] as? [String] ?? []
        let legacyHost = obj["host"] as? String
        let original: [String]
        if !rawHosts.isEmpty {
            original = rawHosts
        } else if let legacyHost, !legacyHost.isEmpty {
            // Legacy single-`host` schema — accept it.
            original = [legacyHost]
        } else {
            return Config(host: defaultHost, refreshSeconds: defaultRefresh,
                          note: "Config at \(url.path) is invalid; using default host.")
        }
        let hosts = splitHosts(original)
        guard !hosts.isEmpty else {
            return Config(host: defaultHost, refreshSeconds: defaultRefresh,
                          note: "Config at \(url.path) is invalid; using default host.")
        }

        let rawRefresh = (obj["refresh_seconds"] as? NSNumber)?.intValue ?? defaultRefresh
        let refresh = min(max(rawRefresh, minRefresh), maxRefresh)
        let cfg = Config(hosts: hosts, activeHost: obj["active_host"] as? String,
                         refreshSeconds: refresh)

        // Self-heal: rewrite when the on-disk form needed normalization
        // (e.g. a comma-joined "a,b" entry) or is the legacy `host` schema.
        if hosts != original || (obj["hosts"] as? [String]) == nil {
            write(cfg, to: url)
        }
        return cfg
    }

    /// Splits comma-joined host entries ("a,b" → ["a", "b"]) and trims
    /// whitespace — a valid SSH destination never contains a comma.
    private static func splitHosts(_ raw: [String]) -> [String] {
        var result: [String] = []
        for entry in raw {
            for part in entry.components(separatedBy: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
            }
        }
        return result
    }

    public static func write(_ config: Config, to url: URL = defaultConfigURL) {
        guard let dir = url.deletingLastPathComponent() as URL? else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "hosts": config.hosts,
            "active_host": config.activeHost,
            "refresh_seconds": config.refreshSeconds,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
