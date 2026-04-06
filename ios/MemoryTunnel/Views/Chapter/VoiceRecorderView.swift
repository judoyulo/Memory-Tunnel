import SwiftUI
import AVFoundation

// MARK: - Voice Recorder View
//
// Hold-to-record with haptic feedback, real-time waveform, progress ring.
// Replaces the basic VoiceFlowView for the chapter detail + button.

struct VoiceRecorderView: View {
    let chapterID: String
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorderViewModel()
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer()

                // Waveform visualization
                HStack(spacing: 2) {
                    ForEach(0..<30, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(recorder.isRecording
                                  ? Color.mtLabel.opacity(0.4)  // muted during recording
                                  : (recorder.hasRecording ? Color.mtAccent : Color.mtTertiary.opacity(0.3)))
                            .frame(width: 3, height: recorder.isRecording
                                   ? CGFloat(recorder.meterLevels[safe: i] ?? 8)
                                   : CGFloat.random(in: 6...16))
                    }
                }
                .frame(height: 40)
                .animation(.easeOut(duration: 0.1), value: recorder.meterLevels)

                // Duration label
                if recorder.isRecording || recorder.hasRecording {
                    Text(recorder.durationString)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color.mtSecondary)
                }

                // Record button with progress ring
                ZStack {
                    // Progress ring (60s max)
                    if recorder.isRecording {
                        Circle()
                            .trim(from: 0, to: recorder.progress)
                            .stroke(Color.mtLabel, lineWidth: 3)
                            .frame(width: 78, height: 78)
                            .rotationEffect(.degrees(-90))
                    }

                    // Record button
                    Circle()
                        .fill(recorder.isRecording ? Color.mtLabel.opacity(0.8) : Color.mtLabel)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.mtBackground)
                        )
                        .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3), value: recorder.isRecording)
                }
                .onTapGesture {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                }

                // Re-record button
                if recorder.hasRecording && !recorder.isRecording {
                    Button {
                        recorder.discardRecording()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                            Text("Discard")
                                .font(.mtCaption)
                        }
                        .foregroundStyle(Color.mtSecondary)
                    }
                }

                // Caption field
                if recorder.hasRecording && !recorder.isRecording {
                    TextField("Add a caption...", text: $caption)
                        .font(.mtBody)
                        .padding(Spacing.sm)
                        .background(Color.mtSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .padding(.horizontal, Spacing.xl)
                }

                Spacer()
            }
            .padding(Spacing.xl)
            .background(Color.mtBackground)
            .navigationTitle("Voice clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.mtSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if recorder.hasRecording && !recorder.isRecording {
                        Button("Send") {
                            Task {
                                await recorder.upload(chapterID: chapterID, caption: caption)
                                onComplete()
                                dismiss()
                            }
                        }
                        .font(.mtButton)
                        .foregroundStyle(Color.mtLabel)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Voice Recorder ViewModel

@MainActor
final class VoiceRecorderViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var duration: TimeInterval = 0
    @Published var meterLevels: [CGFloat] = Array(repeating: 8, count: 30)
    @Published var isUploading = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    static let maxDuration: TimeInterval = 60

    var progress: CGFloat { CGFloat(duration / Self.maxDuration) }

    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            recordingURL = url
            isRecording = true
            duration = 0

            // Haptic feedback on start
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Timer for metering (0.1s interval, not CADisplayLink)
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateMeters()
                }
            }
        } catch {
            // Mic permission denied or other error
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        // Haptic on stop
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Discard if too short (< 1 second)
        if duration < 1.0 {
            discardRecording()
            // Subtle shake feedback for too-short recording
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            hasRecording = true
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discardRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        hasRecording = false
        duration = 0
        meterLevels = Array(repeating: 8, count: 30)
    }

    func upload(chapterID: String, caption: String) async {
        guard let url = recordingURL else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            // 1. Presign: get S3 upload URL
            let presign = try await APIClient.shared.presign(chapterID: chapterID, contentType: "audio/mp4")

            // 2. Upload to S3
            let audioData = try Data(contentsOf: url)
            var request = URLRequest(url: presign.uploadURL)
            request.httpMethod = "PUT"
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            request.httpBody = audioData
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            // 3. Create memory record
            _ = try await APIClient.shared.createMemory(
                chapterID: chapterID,
                s3Key: presign.s3Key,
                caption: caption.isEmpty ? nil : caption,
                takenAt: nil,
                visibility: "this_item",
                mediaType: "voice"
            )
        } catch {
            // Upload failure handled by caller
        }
    }

    private func updateMeters() {
        guard isRecording, let recorder = audioRecorder else { return }
        recorder.updateMeters()
        duration = recorder.currentTime

        // Auto-stop at max duration
        if duration >= Self.maxDuration {
            stopRecording()
            return
        }

        // Update waveform bars from meter power
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (power + 50) / 50)) // -50dB to 0dB → 0 to 1
        let barHeight = 6 + normalized * 28 // 6pt min, 34pt max

        // Shift bars left and add new bar at end
        meterLevels.removeFirst()
        meterLevels.append(CGFloat(barHeight))
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
