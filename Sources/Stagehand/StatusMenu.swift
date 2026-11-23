import AppKit

/// Menu bar icon with the source list and overlay toggles.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let autosaveName = "StagehandStatus"
    private let model: AppModel
    private let openPanel: () -> Void
    private let item: NSStatusItem

    init(model: AppModel, openPanel: @escaping () -> Void) {
        self.model = model
        self.openPanel = openPanel
        // New items appear next to the notch, where they can be hidden. On first launch, ask macOS to place
        // ours near the clock instead. The value is the distance from the right edge; the user can still ⌘-drag it.
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(220, forKey: positionKey)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.autosaveName = Self.autosaveName
        item.button?.image = NSImage(systemSymbolName: "theatermasks.fill", accessibilityDescription: "Stagehand")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// Opens the same menu at the pointer, for bars that replace the native menu bar (SketchyBar).
    func popUpAtPointer() {
        guard let menu = item.menu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Show on stage", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if model.sources.isEmpty {
            let empty = NSMenuItem(title: model.hasScreenAccess ? "No windows found" : "Needs Screen Recording access",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, source) in model.sources.enumerated() {
            let entry = add(menu, source.title, #selector(pickSource(_:)), on: model.current == source)
            entry.tag = index
            if let icon = source.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            if index < 9 {
                entry.keyEquivalent = "\(index + 1)"
                entry.keyEquivalentModifierMask = [.control, .option, .command]
            }
        }

        menu.addItem(.separator())
        add(menu, "Webcam", #selector(toggleCamera), on: model.cameraOn)
        add(menu, "Spotlight", #selector(toggleSpotlight), on: model.spotlight)
        add(menu, "Highlight cursor", #selector(toggleHighlight), on: model.highlight)
        add(menu, model.breakEnd == nil ? "Start \(model.breakMinutes) min break" : "End break", #selector(toggleBreak))

        menu.addItem(.separator())
        add(menu, "Control Panel…", #selector(showPanel))
        add(menu, "Quit Stagehand", #selector(quit))

        // Refresh in the background so the next open has new windows.
        Task { await model.refreshSources() }
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.state = on ? .on : .off
        return entry
    }

    @objc private func pickSource(_ sender: NSMenuItem) { model.select(index: sender.tag) }
    @objc private func toggleCamera() { model.setCamera(!model.cameraOn) }
    @objc private func toggleSpotlight() { model.spotlight.toggle() }
    @objc private func toggleHighlight() { model.highlight.toggle() }
    @objc private func toggleBreak() { model.breakEnd == nil ? model.startBreak() : model.stopBreak() }
    @objc private func showPanel() { openPanel() }
    @objc private func quit() { NSApp.terminate(nil) }
}
