import XCTest
import GPUStatCardCore

/// Fake nvidia-smi CSV line for a given temperature.
private func fakeCSV(tempC: Int) -> String {
    "RTX 4090, \(tempC), 30, 1024 MiB, 24564 MiB, 50.00 W, 350.00 W, 40 %"
}

/// A gate that blocks `waitUntilOpen()` on any thread until `open()` is
/// called. Used to hold a fake SSH poll in flight mid-poll.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false

    func close() {
        lock.lock()
        isOpen = false
        lock.unlock()
    }

    func waitUntilOpen() {
        while true {
            lock.lock()
            let open = isOpen
            lock.unlock()
            if open { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        lock.unlock()
    }
}

/// Tests for switching the polled SSH host from the card's toggle:
/// immediate switchover, persistence to the local config file, and
/// discarding of a stale result that belongs to the previous machine.
@MainActor
final class PollerHostSwitchTests: XCTestCase {
    private var tempDir: URL!
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpu-stat-card-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("config.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeJSON(_ obj: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        try! data.write(to: configURL)
    }

    /// Fake nvidia-smi: alpha answers with 60°C, beta with 75°C (or, when
    /// `betaFails`, beta's SSH fails with exit 255).
    private func makePoller(gate: Gate? = nil, betaFails: Bool = false) -> GPUPoller {
        GPUPoller(configURL: configURL, runCommand: { args, _ in
            let host = args[4]  // [-o, BatchMode=yes, -o, ConnectTimeout=5, host, query]
            if host == "alpha" {
                gate?.waitUntilOpen()
                return CommandResult(stdout: fakeCSV(tempC: 60), status: 0, timedOut: false)
            }
            return betaFails
                ? CommandResult(stdout: "", status: 255, timedOut: false)
                : CommandResult(stdout: fakeCSV(tempC: 75), status: 0, timedOut: false)
        })
    }

    func testPollOnce_usesActiveHostFromConfig() async {
        writeJSON(["hosts": ["alpha", "beta"], "active_host": "alpha", "refresh_seconds": 5])
        let poller = GPUPoller(configURL: configURL, runCommand: { args, _ in
            CommandResult(stdout: fakeCSV(tempC: 60), status: 0, timedOut: false)
        })
        await poller.pollOnce()
        XCTAssertEqual(poller.hosts, ["alpha", "beta"])
        XCTAssertEqual(poller.activeHost, "alpha")
        XCTAssertEqual(poller.sample?.tempC, 60)
    }

    func testSelectHost_switchesPollingAndPersistsToConfigFile() async {
        writeJSON(["hosts": ["alpha", "beta"], "active_host": "alpha", "refresh_seconds": 5])
        let poller = makePoller()
        await poller.pollOnce()
        XCTAssertEqual(poller.sample?.tempC, 60)

        poller.selectHost("beta")
        XCTAssertEqual(poller.activeHost, "beta")
        // The previous machine's last data is kept (dimmed/stale) — the card
        // does not blank out like a restart while the new host is contacted.
        XCTAssertEqual(poller.sample?.tempC, 60)
        XCTAssertTrue(poller.switching)
        XCTAssertTrue(poller.stale)
        // The choice is persisted to the local config file (survives relaunch).
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.activeHost, "beta")
        XCTAssertEqual(cfg.hosts, ["alpha", "beta"])

        // Until the new machine answers with its own data.
        for _ in 0..<100 where poller.sample?.tempC != 75 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(poller.sample?.tempC, 75)
        XCTAssertFalse(poller.switching)
        XCTAssertFalse(poller.stale)
        XCTAssertTrue(poller.ok)
    }

    func testConfigFileEdit_switchesHostKeepingDimmedLastData() async {
        // The user edits the config file directly; the next poll should
        // retarget like a toggle switch and keep the last data dimmed.
        writeJSON(["hosts": ["alpha", "beta"], "active_host": "alpha", "refresh_seconds": 5])
        let poller = makePoller(betaFails: true)
        await poller.pollOnce()
        XCTAssertEqual(poller.sample?.tempC, 60)

        writeJSON(["hosts": ["alpha", "beta"], "active_host": "beta", "refresh_seconds": 5])
        await poller.pollOnce()  // retargets to beta; beta is unreachable
        XCTAssertEqual(poller.activeHost, "beta")
        XCTAssertFalse(poller.switching)  // settled into the normal error state
        XCTAssertEqual(poller.sample?.tempC, 60)  // last data kept, dimmed
        XCTAssertTrue(poller.stale)
        XCTAssertFalse(poller.ok)
        XCTAssertEqual(poller.lastError, "SSH failed (exit 255)")
    }

    func testSelectHost_ignoresUnknownHost() async {
        writeJSON(["hosts": ["alpha", "beta"], "active_host": "alpha", "refresh_seconds": 5])
        let poller = makePoller()
        poller.selectHost("gamma")
        XCTAssertEqual(poller.activeHost, "alpha")
        XCTAssertEqual(Config.load(at: configURL).activeHost, "alpha")
    }

    func testPollInFlightWhenSwitched_keepsDimmedSampleAndDiscardsFreshResult() async {
        // Alpha's in-flight poll must not land as FRESH data after the switch
        // (that would show ok/stale=false with alpha's numbers under beta's
        // name). The last sample stays kept-and-dimmed until beta answers.
        writeJSON(["hosts": ["alpha", "beta"], "active_host": "alpha", "refresh_seconds": 5])
        let gate = Gate()
        let poller = makePoller(gate: gate, betaFails: true)

        // First, establish a completed poll so there IS last data.
        let firstPoll = Task { await poller.pollOnce() }  // blocks inside the fake SSH
        try? await Task.sleep(for: .milliseconds(100))    // let it reach the gate
        gate.open()
        await firstPoll.value
        XCTAssertEqual(poller.sample?.tempC, 60)

        // Now start a second alpha poll and switch while it is in flight.
        gate.close()
        let pollTask = Task { await poller.pollOnce() }   // blocks inside the fake SSH
        try? await Task.sleep(for: .milliseconds(100))    // let it reach the gate
        poller.selectHost("beta")
        gate.open()
        await pollTask.value

        // Give the switch's immediate (failed) beta poll a chance to finish.
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(poller.activeHost, "beta")
        XCTAssertEqual(poller.sample?.tempC, 60)  // kept, dimmed…
        XCTAssertTrue(poller.stale)               // …not applied as fresh data
        XCTAssertFalse(poller.ok)
    }
}
