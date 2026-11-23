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

        capture.onFrame = { [weak self] surface in self?.stageWindow?.stage.show(frame: surface) }
        capture.onStop = { [weak self] _ in
            guard let self else { return }
            self.current = nil
            self.stageWindow?.stage.clear(message: "The shared window closed")
            Task { await self.refreshSources() }
        }

        registerHotkeys()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        Task { await refreshSources() }
    }

    func shutdown() {
        ticker?.invalidate()
        camera.stop()
        Task { await capture.stop() }
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
            if status?.hasPrefix("Screen recording") == true { status = nil }
        } catch {
            status = "Screen recording access is needed. Allow Stagehand in System Settings, then reopen it."
        }
    }

    func select(_ source: Source) {
        if breakEnd != nil { stopBreak() }
        current = source
        sourceFrame = source.currentFrame
        let filter = source.filter(excluding: ownApp)
        Task {
            do {
                try await capture.start(filter: filter, outputSize: VirtualDisplay.size)
                status = nil
            } catch {
                status = "Could not capture \(source.title): \(error.localizedDescription)"
                if current == source { current = nil }
            }
        }
    }

    func select(index: Int) {
        guard sources.indices.contains(index) else { return }
        select(sources[index])
    }

    func step(_ delta: Int) {
        guard !sources.isEmpty else { return }
        let index = current.flatMap { sources.firstIndex(of: $0) } ?? -delta
        select(index: (index + delta + sources.count) % sources.count)
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

        if tick % 6 == 0 { sourceFrame = current?.currentFrame }
        if tick % 15 == 0 { updateBreak() }

        var stagePoint: CGPoint?
        if let frame = sourceFrame, frame.width > 0, frame.height > 0, frame.contains(cursor) {
            let fit = AVMakeRect(aspectRatio: frame.size, insideRect: stage.bounds)
            stagePoint = CGPoint(x: fit.minX + (cursor.x - frame.minX) / frame.width * fit.width,
                                 y: fit.minY + (cursor.y - frame.minY) / frame.height * fit.height)
        }
        stage.updateCursor(stagePoint, spotlight: spotlight && breakEnd == nil, highlight: highlight && breakEnd == nil)
    }

    // MARK: Hotkeys

    static let shortcutHelp: [(String, String)] = [
        ("\(Hotkeys.modifierLabel)1 … 9", "Show source 1 to 9"),
        ("\(Hotkeys.modifierLabel)← / →", "Previous / next source"),
        ("\(Hotkeys.modifierLabel)C", "Webcam on / off"),
        ("\(Hotkeys.modifierLabel)S", "Spotlight on / off"),
        ("\(Hotkeys.modifierLabel)H", "Highlight cursor on / off"),
        ("\(Hotkeys.modifierLabel)B", "Start / stop break countdown"),
        ("\(Hotkeys.modifierLabel)R", "Refresh the window list"),
    ]

    private func registerHotkeys() {
        for (index, key) in Hotkeys.digitKeys.enumerated() {
            hotkeys.register(key) { [weak self] in self?.select(index: index) }
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
        hotkeys.register(kVK_ANSI_R) { [weak self] in Task { await self?.refreshSources() } }
    }
}
