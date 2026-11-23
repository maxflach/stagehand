import AVFoundation
import AppKit
import QuartzCore

/// How the webcam appears on stage.
struct CameraStyle: Codable, Equatable {
    enum Corner: String, Codable, CaseIterable { case bottomRight, bottomLeft, topRight, topLeft }
    enum Size: String, Codable, CaseIterable { case small, medium, large }
    enum Shape: String, Codable, CaseIterable { case circle, rounded }

    var corner: Corner = .bottomRight
    var size: Size = .medium
    var shape: Shape = .circle
    var fullScreen = false

    var diameter: CGFloat {
        switch size {
        case .small: return 220
        case .medium: return 300
        case .large: return 420
        }
    }

    private static let key = "cameraStyle"
    static func load() -> CameraStyle {
        guard let data = UserDefaults.standard.data(forKey: key),
              let style = try? JSONDecoder().decode(CameraStyle.self, from: data) else { return CameraStyle() }
        return style
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// What the meeting sees: one or two captured sources with overlays on top.
///
/// Coordinates: CALayers here use AppKit's bottom-left origin. Everything passed in or out of this class
/// (pane rects, cursor points, zoom centre) is top-left based like CoreGraphics screen coordinates, and is
/// converted at the boundary.
///
/// Layer order, bottom to top: scene (panes with content, zoomable), placeholder, spotlight dim, highlight ring,
/// lower third, webcam, title card.
final class StageView: NSView {
    private let scene = CALayer()
    private let panes = [CALayer(), CALayer()]
    private let contents = [CALayer(), CALayer()]
    private let placeholder = CATextLayer()
    private let dim = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let lowerThird = CAGradientLayer()
    private let lowerName = CATextLayer()
    private let lowerRole = CATextLayer()
    private let cameraFrame = CALayer()
    private var cameraLayer: AVCaptureVideoPreviewLayer?
    private let card = CAGradientLayer()
    private let cardTitle = CATextLayer()
    private let cardClock = CATextLayer()
    private let cardSubtitle = CATextLayer()

    static let spotlightRadius: CGFloat = 170
    static let ringRadius: CGFloat = 38
    static let margin: CGFloat = 40
    static let splitGap: CGFloat = 16

    private(set) var split = false
    private var bufferSizes: [CGSize?] = [nil, nil]
    /// Where each pane's content sits on the stage, top-left based, before zoom. Zero when the pane is empty.
    private(set) var paneFits: [CGRect] = [.zero, .zero]

    private var zoomCenter = CGPoint.zero
    private var zoomScale: CGFloat = 1
    private var cameraStyle = CameraStyle()
    private var lowerThirdText: (name: String, role: String)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        wantsLayer = true

        scene.anchorPoint = .zero
        root.addSublayer(scene)
        for (pane, content) in zip(panes, contents) {
            pane.masksToBounds = true
            content.contentsGravity = .resizeAspect
            pane.addSublayer(content)
            scene.addSublayer(pane)
        }

        placeholder.alignmentMode = .center
        placeholder.fontSize = 34
        placeholder.foregroundColor = NSColor(white: 1, alpha: 0.5).cgColor
        placeholder.contentsScale = 2
        root.addSublayer(placeholder)

        dim.fillRule = .evenOdd
        dim.fillColor = NSColor(white: 0, alpha: 0.62).cgColor
        dim.isHidden = true
        root.addSublayer(dim)

        ring.fillColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        ring.strokeColor = NSColor.systemYellow.cgColor
        ring.lineWidth = 5
        ring.isHidden = true
        root.addSublayer(ring)

        lowerThird.colors = [NSColor(red: 0.30, green: 0.22, blue: 0.70, alpha: 0.92).cgColor,
                             NSColor(red: 0.12, green: 0.09, blue: 0.30, alpha: 0.92).cgColor]
        lowerThird.startPoint = CGPoint(x: 0, y: 0.5)
        lowerThird.endPoint = CGPoint(x: 1, y: 0.5)
        lowerThird.cornerRadius = 18
        lowerThird.isHidden = true
        for (layer, size, weight, alpha) in [(lowerName, 34.0, NSFont.Weight.bold, 1.0), (lowerRole, 22.0, .medium, 0.75)] {
            layer.font = NSFont.systemFont(ofSize: size, weight: weight)
            layer.fontSize = size
            layer.foregroundColor = NSColor(white: 1, alpha: alpha).cgColor
            layer.contentsScale = 2
            lowerThird.addSublayer(layer)
        }
        root.addSublayer(lowerThird)

        cameraFrame.masksToBounds = true
        cameraFrame.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        cameraFrame.backgroundColor = NSColor.darkGray.cgColor
        cameraFrame.isHidden = true
        root.addSublayer(cameraFrame)

        card.colors = [NSColor(red: 0.20, green: 0.16, blue: 0.42, alpha: 1).cgColor,
                       NSColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 1).cgColor]
        card.isHidden = true
        for (layer, size, alpha) in [(cardTitle, 64.0, 0.85), (cardClock, 220.0, 1.0), (cardSubtitle, 30.0, 0.6)] {
            layer.alignmentMode = .center
            layer.fontSize = size
            layer.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            layer.foregroundColor = NSColor(white: 1, alpha: alpha).cgColor
            layer.contentsScale = 2
            card.addSublayer(layer)
        }
        root.addSublayer(card)

        clear(message: "Pick a window in Stagehand")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        withoutAnimation {
            let b = bounds
            scene.bounds = b
            scene.position = .zero
            placeholder.frame = CGRect(x: 0, y: b.midY - 24, width: b.width, height: 48)
            card.frame = b
            cardTitle.frame = CGRect(x: 0, y: b.midY + 140, width: b.width, height: 80)
            cardClock.frame = CGRect(x: 0, y: b.midY - 150, width: b.width, height: 260)
            cardSubtitle.frame = CGRect(x: 0, y: b.midY - 230, width: b.width, height: 44)
            layoutPanes()
            layoutCamera()
            layoutLowerThird()
            applyZoom()
        }
    }

    // MARK: Panes

    /// Pane rects in top-left coordinates.
    func paneRects(split: Bool) -> [CGRect] {
        let b = bounds
        guard split else { return [b, .zero] }
        let w = (b.width - Self.splitGap * 3) / 2
        let h = b.height - Self.splitGap * 2
        return [CGRect(x: Self.splitGap, y: Self.splitGap, width: w, height: h),
                CGRect(x: Self.splitGap * 2 + w, y: Self.splitGap, width: w, height: h)]
    }

    func setSplit(_ on: Bool) {
        split = on
        if !on { clearPane(1) }
        withoutAnimation { layoutPanes() }
    }

    private func layoutPanes() {
        let rects = paneRects(split: split)
        for i in 0..<2 {
            let rect = rects[i]
            panes[i].isHidden = rect == .zero
            panes[i].frame = flipped(rect)
            guard let buffer = bufferSizes[i], contents[i].contents != nil, rect != .zero else {
                paneFits[i] = .zero
                continue
            }
            // The capture is sized to the source's aspect ratio, so the whole buffer is content: centre it.
            let fit = AVMakeRect(aspectRatio: buffer, insideRect: CGRect(origin: .zero, size: rect.size)).integral
            contents[i].frame = CGRect(x: fit.minX, y: rect.height - fit.maxY, width: fit.width, height: fit.height)
            paneFits[i] = fit.offsetBy(dx: rect.minX, dy: rect.minY)
        }
    }

    func show(frame surface: IOSurface, pane: Int) {
        let size = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        let changed = bufferSizes[pane] != size
        bufferSizes[pane] = size
        withoutAnimation {
            contents[pane].contents = surface
            placeholder.isHidden = true
            if changed || paneFits[pane] == .zero { layoutPanes() }
        }
    }

    func clearPane(_ pane: Int) {
        withoutAnimation {
            contents[pane].contents = nil
            bufferSizes[pane] = nil
            paneFits[pane] = .zero
        }
    }

    func clear(message: String) {
        clearPane(0)
        clearPane(1)
        withoutAnimation {
            placeholder.string = message
            placeholder.isHidden = false
        }
    }

    // MARK: Zoom

    /// Magnifies the scene around `center` (top-left stage coordinates). Scale 1 turns zoom off.
    func setZoom(center: CGPoint, scale: CGFloat) {
        zoomCenter = center
        zoomScale = scale
        withoutAnimation { applyZoom() }
    }

    /// Where a scene point ends up on screen after zoom.
    func zoomed(_ p: CGPoint) -> CGPoint {
        CGPoint(x: zoomCenter.x + (p.x - zoomCenter.x) * zoomScale,
                y: zoomCenter.y + (p.y - zoomCenter.y) * zoomScale)
    }

    private func applyZoom() {
        // Scaling about a point inside the stage keeps the visible region inside the stage, so no clamping.
        let c = CGPoint(x: zoomCenter.x, y: bounds.height - zoomCenter.y)
        var t = CATransform3DMakeTranslation(c.x, c.y, 0)
        t = CATransform3DScale(t, zoomScale, zoomScale, 1)
        t = CATransform3DTranslate(t, -c.x, -c.y, 0)
        scene.transform = zoomScale == 1 ? CATransform3DIdentity : t
    }

    // MARK: Cursor effects

    /// `topLeftPoint` is on-screen stage coordinates (after zoom), nil when the cursor is outside the sources.
    func updateCursor(_ topLeftPoint: CGPoint?, spotlight: Bool, highlight: Bool) {
        let point = topLeftPoint.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        withoutAnimation {
            dim.isHidden = !spotlight
            if spotlight {
                let path = CGMutablePath()
                path.addRect(bounds)
                if let point {
                    let r = Self.spotlightRadius
                    path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
                }
                dim.path = path
            }
            ring.isHidden = !(highlight && point != nil)
            if highlight, let point {
                let r = Self.ringRadius
                ring.path = CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r), transform: nil)
            }
        }
    }

    // MARK: Camera

    func showCamera(_ session: AVCaptureSession?) {
        withoutAnimation {
            cameraLayer?.removeFromSuperlayer()
            cameraLayer = nil
            if let session {
                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                cameraFrame.addSublayer(preview)
                cameraLayer = preview
            }
            cameraFrame.isHidden = session == nil
            layoutCamera()
            layoutLowerThird()
        }
    }

    func setCameraStyle(_ style: CameraStyle) {
        cameraStyle = style
        // A short animation makes corner and size changes feel deliberate.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        layoutCamera()
        layoutLowerThird()
        CATransaction.commit()
    }

    /// Camera rect in top-left coordinates, nil when hidden.
    private var cameraRect: CGRect? {
        guard cameraLayer != nil else { return nil }
        let b = bounds
        if cameraStyle.fullScreen { return b }
        let d = cameraStyle.diameter
        let m = Self.margin
        let x = (cameraStyle.corner == .bottomLeft || cameraStyle.corner == .topLeft) ? m : b.width - d - m
        let y = (cameraStyle.corner == .topLeft || cameraStyle.corner == .topRight) ? m : b.height - d - m
        return CGRect(x: x, y: y, width: d, height: d)
    }

    private func layoutCamera() {
        guard let rect = cameraRect else { return }
        cameraFrame.frame = flipped(rect)
        cameraLayer?.frame = cameraFrame.bounds
        if cameraStyle.fullScreen {
            cameraFrame.cornerRadius = 0
            cameraFrame.borderWidth = 0
        } else {
            cameraFrame.cornerRadius = cameraStyle.shape == .circle ? rect.width / 2 : rect.width * 0.16
            cameraFrame.borderWidth = 5
        }
    }

    // MARK: Lower third

    func showLowerThird(name: String?, role: String?) {
        let name = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let role = role?.trimmingCharacters(in: .whitespaces) ?? ""
        lowerThirdText = name.isEmpty && role.isEmpty ? nil : (name, role)
        withoutAnimation {
            lowerName.string = name
            lowerRole.string = role
            layoutLowerThird()
        }
    }

    private func layoutLowerThird() {
        guard let text = lowerThirdText else {
            lowerThird.isHidden = true
            return
        }
        lowerThird.isHidden = cameraStyle.fullScreen && cameraLayer != nil
        let nameWidth = (text.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold)]).width
        let roleWidth = (text.role as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium)]).width
        let width = max(nameWidth, roleWidth) + 64
        let height: CGFloat = text.role.isEmpty || text.name.isEmpty ? 76 : 108
        // Bottom left, moved right of the webcam when the webcam sits in that corner.
        var x = Self.margin
        if let cam = cameraRect, !cameraStyle.fullScreen, cameraStyle.corner == .bottomLeft { x = cam.maxX + 24 }
        let rect = CGRect(x: x, y: bounds.height - Self.margin - height, width: width, height: height)
        lowerThird.frame = flipped(rect)
        let inner = lowerThird.bounds.insetBy(dx: 32, dy: 0)
        if text.role.isEmpty || text.name.isEmpty {
            let single = text.name.isEmpty ? lowerRole : lowerName
            (text.name.isEmpty ? lowerName : lowerRole).frame = .zero
            single.frame = CGRect(x: inner.minX, y: (height - 42) / 2, width: inner.width, height: 44)
        } else {
            lowerName.frame = CGRect(x: inner.minX, y: 48, width: inner.width, height: 44)
            lowerRole.frame = CGRect(x: inner.minX, y: 18, width: inner.width, height: 30)
        }
    }

    // MARK: Title cards

    /// A full-stage card. `title` nil hides it.
    func showCard(title: String?, clock: String?, subtitle: String?) {
        withoutAnimation {
            card.isHidden = title == nil
            cardTitle.string = title
            cardClock.string = clock
            cardSubtitle.string = subtitle
            // Without a clock, centre the title.
            if clock == nil || clock?.isEmpty == true {
                cardTitle.frame = CGRect(x: 0, y: bounds.midY - 40, width: bounds.width, height: 80)
                cardSubtitle.frame = CGRect(x: 0, y: bounds.midY - 100, width: bounds.width, height: 44)
            } else {
                cardTitle.frame = CGRect(x: 0, y: bounds.midY + 140, width: bounds.width, height: 80)
                cardSubtitle.frame = CGRect(x: 0, y: bounds.midY - 230, width: bounds.width, height: 44)
            }
        }
    }

    // MARK: Helpers

    /// Converts a top-left based rect to this view's bottom-left layer coordinates.
    private func flipped(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

/// A borderless window that covers the virtual display.
final class StageWindow: NSWindow {
    let stage: StageView

    init(screen: NSScreen) {
        stage = StageView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        contentView = stage
        isReleasedWhenClosed = false
        backgroundColor = .black
        level = .screenSaver // above the menu bar and Dock, but only on the virtual display
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
