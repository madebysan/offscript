import AVFoundation
import Combine
import CoreMedia
import Foundation

/// Mic capture via AVCaptureSession. AVAudioEngine's input tap is unreliable on
/// macOS 26 (especially with AirPods / Bluetooth mics) — AVCaptureSession
/// consistently fires and plays well with SFSpeechRecognizer.
final class MicLevelMonitor: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    // Only observed fields are @Published. Per-sample values (level, sampleCount)
    // are plain vars so they don't trigger ContentView re-renders 60x/sec.
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false

    var level: Float = 0
    var sampleCount: Int = 0
    var lastRawRMS: Float = 0
    var lastStatusMessage: String = "not started"

    /// Forward each captured audio sample buffer to subscribers (e.g. SpeechTranscriber).
    /// Invoked on the capture queue (not main).
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "com.san.Cue.capture", qos: .userInitiated)

    func start() {
        guard !isRunning else {
            Logger.shared.log("MicLevelMonitor.start called but already running")
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.shared.log("MicLevelMonitor.start — auth status=\(status.rawValue)")
        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    Logger.shared.log("mic permission response: granted=\(granted)")
                    if granted {
                        self.permissionDenied = false
                        self.startSession()
                    } else {
                        self.permissionDenied = true
                        self.lastStatusMessage = "permission denied"
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
            lastStatusMessage = "permission denied — enable in System Settings → Privacy & Security → Microphone"
        @unknown default:
            lastStatusMessage = "unknown permission status"
        }
    }

    func stop() {
        guard isRunning else { return }
        captureSession?.stopRunning()
        captureSession = nil
        isRunning = false
        level = 0
        lastStatusMessage = "stopped"
        Logger.shared.log("MicLevelMonitor.stop — capture stopped")
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            lastStatusMessage = "no audio input device"
            Logger.shared.log("AVCaptureDevice.default(.audio) returned nil")
            return
        }
        Logger.shared.log("AVCaptureDevice: \(device.localizedName)")

        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                lastStatusMessage = "cannot add input"
                return
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: captureQueue)
            guard session.canAddOutput(output) else {
                lastStatusMessage = "cannot add output"
                return
            }
            session.addOutput(output)

            session.startRunning()
            captureSession = session
            isRunning = true
            lastStatusMessage = "running on \(device.localizedName)"
            Logger.shared.log("AVCaptureSession started on \(device.localizedName)")
        } catch {
            lastStatusMessage = "capture setup failed: \(error.localizedDescription)"
            Logger.shared.log("AVCaptureSession setup failed: \(error)")
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Forward to speech recognizer first (no conversion needed — SFSpeech accepts CMSampleBuffer).
        onSampleBuffer?(sampleBuffer)

        let raw = Self.rms(sampleBuffer: sampleBuffer)
        let scaled = min(1.0, max(0.0, raw * 15))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.sampleCount == 0 {
                Logger.shared.log("FIRST SAMPLE — raw=\(String(format: "%.5f", raw)), subscriber=\(self.onSampleBuffer != nil)")
            }
            self.sampleCount += 1
            self.lastRawRMS = raw
            self.level = scaled
            if self.sampleCount % 120 == 0 {
                Logger.shared.log("sample #\(self.sampleCount) raw=\(String(format: "%.5f", raw))")
            }
        }
    }

    private static func rms(sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>? = nil
        CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard let ptr = dataPointer, totalLength > 0 else { return 0 }
        let floatCount = totalLength / MemoryLayout<Float>.size
        guard floatCount > 0 else { return 0 }
        let floatPtr = ptr.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 }
        var sum: Float = 0
        for i in 0..<floatCount {
            let sample = floatPtr[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(floatCount))
    }
}
