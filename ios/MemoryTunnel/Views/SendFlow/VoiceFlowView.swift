// VoiceFlowView.swift
// Voice memory recording flow. Steps: record → preview → caption → sending → sent / error.
// Parallels SendFlowView for photos; reuses the same presign → S3 → createMemory pipeline.

import SwiftUI
import AVFoundation

// MARK: - ViewModel

@MainActor
final class VoiceFlowViewModel: ObservableObject {

    enum Step { case record, preview, caption, sending, sent, error(String) }

    @Published var step: Step = .record
    @Published var caption: String = ""

    private(set) var recordedURL: URL?
    private let recorder = VoiceMemoryService.shared

    let chapterID: String
    init(chapterID: String) { self.chapterID = chapterID }

    // MARK: - Actions

    func startRecording() {
        try? recorder.startRecording()
    }

    func stopRecording() {
        recordedURL = recorder.stopRecording()
        if recordedURL != nil { step = .preview }
    }

    func cancelRecording() {
        recorder.cancelRecording()
        recordedURL = nil
    }

    func retake() {
        recordedURL = nil
        step = .record
    }

    func send() async {
        guard let url = recordedURL,
              let data = try? Data(contentsOf: url) else { return }
        step = .sending

        do {
            // 1. Presign with audio/m4a so S3 key gets .m4a extension
            let presign = try await APIClient.shared.presign(
                chapterID:   chapterID,
                contentType: "audio/m4a"
            )

            // 2. Upload directly to S3
            try await APIClient.shared.uploadToS3(data: data, presign: presign, contentType: "audio/m4a")

            // 3. Create memory record — media_type: "voice"
            _ = try await APIClient.shared.createMemory(
                chapterID:  chapterID,
                s3Key:      presign.s3Key,
                caption:    caption.isEmpty ? nil : caption,
                takenAt:    nil,
                visibility: "this_item",
                mediaType:  "voice"
            )

            step = .sent
        } catch {
            step = .error(error.localizedDescription)
        }
    }
}

// MARK: - View

struct VoiceFlowView: View {
    let chapterID: String
    @StateObject private var vm: VoiceFlowViewModel
    @ObservedObject private var recorder = VoiceMemoryService.shared
    @Environment(\.dismiss) private var dismiss

    init(chapterID: String) {
        self.chapterID = chapterID
        _vm = StateObject(wrappedValue: VoiceFlowViewModel(chapterID: chapterID))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtBackground.ignoresSafeArea()

                switch vm.step {
                case .record:
                    RecordStep(vm: vm, recorder: recorder)
                case .preview:
                    PreviewStep(vm: vm)
                case .caption:
                    CaptionStep(vm: vm)
                case .sending:
                    SendingStep()
                case .sent:
                    SentStep { dismiss() }
                case .error(let msg):
                    VoiceErrorStep(message: msg) { vm.step = .caption }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .sent = vm.step { EmptyView() }
                    else {
                        Button("Cancel") {
                            recorder.cancelRecording()
                            dismiss()
                        }
                        .foregroundStyle(Color.mtSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Step: Record

private struct RecordStep: View {
    @ObservedObject var vm: VoiceFlowViewModel
    @ObservedObject var recorder: VoiceMemoryService

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text(recorder.isRecording ? "Recording…" : "Hold to record")
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                    .multilineTextAlignment(.center)

                Text(recorder.isRecording
                     ? timeString(recorder.duration)
                     : "Up to 60 seconds")
                    .font(.mtCaption)
                    .foregroundStyle(Color.mtSecondary)
                    .monospacedDigit()
            }

            WaveformView(level: recorder.level, isAnimating: recorder.isRecording)
                .frame(height: 56)
                .opacity(recorder.isRecording ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)

            RecordButton(
                isRecording: recorder.isRecording,
                duration:    recorder.duration,
                onStart:     { vm.startRecording() },
                onStop:      { vm.stopRecording() }
            )

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Step: Preview

private struct PreviewStep: View {
    @ObservedObject var vm: VoiceFlowViewModel

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text("Preview")
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                Text("Sounds good?")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
            }

            // Inline player
            if let url = vm.recordedURL {
                VoicePlayerView(url: url)
                    .padding(.horizontal, Spacing.xl)
            }

            VStack(spacing: Spacing.sm) {
                Button {
                    vm.step = .caption
                } label: {
                    Text("Looks good — continue")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                Button("Record again") { vm.retake() }
                    .font(.mtLabel)
                    .foregroundStyle(Color.mtSecondary)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Caption

private struct CaptionStep: View {
    @ObservedObject var vm: VoiceFlowViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            if let url = vm.recordedURL {
                VoicePlayerView(url: url)
                    .padding(.horizontal, Spacing.xl)
            }

            VStack(spacing: Spacing.md) {
                TextField("Add a caption… (optional)", text: $vm.caption, axis: .vertical)
                    .font(.mtBody)
                    .foregroundStyle(Color.mtLabel)
                    .lineLimit(3)
                    .focused($focused)
                    .padding(Spacing.md)
                    .background(Color.mtSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))

                Button {
                    focused = false
                    Task { await vm.send() }
                } label: {
                    Text("Send")
                        .font(.mtButton)
                        .foregroundStyle(Color.mtBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.mtLabel)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
        }
    }
}

// MARK: - Step: Sending

private struct SendingStep: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
            Text("Sending…")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
    }
}

// MARK: - Step: Sent ✓

private struct SentStep: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.mtAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.mtAccent)
            }

            Text("Voice clip sent")
                .font(.mtDisplay)
                .foregroundStyle(Color.mtLabel)

            Text("Come back tomorrow.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)

            Button("Done") { dismiss() }
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)

            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Step: Error

private struct VoiceErrorStep: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("Something went wrong")
                .font(.mtTitle)
                .foregroundStyle(Color.mtLabel)
            Text(message)
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .font(.mtLabel)
                .foregroundStyle(Color.mtSecondary)
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - VoicePlayerView

/// Inline play/pause player for a local or remote audio URL.
struct VoicePlayerView: View {
    let url: URL

    @State private var player:     AVAudioPlayer?
    @State private var isPlaying:  Bool = false
    @State private var progress:   Float = 0
    @State private var timer:      Timer?

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.mtLabel)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play voice clip")

            WaveformView(level: isPlaying ? Float(progress) : 0,
                         isAnimating: isPlaying)
                .frame(height: 44)

            Text(durationLabel)
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .padding(Spacing.md)
        .background(Color.mtSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .onDisappear { stopPlayback() }
    }

    private var durationLabel: String {
        guard let p = player else { return "0:00" }
        let t = isPlaying ? p.currentTime : p.duration
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { return }

        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }

        player?.play()
        isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let p = player, p.isPlaying else {
                    stopPlayback(); return
                }
                progress = Float(p.currentTime / p.duration)
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        progress  = 0
        timer?.invalidate()
        timer = nil
    }
}
