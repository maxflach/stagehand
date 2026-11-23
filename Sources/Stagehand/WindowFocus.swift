import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Brings a captured window to the front so the presenter works in the window everyone sees.
enum WindowFocus {
    private static var askedForAccess = false

    static func focus(_ window: SCWindow) {
        guard let pid = window.owningApplication?.processID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }

        // Raising one specific window needs Accessibility. Ask once per launch; without it just activate the app.
        if AXIsProcessTrusted() {
            raise(window, pid: pid)
        } else if !askedForAccess {
            askedForAccess = true
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        app.activate(options: [])
    }

    /// Finds the app's AX window with the same frame (and title, when there are ties) and raises it.
    private static func raise(_ target: SCWindow, pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        let best = windows.min { distance($0, to: target) < distance($1, to: target) }
        guard let best, distance(best, to: target) < 40 else { return }
        AXUIElementSetAttributeValue(best, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(best, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(best, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, best)
    }

    /// How far an AX window is from the captured one, in points. Title mismatch adds a penalty.
    private static func distance(_ element: AXUIElement, to target: SCWindow) -> CGFloat {
        guard let frame = frame(of: element) else { return .greatestFiniteMagnitude }
        // Use where the window is now; the SCWindow snapshot may be from before it moved.
        let t = Source.window(target).currentFrame ?? target.frame
        var d = abs(frame.minX - t.minX) + abs(frame.minY - t.minY) + abs(frame.width - t.width) + abs(frame.height - t.height)
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success,
           let title = title as? String, let targetTitle = target.title, title != targetTitle {
            d += 20
        }
        return d
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
