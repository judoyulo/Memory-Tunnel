// VoiceMemoryService.swift
// AVAudioRecorder wrapper for voice memory capture.
// Records to M4A (AAC) in the temp directory; caller gets the file URL on stop.
// Metering is sampled at 20 Hz for WaveformView animation.

import AVFoundation
import Foundation

@MainActor
final class VoiceMemoryService: NSObject, ObservableObject {

    static let shared = VoiceMemoryService()

    @Published var isRecording  = false
    @Published var level: Float = 0        // normalized 0…1 for waveform animation
    @Published var duration: TimeInterval = 0

    let maxDuration: TimeInterval = 60

    private var recorder:      AVAudioRecorder?
    private var levelTimer:    Timer?
    private var durationTimer: Timer?
    private(set) var recordedURL: URL?

    private override init() { super.init() }

    // MARK: - Recording lifecycle

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        recordedURL = url

        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatMPEG4AAC,
            AVSampleRateKey:           44100,
            AVNumberOfChannelsKey:     1,
            AVEncoderAudioQualityKey:  AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey:       64000
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        recorder?.record(forDuration: maxDuration)

        isRecording = true
        duration    = 0

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.duration = self?.recorder?.currentTime ?? 0
            }
        }
    }

    /// Stop recording and return the URL of the captured file.
    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        teardown()
        return recordedURL
    }

    func cancelRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        recordedURL = nil
        teardown()
    }

    // MARK: - Private

    private func tick() {
        recorder?.updateMeters()
        let db = recorder?.averagePower(forChannel: 0) ?? -80
        // Map -60 dB … 0 dB → 0 … 1
        level = max(0, min(1, (db + 60) / 60))
    }

    private func teardown() {
        levelTimer?.invalidate();    levelTimer    = nil
        durationTimer?.invalidate(); durationTimer = nil
        isRecording = false
        level       = 0
    }
}

extension VoiceMemoryService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.teardown() }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.teardown() }
    }
}
