import CGVirtualDisplayPrivate
import CoreGraphics
import Foundation

/// The extra display that the meeting app shares. Approach from DeskPad (MIT), see THIRD_PARTY_NOTICES.md.
final class VirtualDisplay {
    static let name = "Stagehand"
    static let size = CGSize(width: 1920, height: 1080)

    private let display: CGVirtualDisplay
    var displayID: CGDirectDisplayID { display.displayID }

    init?() {
        let width = UInt(Self.size.width), height = UInt(Self.size.height)
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = Self.name
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        descriptor.sizeInMillimeters = CGSize(width: 527, height: 296) // a 24" 16:9 panel
        descriptor.vendorID = 0x5354
        descriptor.productID = 0x4748
        descriptor.serialNum = 1

        let display = CGVirtualDisplay(descriptor: descriptor)
        guard display.displayID != 0 else { return nil }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [CGVirtualDisplayMode(width: width, height: height, refreshRate: 60)]
        guard display.apply(settings) else { return nil }
        self.display = display
    }

    var bounds: CGRect { CGDisplayBounds(displayID) }
}
