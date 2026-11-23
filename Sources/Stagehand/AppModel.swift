import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published private(set) var current: Source?
    @Published private(set) var status: String?
    @Published private(set) var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @Published private(set) var displayReady = false

    @Published var spotlight = false
    @Published var highlight = false
    @Published private(set) var cameraOn = false
    @Published var breakMinutes = 5
    @Published private(set) var breakEnd: Date?

    /// Pinned sources; their order is the ⌃⌥⌘1–9 slot order.
    @Published var favorites: [Favorite] = Favorite.load() {
        didSet { Favorite.save(favorites) }
    }
    /// Follow mode: the stage shows whichever window you are working in.
    @Published var follow = UserDefaults.standard.bool(forKey: "follow") {
        didSet { UserDefaults.standard.set(follow, forKey: "follow") }
    }

    /// Live thumbnail of what the meeting sees, shown in the control panel.
    let preview = PreviewView()

    private var display: VirtualDisplay?
    private var stageWindow: StageWindow?
    private let capture = CaptureEngine()
    private let camera = Camera()
    private let hotkeys = Hotkeys()
    private var ownApp: SCRunningApplication?
    private var ticker: Timer?
    private var tick = 0
    private var sourceFrame: CGRect?
    private var lastPhysicalCursor: CGPoint?
    private var favoriteWindowIDs: [UUID: CGWindowID] = [:]
    private let previewCapture = CaptureEngine()
    private var stageDisplay: SCDisplay?
    private var previewWanted = false
    private var previewRunning = false
    private var followCandidate: CGWindowID?
    private var lastFollowRefresh = Date.distantPast

    /// Apps where the presenter looks at the call, not at what they share. Follow mode ignores them.
    private static let meetingApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeetingsapp", "com.apple.FaceTime", "com.hnc.Discord",
    ]

    func launch() {
        if !hasScreenAccess { CGRequestScreenCaptureAccess() }

        guard let display = VirtualDisplay() else {
            status = "Could not create the virtual display."
            return
        }
        self.display = display
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachStageWindow() }
        }
        attachStageWindow()

        capture.onFrame = { [weak self] surface, size in self?.stageWindow?.stage.show(frame: surface, contentSize: size) }
        previewCapture.onFrame = { [weak self] surface, _ in self?.preview.show(surface) }
        previewCapture.onStop = { [weak self] _ in self?.previewRunning = false }
        capture.onStop = { [weak self] _ in
            guard let self else { return }
            self.current = nil
            self.stageWindow?.stage.clear(message: "The shared window closed")
            Task { await self.refreshSources() }
        }

        registerHotkeys()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        Task { await refreshSources() }
    }

    func shutdown() {
        ticker?.invalidate()
        camera.stop()
        Task {
            await capture.stop()
            await previewCapture.stop()
        }
    }

    // MARK: Stage window

    private func attachStageWindow() {
        guard let display else { return }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) else { return } // the display shows up a moment after it is created
        if let window = stageWindow {
            window.setFrame(screen.frame, display: true)
        } else {
            let window = StageWindow(screen: screen)
            window.orderFrontRegardless()
            window.stage.clear(message: "Pick a window in Stagehand")
            stageWindow = window
            if let session = camera.session, cameraOn { window.stage.showCamera(session) }
        }
        displayReady = true
    }

    // MARK: Sources

    func refreshSources() async {
        hasScreenAccess = CGPreflightScreenCaptureAccess()
        do {
            let result = try await Source.available(virtualDisplayID: display?.displayID)
            sources = result.sources
            ownApp = result.ownApp
            stageDisplay = result.stageDisplay
            updatePreview()
            if status?.hasPrefix("Screen recording") == true { status = nil }
        } catch {
            status = "Screen recording access is needed. Allow Stagehand in System Settings, then reopen it."
        }
    }

    func select(_ source: Source, focus: Bool = true) {
        if breakEnd != nil { stopBreak() }
        current = source
        sourceFrame = source.currentFrame
        if focus, case .window(let window) = source { WindowFocus.focus(window) }
        let filter = source.filter(excluding: ownApp)
        Task {
            do {
                try await capture.start(filter: filter, outputSize: VirtualDisplay.size, fps: 30) // meeting apps send ≤30 fps
                status = nil
            } catch {
                status = "Could not capture \(source.title): \(error.localizedDescription)"
                if current == source { current = nil }
            }
        }
    }

    /// ⌃⌥⌘1–9: the favourite in that slot. Without favourites, the window list order as before.
    func select(slot index: Int) {
        if favorites.isEmpty {
            if sources.indices.contains(index) { select(sources[index]) }
            return
        }
        guard favorites.indices.contains(index) else { return }
        let favorite = favorites[index]
        // Refresh first: window titles change (browser tabs) and windows open and close, and a stale list
        // can match the wrong window of an app that has several. Listing takes a few milliseconds.
        Task {
            await refreshSources()
            if let source = resolve(favorite) { select(source) } else { status = "\(favorite.label) isn't open." ; NSSound.beep() }
        }
    }

    /// ⌃⌥⌘← / →: cycle through open favourites, or all sources when there are none.
    func step(_ delta: Int) {
        let ring = favorites.isEmpty ? sources : favorites.compactMap { resolve($0) }
        guard !ring.isEmpty else { return }
        let index = current.flatMap { ring.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        select(ring[(index + delta + ring.count) % ring.count])
    }

    // MARK: Favourites

    func resolve(_ favorite: Favorite) -> Source? {
        let source = favorite.resolve(in: sources, lastWindowID: favoriteWindowIDs[favorite.id])
        if let id = source?.windowID { favoriteWindowIDs[favorite.id] = id }
        return source
    }

    func favorite(for source: Source) -> Favorite? {
        favorites.first { fav in
            if let id = favoriteWindowIDs[fav.id], let sid = source.windowID { return id == sid }
            return fav.resolve(in: sources, lastWindowID: nil) == source
        }
    }

    func toggleFavorite(_ source: Source) {
        if let existing = favorite(for: source) {
            favorites.removeAll { $0.id == existing.id }
            favoriteWindowIDs[existing.id] = nil
        } else if favorites.count < Favorite.maxCount {
            let fav = Favorite(source)
            favoriteWindowIDs[fav.id] = source.windowID
            favorites.append(fav)
        } else {
            status = "All nine shortcut slots are taken. Remove a favourite first."
        }
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        favoriteWindowIDs[favorite.id] = nil
    }

    func moveFavorites(from offsets: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
    }

    // MARK: Preview

    /// The control panel calls this when it becomes visible or hidden, so the preview only costs CPU when seen.
    func setPreviewVisible(_ visible: Bool) {
        previewWanted = visible
        updatePreview()
    }

    private func updatePreview() {
        if previewWanted, !previewRunning, let stageDisplay {
            previewRunning = true
            let filter = SCContentFilter(display: stageDisplay, excludingWindows: [])
            Task {
                do {
                    try await previewCapture.start(filter: filter, outputSize: CGSize(width: 960, height: 540), fps: 15)
                } catch {
                    previewRunning = false
                }
            }
        } else if !previewWanted, previewRunning {
            previewRunning = false
            Task { await previewCapture.stop() }
        }
    }

    // MARK: Follow mode

    /// Frontmost normal window of a regular app, from the window server's front-to-back order.
    private func frontmostWindow() -> (id: CGWindowID, pid: pid_t)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 120, bounds.height >= 80,
                  Source.isRegularApp(pid)
            else { continue }
            return (id, pid)
        }
        return nil
    }

    private func followTick() {
        guard follow, breakEnd == nil, let front = frontmostWindow() else { return }
        if let bundle = NSRunningApplication(processIdentifier: front.pid)?.bundleIdentifier,
           Self.meetingApps.contains(bundle) { return }
        guard current?.windowID != front.id else { followCandidate = nil; return }
        // Wait for the same window on two checks in a row, so ⌘-Tab passing through apps doesn't flicker.
        guard followCandidate == front.id else { followCandidate = front.id; return }
        followCandidate = nil
        if let source = sources.first(where: { $0.windowID == front.id }) {
            select(source, focus: false)
        } else if Date().timeIntervalSince(lastFollowRefresh) > 1 {
            lastFollowRefresh = Date()
            Task { await refreshSources() } // a new window; picked up on the next check
        }
    }

    // MARK: Overlays

    func setCamera(_ on: Bool) {
        if on {
            camera.start { [weak self] session in
                guard let self else { return }
                self.cameraOn = session != nil
                if session == nil { self.status = "No camera access. Allow Stagehand under Privacy & Security › Camera." }
                self.stageWindow?.stage.showCamera(session)
            }
        } else {
            camera.stop()
            cameraOn = false
            stageWindow?.stage.showCamera(nil)
        }
    }

    func startBreak() {
        breakEnd = Date().addingTimeInterval(TimeInterval(breakMinutes * 60))
        updateBreak()
    }

    func stopBreak() {
        breakEnd = nil
        stageWindow?.stage.showBreak(title: nil, clock: nil)
    }

    private var breakFinished = false

    private func updateBreak() {
        guard let breakEnd else { return }
        let left = max(0, Int(breakEnd.timeIntervalSinceNow.rounded(.up)))
        if left == 0, !breakFinished {
            breakFinished = true
            NSSound(named: "Glass")?.play()
        } else if left > 0 {
            breakFinished = false
        }
        let title = left == 0 ? "Starting again" : "Break · back in"
        stageWindow?.stage.showBreak(title: title, clock: String(format: "%d:%02d", left / 60, left % 60))
    }

    // MARK: Tick

    private func onTick() {
        tick += 1
        guard let display, let stage = stageWindow?.stage else { return }
        guard let cursor = CGEvent(source: nil)?.location else { return }

        // Keep the pointer off the virtual display: nobody can see it there.
        if display.bounds.contains(cursor) {
            if let back = lastPhysicalCursor { CGWarpMouseCursorPosition(back) }
            return
        }
        lastPhysicalCursor = cursor

        if tick % 3 == 0 { sourceFrame = current?.currentFrame }
        if tick % 8 == 0 {
            updateBreak()
            followTick()
        }

        var stagePoint: CGPoint?
        let fit = stage.contentFit
        if let frame = sourceFrame, frame.width > 0, frame.height > 0, fit.width > 0, frame.contains(cursor) {
            stagePoint = CGPoint(x: fit.minX + (cursor.x - frame.minX) / frame.width * fit.width,
                                 y: fit.minY + (cursor.y - frame.minY) / frame.height * fit.height)
        }
        stage.updateCursor(stagePoint, spotlight: spotlight && breakEnd == nil, highlight: highlight && breakEnd == nil)
    }

    // MARK: Hotkeys

    static let shortcutHelp: [(String, String)] = [
        ("\(Hotkeys.modifierLabel)1 … 9", "Show favourite 1 to 9"),
        ("\(Hotkeys.modifierLabel)← / →", "Previous / next favourite"),
        ("\(Hotkeys.modifierLabel)F", "Follow mode on / off"),
        ("\(Hotkeys.modifierLabel)C", "Webcam on / off"),
        ("\(Hotkeys.modifierLabel)S", "Spotlight on / off"),
        ("\(Hotkeys.modifierLabel)H", "Highlight cursor on / off"),
        ("\(Hotkeys.modifierLabel)B", "Start / stop break countdown"),
        ("\(Hotkeys.modifierLabel)R", "Refresh the window list"),
    ]

    private func registerHotkeys() {
        for (index, key) in Hotkeys.digitKeys.enumerated() {
            hotkeys.register(key) { [weak self] in self?.select(slot: index) }
        }
        hotkeys.register(kVK_LeftArrow) { [weak self] in self?.step(-1) }
        hotkeys.register(kVK_RightArrow) { [weak self] in self?.step(1) }
        hotkeys.register(kVK_ANSI_C) { [weak self] in guard let self else { return }; self.setCamera(!self.cameraOn) }
        hotkeys.register(kVK_ANSI_S) { [weak self] in self?.spotlight.toggle() }
        hotkeys.register(kVK_ANSI_H) { [weak self] in self?.highlight.toggle() }
        hotkeys.register(kVK_ANSI_B) { [weak self] in
            guard let self else { return }
            self.breakEnd == nil ? self.startBreak() : self.stopBreak()
        }
        hotkeys.register(kVK_ANSI_F) { [weak self] in self?.follow.toggle() }
        hotkeys.register(kVK_ANSI_R) { [weak self] in Task { await self?.refreshSources() } }
    }
}
