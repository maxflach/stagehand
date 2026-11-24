import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// A full-stage card shown instead of the shared content.
enum TitleCard: Equatable {
    case beRightBack
    case startingSoon(Date)
    case breakTime(Date)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sources: [Source] = []
    /// What's on stage, or on the left when side by side.
    @Published private(set) var current: Source?
    /// The right-hand source when side by side.
    @Published private(set) var secondary: Source?
    @Published private(set) var split = false
    @Published private(set) var status: String?
    @Published private(set) var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @Published private(set) var displayReady = false
    /// Off means nothing is captured and the Stagehand display is gone, so macOS has no recording to warn about
    /// and the battery isn't spent on capturing. Stagehand always starts off; picking a window turns it on.
    @Published private(set) var isOn = false
    @Published var offWhenLocked = UserDefaults.standard.object(forKey: "offWhenLocked") as? Bool ?? true {
        didSet { UserDefaults.standard.set(offWhenLocked, forKey: "offWhenLocked") }
    }

    @Published var spotlight = false { didSet { updateTicker() } }
    @Published var highlight = false { didSet { updateTicker() } }
    @Published var zoomOn = false { didSet { updateTicker() } }
    @Published var zoomLevel: Double = UserDefaults.standard.object(forKey: "zoomLevel") as? Double ?? 2 {
        didSet { UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel") }
    }

    @Published private(set) var cameraOn = false
    @Published var cameraStyle = CameraStyle.load() {
        didSet {
            cameraStyle.save()
            stageWindow?.stage.setCameraStyle(cameraStyle)
        }
    }

    @Published private(set) var card: TitleCard?
    @Published var breakMinutes = 5
    @Published var startTime = AppModel.nextHalfHour()

    @Published var lowerThirdOn = false { didSet { updateLowerThird() } }
    @Published var lowerName = UserDefaults.standard.string(forKey: "lowerName") ?? NSFullUserName() {
        didSet { UserDefaults.standard.set(lowerName, forKey: "lowerName"); updateLowerThird() }
    }
    @Published var lowerRole = UserDefaults.standard.string(forKey: "lowerRole") ?? "" {
        didSet { UserDefaults.standard.set(lowerRole, forKey: "lowerRole"); updateLowerThird() }
    }

    /// Pinned sources; their order is the favourite shortcut slot order.
    @Published var favorites: [Favorite] = Favorite.load() {
        didSet { Favorite.save(favorites) }
    }
    /// Follow mode: the stage shows whichever window you are working in.
    @Published var follow = UserDefaults.standard.bool(forKey: "follow") {
        didSet { UserDefaults.standard.set(follow, forKey: "follow") }
    }

    /// Live thumbnail of what the meeting sees, shown in the control panel.
    let preview = PreviewView()

    var breakEnd: Date? {
        if case .breakTime(let end) = card { return end }
        return nil
    }

    private var display: VirtualDisplay?
    private var stageWindow: StageWindow?
    private let captures = [CaptureEngine(), CaptureEngine()]
    private let camera = Camera()
    private let hotkeys = Hotkeys()
    private var ownApp: SCRunningApplication?
    private var ticker: Timer?
    private var tickerFast = false
    private var lastFrameCheck = Date.distantPast
    private var lastSlowWork = Date.distantPast
    private var sourceFrames: [CGRect?] = [nil, nil]
    /// The source shown before `current`, used when side by side is switched on.
    private var previous: Source?
    private var lastPhysicalCursor: CGPoint?
    private var favoriteWindowIDs: [UUID: CGWindowID] = [:]
    private let previewCapture = CaptureEngine()
    private var stageDisplay: SCDisplay?
    private var previewWanted = false
    private var previewRunning = false
    private var followCandidate: CGWindowID?
    private var lastFollowRefresh = Date.distantPast
    private var cardFinished = false
    private var zoomCenter: CGPoint?
    private var zoomScale: CGFloat = 1

    /// Apps where the presenter looks at the call, not at what they share. Follow mode ignores them.
    private static let meetingApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeetingsapp", "com.apple.FaceTime", "com.hnc.Discord",
    ]

    func launch() {
        if !hasScreenAccess { CGRequestScreenCaptureAccess() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachStageWindow() }
        }
        // Stop capturing while locked: macOS warns about apps recording the screen when you unlock.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.offWhenLocked, self.isOn else { return }
                self.setOn(false)
            }
        }

        previewCapture.onFrame = { [weak self] surface, _ in self?.preview.show(surface) }
        previewCapture.onStop = { [weak self] _ in self?.previewRunning = false }
        captures[0].onStop = { [weak self] _ in self?.paneStopped(0) }
        captures[1].onStop = { [weak self] _ in self?.paneStopped(1) }

        registerHotkeys()
        UserDefaults.standard.set(false, forKey: "isOn") // starts off; keeps the SketchyBar item in step
        Task { await refreshSources() }
    }

    // MARK: On / off

    func toggleOn() { setOn(!isOn) }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        UserDefaults.standard.set(on, forKey: "isOn") // read by the SketchyBar item
        on ? powerOn() : powerOff()
    }

    private func powerOn() {
        guard display == nil else { return }
        guard let display = VirtualDisplay() else {
            status = "Could not create the virtual display."
            return
        }
        self.display = display
        attachStageWindow()
        startTicker(fast: needsFastTick)
        // Put back what was on stage before turning off.
        if current != nil {
            startCapture(pane: 0)
            if split { startCapture(pane: 1) }
        }
        Task { await refreshSources() } // finds the new display for the preview
    }

    private func powerOff() {
        ticker?.invalidate()
        ticker = nil
        camera.stop()
        cameraOn = false
        previewRunning = false
        let engines = captures + [previewCapture]
        Task { for engine in engines { await engine.stop() } }
        stageWindow?.orderOut(nil)
        stageWindow?.close()
        stageWindow = nil
        stageDisplay = nil
        display = nil // removes the display; meeting apps see it disappear
        displayReady = false
        zoomCenter = nil
        zoomScale = 1
        preview.clear()
    }

    func shutdown() {
        ticker?.invalidate()
        camera.stop()
        Task {
            for capture in captures { await capture.stop() }
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
            window.stage.setCameraStyle(cameraStyle)
            stageWindow = window
            if split { window.stage.setSplit(true) }
            if let session = camera.session, cameraOn { window.stage.showCamera(session) }
            updateLowerThird()
            updateCard()
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

    /// Puts a source on stage. Side by side, the stage shows your last two picks: the new one on the left
    /// and the one it replaces on the right.
    func select(_ source: Source, focus: Bool = true) {
        if !isOn {
            setOn(true)
            if source == current { return } // powerOn already put it back
        }
        if card != nil { hideCard() }
        if focus, case .window(let window) = source { WindowFocus.focus(window) }
        guard source != current else { return }
        if current != nil { previous = current }
        if split {
            if source == secondary {
                secondary = current // swap sides
            } else {
                secondary = current ?? secondary
            }
            current = source
            startCapture(pane: 0)
            startCapture(pane: 1)
        } else {
            current = source
            startCapture(pane: 0)
        }
    }

    /// Side by side with `source` on the right.
    func showOnRight(_ source: Source) {
        if !isOn { setOn(true) }
        if source == current {
            current = secondary ?? previous
        }
        secondary = source
        if !split { setSplit(true, keepSecondary: true) } else { startCapture(pane: 0); startCapture(pane: 1) }
    }

    func toggleSplit() { setSplit(!split) }

    private func setSplit(_ on: Bool, keepSecondary: Bool = false) {
        if on {
            if !keepSecondary {
                // The window shown before this one, or else any other source.
                let candidate = previous.flatMap { p in sources.contains(p) && p != current ? p : nil }
                secondary = candidate ?? sources.first { $0 != current }
            }
            guard current != nil, secondary != nil else {
                status = "Put two windows on stage one after the other, then turn on side by side."
                return
            }
            split = true
            stageWindow?.stage.setSplit(true)
            startCapture(pane: 0)
            startCapture(pane: 1)
        } else {
            split = false
            secondary = nil
            sourceFrames[1] = nil
            Task { await captures[1].stop() }
            stageWindow?.stage.setSplit(false)
            startCapture(pane: 0)
        }
    }

    private func startCapture(pane: Int) {
        guard let source = pane == 0 ? current : secondary else { return }
        sourceFrames[pane] = source.currentFrame
        let size = captureSize(pane: pane, frame: sourceFrames[pane])
        let engine = captures[pane]
        engine.onFrame = { [weak self] surface, _ in
            self?.stageWindow?.stage.show(frame: surface, pane: pane)
        }
        let filter = source.filter(excluding: ownApp)
        Task {
            do {
                // Meeting apps send at most 30 fps, so capturing faster only costs CPU.
                try await engine.start(filter: filter, outputSize: size, fps: 30)
                status = nil
            } catch {
                status = "Could not capture \(source.title): \(error.localizedDescription)"
            }
        }
    }

    /// Capture size: the pane, shrunk to the source's aspect ratio so the frame has no padding.
    private func captureSize(pane: Int, frame: CGRect?) -> CGSize {
        let box = stageWindow?.stage.paneRects(split: split)[pane].size ?? VirtualDisplay.size
        guard let frame, frame.width > 0, frame.height > 0 else { return box }
        return CaptureEngine.fittedSize(aspect: frame.size, in: box)
    }

    /// Follows window resizes so the capture keeps matching the window's shape.
    private func resizeCapturesIfNeeded() {
        for pane in 0..<(split ? 2 : 1) {
            let wanted = captureSize(pane: pane, frame: sourceFrames[pane])
            let have = captures[pane].outputSize
            guard have != .zero, abs(wanted.width - have.width) > 2 || abs(wanted.height - have.height) > 2 else { continue }
            let engine = captures[pane]
            Task { await engine.resize(to: wanted) }
        }
    }

    /// A captured window closed.
    private func paneStopped(_ pane: Int) {
        if pane == 0, split, let right = secondary {
            current = right
            setSplit(false)
        } else if pane == 1 {
            setSplit(false)
        } else {
            current = nil
            sourceFrames[0] = nil
            stageWindow?.stage.clear(message: "The shared window closed")
        }
        Task { await refreshSources() }
    }

    /// Favourite shortcut 1–9: the favourite in that slot. Without favourites, the window list order as before.
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
            if let source = resolve(favorite) { select(source) } else { status = "\(favorite.label) isn't open."; NSSound.beep() }
        }
    }

    /// Previous / next favourite: cycle through open favourites, or all sources when there are none.
    func step(_ delta: Int) {
        let ring = favorites.isEmpty ? sources : favorites.compactMap { resolve($0) }
        guard !ring.isEmpty else { return }
        let index = current.flatMap { ring.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        select(ring[(index + delta + ring.count) % ring.count])
    }

    func isOnStage(_ source: Source) -> Bool { source == current || (split && source == secondary) }

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
        guard follow, card == nil, let front = frontmostWindow() else { return }
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

    // MARK: Webcam

    func setCamera(_ on: Bool) {
        if on, !isOn { setOn(true) }
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

    /// "Just me": the webcam fills the stage.
    func toggleJustMe() {
        if !cameraOn { setCamera(true) }
        cameraStyle.fullScreen.toggle()
    }

    /// macOS's own camera effects (Portrait background blur, Studio Light, backgrounds). They run on the
    /// Neural Engine and apply to Stagehand's camera like to any other app's.
    func showVideoEffects() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    // MARK: Title cards

    func startBreak() { show(card: .breakTime(Date().addingTimeInterval(TimeInterval(breakMinutes * 60)))) }
    func stopBreak() { hideCard() }
    func showBeRightBack() { show(card: .beRightBack) }
    func showStartingSoon() { show(card: .startingSoon(startTime)) }

    func show(card: TitleCard) {
        self.card = card
        cardFinished = false
        updateCard()
    }

    func hideCard() {
        card = nil
        stageWindow?.stage.showCard(title: nil, clock: nil, subtitle: nil)
    }

    private func updateCard() {
        guard let card, let stage = stageWindow?.stage else { return }
        switch card {
        case .beRightBack:
            stage.showCard(title: "Be right back", clock: nil, subtitle: lowerName.isEmpty ? nil : lowerName)
        case .breakTime(let end), .startingSoon(let end):
            let left = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
            if left == 0, !cardFinished {
                cardFinished = true
                NSSound(named: "Glass")?.play()
            }
            let clock = left >= 3600
                ? String(format: "%d:%02d:%02d", left / 3600, (left / 60) % 60, left % 60)
                : String(format: "%d:%02d", left / 60, left % 60)
            if case .breakTime = card {
                stage.showCard(title: left == 0 ? "Starting again" : "Break · back in", clock: clock, subtitle: nil)
            } else {
                let time = end.formatted(date: .omitted, time: .shortened)
                stage.showCard(title: left == 0 ? "Starting now" : "Starting soon", clock: clock,
                               subtitle: left == 0 ? nil : "We begin at \(time)")
            }
        }
    }

    static func nextHalfHour() -> Date {
        let now = Date()
        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        let add = minute < 30 ? 30 - minute : 60 - minute
        return cal.date(byAdding: .minute, value: add, to: now).map { cal.date(bySetting: .second, value: 0, of: $0) ?? $0 } ?? now
    }

    private func updateLowerThird() {
        stageWindow?.stage.showLowerThird(name: lowerThirdOn ? lowerName : nil, role: lowerThirdOn ? lowerRole : nil)
    }

    // MARK: Tick

    /// Pointer effects need 30 updates a second to look smooth. Without them, 8 a second is enough to keep
    /// the pointer off the virtual display and to drive follow mode and countdowns, at a fraction of the wakeups.
    private var needsFastTick: Bool { spotlight || highlight || zoomOn || zoomScale != 1 }

    private func updateTicker() {
        if ticker != nil, needsFastTick != tickerFast { startTicker(fast: needsFastTick) }
    }

    private func startTicker(fast: Bool) {
        ticker?.invalidate()
        tickerFast = fast
        let timer = Timer(timeInterval: fast ? 1.0 / 30 : 1.0 / 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        timer.tolerance = fast ? 0.005 : 0.03 // lets macOS batch our wakeups with others
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func onTick() {
        guard let display, let stage = stageWindow?.stage else { return }
        guard let cursor = CGEvent(source: nil)?.location else { return }

        // Keep the pointer off the virtual display: nobody can see it there.
        if display.bounds.contains(cursor) {
            if let back = lastPhysicalCursor { CGWarpMouseCursorPosition(back) }
            return
        }
        lastPhysicalCursor = cursor

        let now = Date()
        if now.timeIntervalSince(lastFrameCheck) >= 0.1 {
            lastFrameCheck = now
            sourceFrames[0] = current?.currentFrame
            sourceFrames[1] = split ? secondary?.currentFrame : nil
            resizeCapturesIfNeeded()
        }
        if now.timeIntervalSince(lastSlowWork) >= 0.25 {
            lastSlowWork = now
            updateCard()
            followTick()
        }
        // Zoom easing finished: the fast ticker can step down.
        if tickerFast, !needsFastTick { updateTicker() }
        guard tickerFast || zoomScale != 1 else {
            stage.updateCursor(nil, spotlight: false, highlight: false)
            return
        }

        // Map the pointer into whichever pane shows the window it is over.
        var scenePoint: CGPoint?
        for pane in 0..<2 {
            let fit = stage.paneFits[pane]
            guard let frame = sourceFrames[pane], frame.width > 0, frame.height > 0, fit.width > 0,
                  frame.contains(cursor) else { continue }
            scenePoint = CGPoint(x: fit.minX + (cursor.x - frame.minX) / frame.width * fit.width,
                                 y: fit.minY + (cursor.y - frame.minY) / frame.height * fit.height)
            break
        }

        updateZoom(towards: scenePoint, stage: stage)
        let onScreen = scenePoint.map { stage.zoomed($0) }
        let effects = card == nil
        stage.updateCursor(onScreen, spotlight: spotlight && effects, highlight: highlight && effects)
    }

    /// Eases the zoom level and centre towards their targets so zooming glides instead of jumping.
    private func updateZoom(towards point: CGPoint?, stage: StageView) {
        let targetScale: CGFloat = zoomOn && card == nil ? CGFloat(zoomLevel) : 1
        if let point { zoomCenter = zoomCenter.map { CGPoint(x: $0.x + (point.x - $0.x) * 0.25,
                                                               y: $0.y + (point.y - $0.y) * 0.25) } ?? point }
        let newScale = zoomScale + (targetScale - zoomScale) * 0.25
        zoomScale = abs(newScale - targetScale) < 0.01 ? targetScale : newScale
        guard let center = zoomCenter else { return }
        stage.setZoom(center: center, scale: zoomScale)
    }

    // MARK: Hotkeys

    /// The shortcut for each action; an action missing here has none.
    @Published private(set) var shortcuts = ShortcutAction.load()
    /// Actions whose shortcut another app already owns.
    @Published private(set) var unavailableShortcuts: Set<ShortcutAction> = []
    private var hotkeysPaused = false

    func shortcut(_ action: ShortcutAction) -> KeyCombo? { shortcuts[action] }

    /// The label for an action's shortcut, or nil when it has none.
    func shortcutLabel(_ action: ShortcutAction) -> String? { shortcuts[action]?.label }

    /// The shared modifiers ("⌃⌥⌘") when the favourite shortcuts are still the digits 1 to 9 with one
    /// modifier set, so the panel can say "⌃⌥⌘ + number". Nil once they've been customised individually.
    var favoriteModifiers: String? {
        let combos = (0..<9).map { shortcuts[.favorite($0)] }
        guard let first = combos[0], combos.enumerated().allSatisfy({ $1 == KeyCombo(ShortcutAction.favorite($0).defaultCombo.keyCode, modifiers: first.modifiers) })
        else { return nil }
        return first.modifierLabel
    }

    /// Assigns `combo` to `action`. Another action using the same combination loses it; the returned
    /// message says which.
    @discardableResult
    func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) -> String? {
        var message: String?
        if let combo, let other = shortcuts.first(where: { $0.key != action && $0.value == combo })?.key {
            shortcuts[other] = nil
            message = "\(combo.label) was \u{201C}\(other.title)\u{201D}, which now has no shortcut."
        }
        shortcuts[action] = combo
        ShortcutAction.save(shortcuts)
        registerHotkeys()
        return message
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
        ShortcutAction.save(shortcuts)
        registerHotkeys()
    }

    /// While a shortcut is being recorded, the global ones are off, so pressing an existing one records it
    /// instead of triggering it.
    func pauseHotkeys(_ paused: Bool) {
        hotkeysPaused = paused
        registerHotkeys()
    }

    private func registerHotkeys() {
        hotkeys.unregisterAll()
        guard !hotkeysPaused else { return }
        var failed: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let combo = shortcuts[action] else { continue }
            if !hotkeys.register(combo, action: { [weak self] in self?.perform(action) }) { failed.insert(action) }
        }
        unavailableShortcuts = failed
    }

    func perform(_ action: ShortcutAction) {
        if let slot = action.favoriteSlot { select(slot: slot); return }
        switch action {
        case .previous: step(-1)
        case .next: step(1)
        case .refresh: Task { await refreshSources() }
        case .power: toggleOn()
        case .split: toggleSplit()
        case .follow: follow.toggle()
        case .zoom: zoomOn.toggle()
        case .zoomIn:
            zoomLevel = min(4, zoomLevel + 0.5)
            zoomOn = true
        case .zoomOut: zoomLevel = max(1.5, zoomLevel - 0.5)
        case .spotlight: spotlight.toggle()
        case .highlight: highlight.toggle()
        case .camera: setCamera(!cameraOn)
        case .justMe: toggleJustMe()
        case .beRightBack: card == .beRightBack ? hideCard() : showBeRightBack()
        case .breakTime: breakEnd == nil ? startBreak() : stopBreak()
        case .nameTag: lowerThirdOn.toggle()
        default: break
        }
    }
}
