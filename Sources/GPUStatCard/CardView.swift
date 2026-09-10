import SwiftUI
import AppKit
import GPUStatCardCore

struct CardView: View {
    @Bindable var poller: GPUPoller
    @Bindable var interaction: MenuBarInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HairlineDivider()
            content
            if let note = poller.configNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HairlineDivider()
            footer
        }
        .padding(14)
        .frame(width: 260)
        .onHover { inside in
            interaction.insidePopover = inside
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(poller.sample?.name ?? "GPU")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        if poller.sample == nil { return .gray }
        return poller.ok ? .green : .red
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(Config.load().host)
        if let last = poller.lastUpdated {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            parts.append(f.string(from: last))
        }
        if !poller.ok { parts.append("unreachable") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if let s = poller.sample {
            tempRow(s)
            HStack(spacing: 10) {
                BigRingTile(
                    title: "Power", icon: "bolt.fill",
                    fraction: s.powerPct ?? 0, color: Color.power(s.powerPct),
                    centerText: powerDrawText(s),
                    centerTextColor: Color.power(s.powerPct),
                    caption: powerCaption(s), active: poller.ok)
                BigRingTile(
                    title: "VRAM", icon: "memorychip",
                    fraction: s.vramPct ?? 0, color: .blue,
                    centerText: ringPercent(s.vramPct),
                    caption: vramText(s), active: poller.ok)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                metricRow(icon: "fan", label: "Fan",
                          value: s.fanPct.map { "\($0) %" } ?? "—")
                metricRow(icon: "gauge.with.dots.needle.50percent", label: "Utilization",
                          value: s.utilizationPct.map { "\($0) %" } ?? "—")
            }
        } else if poller.lastError != nil && poller.lastUpdated != nil {
            Label("Waiting for GPU data…", systemImage: "hourglass")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Label("Contacting \(Config.load().host)…", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func ringPercent(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        return "\(Int((pct * 100).rounded()))%"
    }

    /// The temperature block: "Temperature" label above a centered
    /// number colored by heat.
    private func tempRow(_ s: GPUSample) -> some View {
        VStack(spacing: 2) {
            Text("Temperature")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Group {
                if let t = s.tempC {
                    Text("\(t)°")
                        .foregroundStyle(Color.heat(t))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 20, weight: .bold))
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func vramText(_ s: GPUSample) -> String {
        guard let used = s.vramUsedMiB else { return "—" }
        if let total = s.vramTotalMiB {
            return String(format: "%.1f / %.1f GB", Double(used) / 1024, Double(total) / 1024)
        }
        return String(format: "%.1f GB", Double(used) / 1024)
    }

    private func powerDrawText(_ s: GPUSample) -> String {
        guard let draw = s.powerW else { return "—" }
        return String(format: "%.0f W", draw)
    }

    private func powerCaption(_ s: GPUSample) -> String {
        guard let limit = s.powerLimitW else { return "" }
        return "Limit \(Int(limit.rounded())) W"
    }

    private func metricRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(poller.stale ? "—" : value)
                .monospacedDigit().bold().foregroundStyle(valueColor)
        }
        .font(.system(size: 13))
        .frame(height: 22)
    }

    private var footer: some View {
        HStack {
            MenuItemButton("Edit Config") {
                if let url = URL(string: "file://" + Config.defaultConfigURL.path) {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
            MenuItemButton("Quit") { NSApp.terminate(nil) }
        }
    }
}

/// A 1pt separator hairline, inset from the edges like a native menu divider.
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

/// A borderless button mimicking an NSMenu item: 13pt text, 22pt row,
/// system accent highlight with white text on hover.
struct MenuItemButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(height: 22)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? Color.accentColor : .clear)
        )
        .onHover { hovering = $0 }
    }
}

/// A large labeled ring tile with a centered value and a caption underneath.
struct BigRingTile: View {
    let title: String
    let icon: String
    let fraction: Double
    let color: Color
    let centerText: String
    var centerTextColor: Color = .primary
    let caption: String
    let active: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ZStack {
                RingView(fraction: fraction, color: color, lineWidth: 5.5, active: active)
                Text(centerText)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(centerTextColor)
            }
            .frame(width: 56, height: 56)
            Text(caption)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
