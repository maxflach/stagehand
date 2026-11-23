import CoreMedia
import IOSurface
import ScreenCaptureKit

/// Streams one source with ScreenCaptureKit and hands each finished frame to `onFrame`, together with the
/// size of the captured content. ScreenCaptureKit scales the content to fit but pins it to the top-left of
/// the buffer, so the stage needs the real content size to centre it.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((IOSurface, CGSize?) -> Void)?
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
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
