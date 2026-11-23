import CoreGraphics
import Foundation

/// A pinned source with a fixed shortcut slot (⌃⌥⌘1 to 9).
/// Window IDs change between launches, so a favourite remembers the app and the window title, and
/// matches whatever window of that app fits best right now.
struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String?   // nil for screens
    var appName: String
    var title: String       // window title, or the screen name
    var isScreen: Bool

    init(_ source: Source) {
        bundleID = source.bundleID
        appName = source.appName
        title = source.rawTitle
        if case .display = source { isScreen = true } else { isScreen = false }
    }

    var label: String {
        if isScreen { return "Screen: \(title)" }
        return appName
    }

    var detail: String { isScreen ? "" : title }

    static let maxCount = 9
    private static let key = "favorites"

    static func load() -> [Favorite] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Favorite].self, from: data) else { return [] }
        return Array(list.prefix(maxCount))
    }

    static func save(_ list: [Favorite]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Best matching source: same screen name, or a window of the same app. Among several windows, prefer
    /// the one this favourite used earlier in this session, then an exact title, then the first.
    func resolve(in sources: [Source], lastWindowID: CGWindowID?) -> Source? {
        if isScreen {
            return sources.first { if case .display = $0 { return $0.rawTitle == title }; return false }
        }
        let windows = sources.filter { $0.bundleID != nil && $0.bundleID == bundleID }
        if windows.count <= 1 { return windows.first }
        if let lastWindowID, let match = windows.first(where: { $0.windowID == lastWindowID }) { return match }
        if let match = windows.first(where: { $0.rawTitle == title }) { return match }
        return windows.first
    }
}
