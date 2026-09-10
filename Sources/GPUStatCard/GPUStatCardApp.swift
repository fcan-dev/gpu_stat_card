import SwiftUI
import AppKit
import GPUStatCardCore

@main
struct GPUStatCardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No windows; the status item + popover are created by the AppDelegate.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var poller: GPUPoller?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon / app menu
        let p = GPUPoller()
        p.start()                               // poll continuously
        poller = p
        controller = StatusItemController(poller: p)
    }
}
