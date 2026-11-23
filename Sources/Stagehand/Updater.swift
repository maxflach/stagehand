import Sparkle

/// Automatic updates from the GitHub releases appcast (SUFeedURL in Info.plist).
@MainActor
final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
