import SwiftUI

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step { case phone, code, name }

    @Published var step: Step = .phone
    @Published var phone: String = ""
    @Published var code: String = ""
    @Published var displayName: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isComplete = false

    // Set by Branch.io deferred deep link if user came via invitation
    var invitationToken: String?

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
            let response = try await APIClient.shared.verifyOTP(
                phone:           normalizedPhone,
                code:            code,
                displayName:     nil,
                invitationToken: invitationToken
            )
            // New user — ask for name; existing user — go straight in
            if response.user.displayName == "User" {
                step = .name
            }
            // AppState observes token change and transitions to ContentView
        } catch {
            errorMessage = "Incorrect code. Try again."
        }
    }

    func saveName() async {
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await APIClient.shared.updateMe(displayName: displayName.isEmpty ? nil : displayName)
            await PushNotificationService.shared.requestAuthorization()
            isComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var normalizedPhone: String {
        // Strip all non-digit characters, prepend + if missing
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

            VStack(spacing: 0) {
                Spacer()

                // Logo / wordmark
                VStack(spacing: Spacing.sm) {
                    Text("Memory Tunnel")
                        .font(.mtDisplay)
                        .foregroundStyle(Color.mtLabel)
                    Text("For the people who matter most.")
                        .font(.mtBody)
                        .foregroundStyle(Color.mtSecondary)
                }
                .padding(.bottom, Spacing.xxl)

                // Steps
                Group {
                    switch vm.step {
                    case .phone: PhoneStep(vm: vm)
                    case .code:  CodeStep(vm: vm)
                    case .name:  NameStep(vm: vm)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.mtSlide, value: vm.step)

                Spacer()
            }
            .padding(Spacing.xl)
        }
        .onChange(of: vm.isComplete) { _, complete in
            if complete { Task { await appState.loadCurrentUser() } }
        }
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
                Text(err).font(.mtCaption).foregroundStyle(.red)
            }

            PrimaryButton(title: "Continue", isLoading: vm.isLoading) {
                Task { await vm.sendOTP() }
            }
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
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(Spacing.md)
                .background(Color.mtSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .focused($focused)
                .onAppear { focused = true }

            if let err = vm.errorMessage {
                Text(err).font(.mtCaption).foregroundStyle(.red)
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
