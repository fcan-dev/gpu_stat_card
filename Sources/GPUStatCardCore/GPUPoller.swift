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
    public private(set) var configNote: String?

    /// Fixed `nvidia-smi` query; passed as a single ssh command argument.
    public static let query =
        "nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,memory.used,memory.total,power.draw,power.limit,utilization.gpu --format=csv,noheader"

    private let configProvider: @Sendable () -> Config
    private let timeout: TimeInterval
    private let runCommand: @Sendable ([String], TimeInterval) throws -> CommandResult
    private var task: Task<Void, Never>?

    public init(configProvider: @escaping @Sendable () -> Config = { Config.load() },
                timeout: TimeInterval = 10,
                runCommand: @escaping @Sendable ([String], TimeInterval) throws -> CommandResult =
                    { try GPUPoller.defaultRun(args: $0, timeout: $1) }) {
        self.configProvider = configProvider
        self.timeout = timeout
        self.runCommand = runCommand
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

    /// Runs one poll synchronously (SSH on a detached task) and updates state.
    public func pollOnce() async {
        let cfg = configProvider()
        configNote = cfg.note
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
