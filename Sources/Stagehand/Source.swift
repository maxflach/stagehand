import AppKit
import ScreenCaptureKit

/// Something Stagehand can put on stage: one window or one physical screen.
enum Source: Identifiable, Equatable {
    case window(SCWindow)
    case display(SCDisplay, name: String)

    var id: String {
        switch self {
        case .window(let w): return "w\(w.windowID)"
        case .display(let d, _): return "d\(d.displayID)"
        }
    }

    var title: String {
        switch self {
        case .window(let w):
            let app = w.owningApplication?.applicationName ?? "Window"
            if let t = w.title, !t.isEmpty { return "\(app) · \(t)" }
            return app
        case .display(_, let name):
            return "Screen: \(name)"
        }
    }

    var bundleID: String? {
        if case .window(let w) = self { return w.owningApplication?.bundleIdentifier }
        return nil
    }

    var appName: String {
        switch self {
        case .window(let w): return w.owningApplication?.applicationName ?? "Window"
        case .display(_, let name): return name
        }
    }

    /// Window title, or the display name for screens.
    var rawTitle: String {
        switch self {
        case .window(let w): return w.title ?? ""
        case .display(_, let name): return name
        }
    }

    var windowID: CGWindowID? {
        if case .window(let w) = self { return w.windowID }
        return nil
    }

    var icon: NSImage? {
        switch self {
        case .window(let w):
            guard let pid = w.owningApplication?.processID else { return nil }
            return NSRunningApplication(processIdentifier: pid)?.icon
        case .display:
            return NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        }
    }

    /// Where the source is right now, in global CoreGraphics coordinates (top-left origin).
    var currentFrame: CGRect? {
        switch self {
        case .display(let d, _):
            return CGDisplayBounds(d.displayID)
        case .window(let w):
            guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, w.windowID) as? [[String: Any]],
                  let dict = info.first?[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: dict as CFDictionary)
        }
    }

    func filter(excluding ownApp: SCRunningApplication?) -> SCContentFilter {
        switch self {
        case .window(let w):
            return SCContentFilter(desktopIndependentWindow: w)
        case .display(let d, _):
            return SCContentFilter(display: d, excludingApplications: ownApp.map { [$0] } ?? [], exceptingWindows: [])
        }
    }

    static func == (a: Source, b: Source) -> Bool { a.id == b.id }

    /// Lists shareable windows and screens, skipping Stagehand itself and the virtual display.
    struct Snapshot {
        var sources: [Source]
        var ownApp: SCRunningApplication?
        /// The virtual display itself, for the control panel preview.
        var stageDisplay: SCDisplay?
    }

    static func available(virtualDisplayID: CGDirectDisplayID?) async throws -> Snapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.first { $0.processID == ownPID }

        let screenNames = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (id, screen.localizedName)
        }, uniquingKeysWith: { a, _ in a })

        let displays = content.displays
            .filter { $0.displayID != virtualDisplayID }
            .map { Source.display($0, name: screenNames[$0.displayID] ?? "Display \($0.displayID)") }

        let windows = content.windows
            .filter { w in
                w.windowLayer == 0 && w.isOnScreen
                    && w.frame.width >= 120 && w.frame.height >= 80
                    && w.owningApplication != nil
                    && w.owningApplication?.processID != ownPID
                    && isRegularApp(w.owningApplication?.processID)
            }
            .sorted { a, b in
                let an = a.owningApplication?.applicationName ?? "", bn = b.owningApplication?.applicationName ?? ""
                return an == bn ? (a.title ?? "") < (b.title ?? "") : an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
            }
            .map(Source.window)

        let stageDisplay = content.displays.first { $0.displayID == virtualDisplayID }
        return Snapshot(sources: windows + displays, ownApp: ownApp, stageDisplay: stageDisplay)
    }

    /// Only apps with a Dock icon. Skips background helpers such as JankyBorders, whose
    /// outline windows around every app window would otherwise show up as nameless entries.
    static func isRegularApp(_ pid: pid_t?) -> Bool {
        guard let pid else { return false }
        return NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }
}
