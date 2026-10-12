import Foundation
import Observation

public struct CommandResult: Sendable, Equatable {
    public var stdout: String
    public var status: Int32
    public var timedOut: Bool

    public init(stdout: String, status: Int32, timedOut: Bool) {
        self.stdout = stdout
        self.status = status
        self.timedOut = timedOut
    }
}

@MainActor
@Observable
public final class GPUPoller {
    public private(set) var sample: GPUSample?
    public private(set) var ok: Bool = false
    public private(set) var lastUpdated: Date?
    public private(set) var lastError: String?
    public private(set) var stale: Bool = false
    /// True while a host switch is in progress: the card keeps the last
    /// sample dimmed until the new host answers.
    public private(set) var switching: Bool = false
    public private(set) var configNote: String?
    /// The SSH destinations from the config (the card's toggle switches these).
    public private(set) var hosts: [String]
    /// The SSH destination currently polled.
    public private(set) var activeHost: String

    /// Position of `activeHost` in `hosts` (the toggle's switch state).
    public var activeIndex: Int { hosts.firstIndex(of: activeHost) ?? 0 }

    private var hostGeneration = 0
    private var pollInFlight = false

    /// Fixed `nvidia-smi` query; passed as a single ssh command argument.
    public static let query =
        "nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,memory.used,memory.total,power.draw,power.limit,utilization.gpu --format=csv,noheader"

    private let configURL: URL
    private let configProvider: @Sendable () -> Config
    private let timeout: TimeInterval
    private let runCommand: @Sendable ([String], TimeInterval) throws -> CommandResult
    private var task: Task<Void, Never>?

    public convenience init(configURL: URL = Config.defaultConfigURL,
                            timeout: TimeInterval = 10,
                            runCommand: @escaping @Sendable ([String], TimeInterval) throws -> CommandResult =
                                { try GPUPoller.defaultRun(args: $0, timeout: $1) }) {
        self.init(configURL: configURL,
                  configProvider: { Config.load(at: configURL) },
                  timeout: timeout,
                  runCommand: runCommand)
    }

    public init(configURL: URL = Config.defaultConfigURL,
                configProvider: @escaping @Sendable () -> Config = { Config.load() },
                timeout: TimeInterval = 10,
                runCommand: @escaping @Sendable ([String], TimeInterval) throws -> CommandResult =
                    { try GPUPoller.defaultRun(args: $0, timeout: $1) }) {
        self.configURL = configURL
        self.configProvider = configProvider
        self.timeout = timeout
        self.runCommand = runCommand
        let initial = configProvider()
        self.hosts = initial.hosts
        self.activeHost = initial.host
        self.configNote = initial.note
    }

    /// Starts the polling loop (idempotent).
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.pollOnce()
                let secs = TimeInterval(self.configProvider().refreshSeconds)
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Switches the polled host: persists the choice to the local config file
    /// (survives relaunch), clears the previous machine's sample, and polls
    /// the new host immediately (skipped if a poll is already in flight — the
    /// poll loop picks the new host up on its next iteration then).
    public func selectHost(_ host: String) {
        guard hosts.contains(host), host != activeHost else { return }
        var cfg = Config.load(at: configURL)
        guard cfg.hosts.contains(host) else { return }
        cfg.activeHost = host
        Config.write(cfg, to: configURL)

        hostGeneration &+= 1
        activeHost = host
        beginSwitch()
        Task { [weak self] in await self?.pollOnce() }
    }

    /// Marks a switch as in progress: the previous machine's last sample is
    /// kept (dimmed via `stale`) instead of blanking the card.
    private func beginSwitch() {
        switching = true
        stale = true
        ok = false
        lastError = nil
    }

    /// Runs one poll synchronously (SSH on a detached task) and updates state.
    public func pollOnce() async {
        guard !pollInFlight else { return }
        pollInFlight = true
        defer { pollInFlight = false }

        let generation = hostGeneration
        let cfg = configProvider()
        if cfg.activeHost != activeHost {
            // The host changed via a config-file edit — treat it like a
            // toggle switch (dim the last data while the new host is hit).
            beginSwitch()
        }
        lastUpdated = Date()

        let args = Self.makeArgs(host: cfg.host)
        let result: CommandResult
        do {
            result = try await Task.detached { [runCommand, timeout] in
                try runCommand(args, timeout)
            }.value
        } catch {
            result = CommandResult(stdout: "", status: -1, timedOut: false)
        }

        // A host switch happened while this poll was in flight: the result
        // belongs to the previous machine, so discard it entirely.
        guard generation == hostGeneration else { return }

        hosts = cfg.hosts
        activeHost = cfg.activeHost
        configNote = cfg.note

        switching = false
        if result.timedOut || result.status != 0 {
            ok = false
            stale = true
            lastError = result.timedOut ? "Timed out" : "SSH failed (exit \(result.status))"
        } else if let parsed = CSVParser.parse(result.stdout) {
            sample = parsed
            ok = true
            stale = false
            lastError = nil
        } else {
            ok = false
            stale = true
            lastError = "Unexpected nvidia-smi output"
        }
    }

    public static func makeArgs(host: String) -> [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, query]
    }

    /// Runs `/usr/bin/ssh` with the given args, enforcing a hard timeout.
    /// `nonisolated` so it can be used as a `@Sendable` default without
    /// inheriting MainActor isolation from the enclosing class.
    public nonisolated static func defaultRun(args: [String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        let outPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = Pipe()  // discard stderr
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            process.waitUntilExit()
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(stdout: stdout, status: process.terminationStatus, timedOut: timedOut)
    }
}
