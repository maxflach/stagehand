import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = Updater()
    private var panel: NSWindow?
    private var statusMenu: StatusMenu?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    /// `stagehand://menu` opens the Stagehand menu at the pointer; any other stagehand:// URL shows the control panel.
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        let url = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue.flatMap(URL.init(string:))
        launchedFromURL = true
        // Let launch finish before showing anything.
        DispatchQueue.main.async {
            if url?.host == "menu" { self.statusMenu?.popUpAtPointer() } else { self.showPanel() }
        }
    }

    private var launchedFromURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--write-icon"), let dir = CommandLine.arguments.last {
            exit(AppIcon.writeIconset(to: URL(fileURLWithPath: dir)) ? 0 : 1)
        }
        NSApp.mainMenu = buildMainMenu()
        model.launch()
        statusMenu = StatusMenu(model: model, updater: updater) { [weak self] in self?.showPanel() }
        if !launchedFromURL { showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    @objc func showPanel() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Stagehand"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The live preview only runs while the panel can actually be seen.
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { self?.model.setPreviewVisible(window.occlusionState.contains(.visible)) }
            }
            window.contentView = NSHostingView(rootView: ControlPanel(model: model))
            window.setFrameAutosaveName("ControlPanel")
            if !window.setFrameUsingName("ControlPanel") { window.center() }
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Stagehand", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let check = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        check.target = updater
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Stagehand", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Stagehand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Stagehand", action: nil, keyEquivalent: "").submenu = appMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Control Panel", action: #selector(showPanel), keyEquivalent: "0").target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
