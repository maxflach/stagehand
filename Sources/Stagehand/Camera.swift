import AVFoundation

/// Owns the webcam session shown in the corner of the stage.
final class Camera {
    private(set) var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "com.musicdatalabs.stagehand.camera")

    /// Calls back on the main queue with a running session, or nil if access or the device is missing.
    func start(completion: @escaping (AVCaptureSession?) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted, let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else { return DispatchQueue.main.async { completion(nil) } }
            let session = AVCaptureSession()
            session.sessionPreset = .high
            guard session.canAddInput(input) else { return DispatchQueue.main.async { completion(nil) } }
            session.addInput(input)
            self.queue.async {
                session.startRunning()
                DispatchQueue.main.async {
                    self.session = session
                    completion(session)
                }
            }
        }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        queue.async { session.stopRunning() }
    }
}
