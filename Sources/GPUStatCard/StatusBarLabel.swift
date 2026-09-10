import SwiftUI
import Observation
import GPUStatCardCore

/// Shared hover state driving the popover's show/hide.
@MainActor
@Observable
final class MenuBarInteraction {
    var insideStatus = false
    var insidePopover = false
}

/// The content shown in the menu bar itself: live temperature text plus small
/// Watt and VRAM rings. Rendered to an NSImage by `StatusItemController`.
struct StatusBarLabel: View {
    @Bindable var poller: GPUPoller

    var body: some View {
        HStack(spacing: 5) {
            if let t = poller.sample?.tempC {
                Text("\(t)°")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(poller.ok ? Color.heat(t) : Color.secondary)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            RingView(fraction: poller.sample?.powerPct ?? 0,
                     color: Color.power(poller.sample?.powerPct),
                     lineWidth: 2.5, active: poller.ok)
                .frame(width: 13, height: 13)
            RingView(fraction: poller.sample?.vramPct ?? 0, color: .blue,
                     lineWidth: 2.5, active: poller.ok)
                .frame(width: 13, height: 13)
        }
        .padding(.horizontal, 2)
    }
}
