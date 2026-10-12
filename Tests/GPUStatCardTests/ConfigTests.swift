import XCTest
import GPUStatCardCore

/// Tests for the local config file: new `hosts`/`active_host` schema,
/// backward compatibility with the legacy single-`host` schema, and
/// validation/fallback rules. All tests use a temp file, never the real
/// `~/.config/gpu-stat-card/config.json`.
final class ConfigTests: XCTestCase {
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

    func testNewSchema_loadsHostsAndActiveHost() {
        writeJSON([
            "hosts": ["alpha", "beta"],
            "active_host": "beta",
            "refresh_seconds": 10,
        ])
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.hosts, ["alpha", "beta"])
        XCTAssertEqual(cfg.activeHost, "beta")
        XCTAssertEqual(cfg.host, "beta")
        XCTAssertEqual(cfg.refreshSeconds, 10)
        XCTAssertNil(cfg.note)
    }

    func testLegacyHostFile_migratesToSingleHostAndRewritesFile() {
        writeJSON(["host": "gpu-server", "refresh_seconds": 8])
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.hosts, ["gpu-server"])
        XCTAssertEqual(cfg.activeHost, "gpu-server")
        XCTAssertEqual(cfg.refreshSeconds, 8)

        // The legacy file is rewritten in place to the new schema.
        let raw = (try? JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL))) as? [String: Any]
        XCTAssertNotNil(raw?["hosts"] as? [String])
        XCTAssertNil(raw?["host"])
        XCTAssertEqual((raw?["refresh_seconds"] as? NSNumber)?.intValue, 8)
    }

    func testCommaJoinedHostEntry_isSplitIntoSeparateHostsAndFileSelfHeals() {
        // Users often write "a,b" as one entry; a valid SSH destination
        // never contains a comma, so split it and heal the file.
        writeJSON([
            "hosts": ["alpha, beta"],
            "active_host": "alpha",
            "refresh_seconds": 5,
        ])
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.hosts, ["alpha", "beta"])
        XCTAssertEqual(cfg.activeHost, "alpha")
        let raw = (try? JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL))) as? [String: Any]
        XCTAssertEqual(raw?["hosts"] as? [String], ["alpha", "beta"])
    }

    func testActiveHostNotInHosts_fallsBackToFirstHost() {
        writeJSON([
            "hosts": ["alpha", "beta"],
            "active_host": "gamma",
            "refresh_seconds": 5,
        ])
        XCTAssertEqual(Config.load(at: configURL).activeHost, "alpha")
    }

    func testMissingActiveHost_defaultsToFirstHost() {
        writeJSON(["hosts": ["alpha", "beta"], "refresh_seconds": 5])
        XCTAssertEqual(Config.load(at: configURL).activeHost, "alpha")
    }

    func testEmptyHostsFallsBackToDefaultWithNote() {
        writeJSON(["hosts": [], "refresh_seconds": 5])
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.host, Config.defaultHost)
        XCTAssertNotNil(cfg.note)
    }

    func testMissingFile_createsDefaultAndWritesIt() {
        let cfg = Config.load(at: configURL)
        XCTAssertEqual(cfg.host, Config.defaultHost)
        XCTAssertEqual(cfg.hosts, [Config.defaultHost])
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testWriteThenLoad_roundTripsHostsAndActiveHost() {
        var cfg = Config.load(at: configURL)
        cfg.hosts = ["alpha", "beta"]
        cfg.activeHost = "beta"
        Config.write(cfg, to: configURL)
        let reloaded = Config.load(at: configURL)
        XCTAssertEqual(reloaded.hosts, ["alpha", "beta"])
        XCTAssertEqual(reloaded.activeHost, "beta")
        XCTAssertNil(reloaded.note)
    }

    func testRefreshSeconds_clampedToValidRange() {
        writeJSON(["hosts": ["alpha"], "refresh_seconds": 9999])
        XCTAssertEqual(Config.load(at: configURL).refreshSeconds, 60)
        writeJSON(["hosts": ["alpha"], "refresh_seconds": 1])
        XCTAssertEqual(Config.load(at: configURL).refreshSeconds, 2)
    }
}
