import AVFoundation
import AppKit
import QuartzCore

/// What the meeting sees: the captured source with overlays on top. Layer coordinates are top-left based.
final class StageView: NSView {
    private let content = CALayer()
    private let placeholder = CATextLayer()
    private let dim = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let cameraFrame = CALayer()
    private var cameraLayer: AVCaptureVideoPreviewLayer?
    private let breakBackground = CAGradientLayer()
    private let breakTitle = CATextLayer()
    private let breakClock = CATextLayer()

    static let spotlightRadius: CGFloat = 170
    static let ringRadius: CGFloat = 38
    static let cameraDiameter: CGFloat = 300
    static let margin: CGFloat = 40

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.isGeometryFlipped = true
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        wantsLayer = true

        content.contentsGravity = .resize
        root.addSublayer(content)

        placeholder.string = "Pick a window in Stagehand"
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

        cameraFrame.cornerRadius = Self.cameraDiameter / 2
        cameraFrame.masksToBounds = true
        cameraFrame.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        cameraFrame.borderWidth = 5
        cameraFrame.backgroundColor = NSColor.darkGray.cgColor
        cameraFrame.isHidden = true
        root.addSublayer(cameraFrame)

        breakBackground.colors = [NSColor(red: 0.12, green: 0.10, blue: 0.24, alpha: 1).cgColor,
                                  NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1).cgColor]
        breakBackground.isHidden = true
        root.addSublayer(breakBackground)
        for (layer, size, alpha) in [(breakTitle, 56.0, 0.75), (breakClock, 220.0, 1.0)] {
            layer.alignmentMode = .center
            layer.fontSize = size
            layer.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            layer.foregroundColor = NSColor(white: 1, alpha: alpha).cgColor
            layer.contentsScale = 2
            breakBackground.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        withoutAnimation {
            let b = bounds
            content.frame = b
            placeholder.frame = CGRect(x: 0, y: b.midY - 24, width: b.width, height: 48)
            breakBackground.frame = b
            breakTitle.frame = CGRect(x: 0, y: b.midY - 200, width: b.width, height: 70)
            breakClock.frame = CGRect(x: 0, y: b.midY - 110, width: b.width, height: 260)
            let d = Self.cameraDiameter
            cameraFrame.frame = CGRect(x: b.maxX - d - Self.margin, y: b.maxY - d - Self.margin, width: d, height: d)
            cameraLayer?.frame = cameraFrame.bounds
        }
    }

    // MARK: Content

    func show(frame surface: IOSurface) {
        withoutAnimation {
            content.contents = surface
            placeholder.isHidden = true
        }
    }

    func clear(message: String) {
        withoutAnimation {
            content.contents = nil
            placeholder.string = message
            placeholder.isHidden = false
        }
    }

    // MARK: Cursor effects

    /// `point` is in stage coordinates, nil when the cursor is outside the shared source.
    func updateCursor(_ point: CGPoint?, spotlight: Bool, highlight: Bool) {
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
                preview.frame = cameraFrame.bounds
                cameraFrame.addSublayer(preview)
                cameraLayer = preview
            }
            cameraFrame.isHidden = session == nil
        }
    }

    // MARK: Break countdown

    func showBreak(title: String?, clock: String?) {
        withoutAnimation {
            breakBackground.isHidden = title == nil
            breakTitle.string = title
            breakClock.string = clock
        }
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
