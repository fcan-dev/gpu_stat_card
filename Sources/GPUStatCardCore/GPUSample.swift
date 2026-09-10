import Foundation

public struct GPUSample: Equatable, Sendable {
    public var name: String?
    public var tempC: Int?
    public var fanPct: Int?
    public var vramUsedMiB: Int?
    public var vramTotalMiB: Int?
    public var powerW: Double?
    public var powerLimitW: Double?
    public var utilizationPct: Int?

    public init(name: String? = nil, tempC: Int? = nil, fanPct: Int? = nil,
                vramUsedMiB: Int? = nil, vramTotalMiB: Int? = nil,
                powerW: Double? = nil, powerLimitW: Double? = nil,
                utilizationPct: Int? = nil) {
        self.name = name
        self.tempC = tempC
        self.fanPct = fanPct
        self.vramUsedMiB = vramUsedMiB
        self.vramTotalMiB = vramTotalMiB
        self.powerW = powerW
        self.powerLimitW = powerLimitW
        self.utilizationPct = utilizationPct
    }

    /// VRAM used fraction (0…1), nil when total is unknown/zero.
    public var vramPct: Double? {
        guard let used = vramUsedMiB, let total = vramTotalMiB, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    /// Power draw fraction of the limit (0…1), nil when limit is unknown/zero.
    public var powerPct: Double? {
        guard let draw = powerW, let limit = powerLimitW, limit > 0 else { return nil }
        return draw / limit
    }
}
