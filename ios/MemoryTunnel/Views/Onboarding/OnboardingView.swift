import SwiftUI
import Photos

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Equatable {
        case welcome
        case phone
        case devCode          // developer bypass
        case code
        case name
        case photoPermission
        case faceBubbles
        case chapterCreation(FaceSuggestion?)   // nil = manual mode
        case done

        static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.welcome, .welcome), (.phone, .phone), (.devCode, .devCode),
                 (.code, .code), (.name, .name), (.photoPermission, .photoPermission),
                 (.faceBubbles, .faceBubbles), (.done, .done): return true
            case (.chapterCreation, .chapterCreation): return true
            default: return false
            }
        }
    }

    @Published var step: Step = .welcome
    @Published var phone: String = ""
    @Published var code: String = ""
    @Published var devCode: String = ""
    @Published var displayName: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isComplete = false

    // Face scanning
    @Published var faceSuggestions: [FaceSuggestion] = []
    @Published var isScanning = false
    @Published var completedFaces: Set<UUID> = []

    // Consumed from DeepLinkStore if user came via Branch.io deferred deep link
    var invitationToken: String? {
        DeepLinkStore.shared.pendingInvitationToken
    }

    // MARK: - Dev Login

    func devLogin() async {
        guard devCode == "8888" else {
            errorMessage = "Invalid code."
            return
        }
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await APIClient.shared.devLogin(code: "8888")
            // Fresh user — always go to name
            step = .name
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auth Flow

    func sendOTP() async {
        guard !phone.isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        do {
            try await APIClient.shared.sendOTP(phone: normalizedPhone)
            step = .code
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func verifyOTP() async {
        guard !code.isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let token = invitationToken
            let response = try await APIClient.shared.verifyOTP(
                phone:           normalizedPhone,
                code:            code,
                displayName:     nil,
                invitationToken: token
            )
            if token != nil { DeepLinkStore.shared.pendingInvitationToken = nil }
            // New user → ask for name; returning user → done
            if response.user.displayName == "User" {
                step = .name
            } else {
                isComplete = true
            }
        } catch {
            errorMessage = "Incorrect code. Try again."
        }
    }

    func saveName() async {
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await APIClient.shared.updateMe(displayName: displayName.isEmpty ? nil : displayName)
            await PushNotificationService.shared.requestAuthorization()
            step = .photoPermission
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Photo Permission + Scanning

    func requestPhotosAndScan() {
        isScanning = true
        step = .faceBubbles

        Task {
            let stream = await PhotoLibraryScanner.shared.scanFacesProgressively()
            for await snapshot in stream {
                faceSuggestions = snapshot
            }
            isScanning = false

            // If no faces found, offer manual creation
            if faceSuggestions.isEmpty {
                // Stay on faceBubbles — the view shows "Choose photos manually" option
            }
        }
    }

    func skipPhotos() {
        UserDefaults.standard.set(true, forKey: "smartStartCompleted")
        isComplete = true
    }

    // MARK: - Chapter Creation (batch)

    func selectFace(at index: Int) {
        guard index < faceSuggestions.count else { return }
        step = .chapterCreation(faceSuggestions[index])
    }

    func manualCreate() {
        step = .chapterCreation(nil)
    }

    func chapterCompleted(faceID: UUID?) {
        if let id = faceID {
            completedFaces.insert(id)
        }
        // Return to bubbles for batch creation
        step = .faceBubbles
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "smartStartCompleted")
        isComplete = true
    }

    // MARK: - Private

    private var normalizedPhone: String {
        let digits = phone.filter { $0.isNumber }
        return digits.hasPrefix("1") ? "+\(digits)" : "+1\(digits)"
    }
}

// MARK: - View

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.mtBackground.ignoresSafeArea()

            Group {
                switch vm.step {
                case .welcome:
                    WelcomeView { vm.step = .phone }

                case .phone:
                    authShell { PhoneStep(vm: vm) }

                case .devCode:
                    authShell { DevCodeStep(vm: vm) }

                case .code:
                    authShell { CodeStep(vm: vm) }

                case .name:
                    authShell { NameStep(vm: vm) }

                case .photoPermission:
                    PhotoPermissionView(
                        onAllow: { vm.requestPhotosAndScan() },
                        onSkip: { vm.skipPhotos() }
                    )

                case .faceBubbles:
                    FaceBubblesView(
                        suggestions: $vm.faceSuggestions,
                        isScanning: vm.isScanning,
                        onSelectFace: { vm.selectFace(at: $0) },
                        onManualCreate: { vm.manualCreate() },
                        onSkip: { vm.finishOnboarding() },
                        completedFaces: vm.completedFaces
                    )

                case .chapterCreation(let suggestion):
                    ChapterCreationView(
                        suggestion: suggestion,
                        onComplete: { chapterID in
                            if chapterID != nil {
                                vm.chapterCompleted(faceID: suggestion?.id)
                            } else {
                                vm.step = .faceBubbles
                            }
                        },
                        onCreateAnother: {
                            vm.chapterCompleted(faceID: suggestion?.id)
                        }
                    )

                case .done:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.mtSlide, value: vm.step)
        }
        .preferredColorScheme(.light)
        .onChange(of: vm.isComplete) { _, complete in
            if complete { Task { await appState.loadCurrentUser() } }
        }
    }

    /// Wraps auth steps (phone/code/name) in the centered logo layout.
    @ViewBuilder
    private func authShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text("Memory Tunnel")
                    .font(.mtDisplay)
                    .foregroundStyle(Color.mtLabel)
                Text("For the people who matter most.")
                    .font(.mtBody)
                    .foregroundStyle(Color.mtSecondary)
            }
            .padding(.bottom, Spacing.xxl)

            content()

            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Phone Step

struct PhoneStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            TextField("+1 (555) 555-5555", text: $vm.phone)
                .keyboardType(.phonePad)
                .font(.mtBody)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }

            if let err = vm.errorMessage {
                Text(err).font(.mtCaption).foregroundStyle(Color.mtError)
            }

            PrimaryButton(title: "Continue", isLoading: vm.isLoading) {
                Task { await vm.sendOTP() }
            }

            #if DEBUG
            Button("Developer Login") {
                vm.step = .devCode
            }
            .font(.mtCaption)
            .foregroundStyle(Color.mtTertiary)
            #endif
        }
    }
}

// MARK: - Dev Code Step

struct DevCodeStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Enter developer code")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)

            TextField("0000", text: $vm.devCode)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }

            if let err = vm.errorMessage {
                Text(err).font(.mtCaption).foregroundStyle(Color.mtError)
            }

            PrimaryButton(title: "Dev Login", isLoading: vm.isLoading) {
                Task { await vm.devLogin() }
            }

            Button("Back") { vm.step = .phone }
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
        }
    }
}

// MARK: - Code Step

struct CodeStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Enter the 6-digit code\nsent to your phone.")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $vm.code)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }

            if let err = vm.errorMessage {
                Text(err).font(.mtCaption).foregroundStyle(Color.mtError)
            }

            PrimaryButton(title: "Verify", isLoading: vm.isLoading) {
                Task { await vm.verifyOTP() }
            }

            Button("Change number") { vm.step = .phone }
                .font(.mtCaption)
                .foregroundStyle(Color.mtSecondary)
        }
    }
}

// MARK: - Name Step

struct NameStep: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("What should friends call you?")
                .font(.mtBody)
                .foregroundStyle(Color.mtSecondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $vm.displayName)
                .font(.mtBody)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }

            PrimaryButton(title: "Get started", isLoading: vm.isLoading) {
                Task { await vm.saveName() }
            }
        }
    }
}

// MARK: - Shared button component

struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.mtButton)
                    .foregroundStyle(Color.mtBackground)
                    .opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(Color.mtBackground) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.mtLabel)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .disabled(isLoading)
    }
}
