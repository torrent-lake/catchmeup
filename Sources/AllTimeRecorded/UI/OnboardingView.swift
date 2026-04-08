import AVFoundation
import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var micGranted = false
    @State private var pulse = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            GlassMaterialView()
            Color.black.opacity(0.1)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.black.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)

            VStack(spacing: 0) {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    permissionsStep
                default:
                    readyStep
                }

                Spacer().frame(height: 16)
                stepIndicator
            }
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.34), Theme.neonCyan.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.white.opacity(0.05), radius: 14, x: 0, y: 5)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(width: 420, height: 340)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Circle()
                .fill(Theme.neonCyan.opacity(pulse ? 0.7 : 0.35))
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .stroke(Theme.neonCyan.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 58, height: 58)
                )

            Text("AllTimeRecorded")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

            Text("Continuous recording. Local transcription.\nYour audio timeline, always available.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()

            actionButton("Get Started") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = 1
                }
            }
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Permissions")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Record ambient audio when your Mac lid is open",
                    granted: micGranted
                ) {
                    requestMicrophone()
                }

                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Capture",
                    subtitle: "Capture system audio output",
                    granted: false,
                    isOptional: true
                ) {}
            }

            Spacer()

            actionButton("Continue") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = 2
                }
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        isOptional: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(granted ? Theme.neonCyan : .white.opacity(0.5))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    if isOptional {
                        Text("optional")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.neonCyan)
                    .font(.system(size: 16))
            } else if !isOptional {
                Button("Grant") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.neonCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.neonCyan.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Theme.neonCyan.opacity(0.3), lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.neonCyan)

            Text("All Set")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

            Text("Recording starts automatically.\nAccess your timeline from the menu bar.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            miniTimeline

            Spacer()

            actionButton("Start Recording") {
                onComplete()
            }
        }
    }

    private var miniTimeline: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(i < 14
                        ? Theme.neonCyan.opacity(Double.random(in: 0.2...0.8))
                        : Color.white.opacity(0.1)
                    )
                    .frame(width: 4, height: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.12), in: Capsule())
    }

    // MARK: - Shared

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: 200)
                .padding(.vertical, 9)
                .background(Theme.neonCyan.opacity(0.25), in: Capsule())
                .overlay(Capsule().stroke(Theme.neonCyan.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == currentStep
                        ? Theme.neonCyan.opacity(0.8)
                        : Color.white.opacity(0.2)
                    )
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: - Actions

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micGranted = granted
            }
        }
    }
}
