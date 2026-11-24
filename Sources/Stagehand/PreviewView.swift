import AppKit
import SwiftUI

/// Shows frames of the virtual display: exactly what the meeting receives, overlays included.
final class PreviewView: NSView {
    private let content = CALayer()

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        content.contentsGravity = .resizeAspect
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = bounds
        CATransaction.commit()
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.contents = nil
        CATransaction.commit()
    }

    func show(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.contents = surface
        CATransaction.commit()
    }
}

struct PreviewRepresentable: NSViewRepresentable {
    let view: PreviewView
    func makeNSView(context: Context) -> PreviewView { view }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}
