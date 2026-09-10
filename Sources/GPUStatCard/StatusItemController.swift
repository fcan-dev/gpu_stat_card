import SwiftUI
import AppKit
import GPUStatCardCore

/// Transparent subview inside the status button that observes the cursor and
/// forwards enter/exit to the controller. `hitTest` returns nil so clicks pass
/// through to the button (which drives the pin action).
@MainActor
final class StatusHoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// Owns the `NSStatusItem` (menu bar item) and the `NSPopover` (detail card).
///
/// The menu bar content is a SwiftUI view rendered to an `NSImage` (via
/// `ImageRenderer`) and set as the status button's image; it is re-rendered
/// whenever the poll data changes. Hover is tracked by `StatusHoverView` and
/// drives the popover's visibility: moving over the status item (or the card)
/// reveals the card, moving away hides it.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let interaction = MenuBarInteraction()
    private let poller: GPUPoller
    private var hoverView: StatusHoverView?
    private var timer: Timer?
    private var lastSignature = ""

    init(poller: GPUPoller) {
        self.poller = poller
        super.init()
        setupStatusItem()
        setupPopover()
        renderImage()

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so it always fires on main.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.target = nil
        button.action = nil
        button.setAccessibilityLabel("GPU status")

        let hover = StatusHoverView()
        hover.onEnter = { [weak self] in self?.interaction.insideStatus = true }
        hover.onExit = { [weak self] in self?.interaction.insideStatus = false }
        hover.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hover)
        NSLayoutConstraint.activate([
            hover.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hover.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hover.topAnchor.constraint(equalTo: button.topAnchor),
            hover.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        hoverView = hover
    }

    private func setupPopover() {
        popover.behavior = .semitransient
        popover.animates = false
        let host = NSHostingController(
            rootView: CardView(poller: poller, interaction: interaction))
        popover.contentViewController = host
    }

    // MARK: - Rendering

    private var dataSignature: String {
        guard let s = poller.sample else { return "nil" }
        let v = s.vramPct.map { String(format: "%.3f", $0) } ?? "-"
        let p = s.powerPct.map { String(format: "%.3f", $0) } ?? "-"
        return "\(s.tempC.map(String.init) ?? "-")|\(poller.ok)|\(v)|\(p)"
    }

    private func renderImage() {
        guard let button = statusItem.button else { return }
        let renderer = ImageRenderer(content: StatusBarLabel(poller: poller))
        renderer.scale = 2
        if let image = renderer.nsImage {
            button.image = image
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Loop

    private func tick() {
        if dataSignature != lastSignature {
            lastSignature = dataSignature
            renderImage()
        }
        update()
    }

    private func update() {
        guard let button = statusItem.button else { return }

        let shouldShow = interaction.insideStatus || interaction.insidePopover
        if shouldShow {
            if !popover.isShown {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Make the popover's window key immediately so the vibrant
                // background renders in its active (key-window) state. Without
                // this the material only switches to that state when the user
                // clicks inside the card, causing a visible light→gray shift.
                popover.contentViewController?.view.window?.makeKey()
            }
        } else if popover.isShown {
            popover.performClose(nil)
        }
    }
}
