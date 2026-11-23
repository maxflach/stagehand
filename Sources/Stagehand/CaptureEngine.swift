import CoreMedia
import IOSurface
import ScreenCaptureKit

/// Streams one source with ScreenCaptureKit and hands each finished frame to `onFrame`.
///
/// The output size should match the source's aspect ratio (see `fittedSize`). ScreenCaptureKit pads
/// mismatched content, and where it puts the padding differs between windows (top-left) and screens
/// (centred), so matching the aspect avoids padding instead of guessing its position.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((IOSurface, CGSize?) -> Void)?
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private(set) var outputSize: CGSize = .zero

    /// The largest size with `aspect` that fits in `box`, rounded to even pixels.
    static func fittedSize(aspect: CGSize, in box: CGSize) -> CGSize {
        guard aspect.width > 0, aspect.height > 0 else { return box }
        let scale = min(box.width / aspect.width, box.height / aspect.height)
        return CGSize(width: max(2, (aspect.width * scale / 2).rounded() * 2),
                      height: max(2, (aspect.height * scale / 2).rounded() * 2))
    }

    /// Changes the output size of the running stream, e.g. after the window was resized.
    func resize(to size: CGSize) async {
        guard let stream, let config, size != outputSize else { return }
        outputSize = size
        config.width = Int(size.width)
        config.height = Int(size.height)
        try? await stream.updateConfiguration(config)
    }
    private let queue = DispatchQueue(label: "com.musicdatalabs.stagehand.capture", qos: .userInteractive)

    func start(filter: SCContentFilter, outputSize: CGSize, fps: Int32 = 60) async throws {
        await stop()
        let config = SCStreamConfiguration()
        config.width = Int(outputSize.width)
        config.height = Int(outputSize.height)
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.queueDepth = 6

        self.config = config
        self.outputSize = outputSize
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = buffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        var contentSize: CGSize?
        if let dict = attachments.first?[.contentRect] as! CFDictionary?,
           let rect = CGRect(dictionaryRepresentation: dict), rect.width > 0, rect.height > 0 {
            contentSize = rect.size
        }
        DispatchQueue.main.async { [weak self] in self?.onFrame?(surface, contentSize) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.onStop?(error)
        }
    }
}
