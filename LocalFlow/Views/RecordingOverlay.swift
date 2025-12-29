import SwiftUI
import AppKit

class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    private var viewModel = RecordingOverlayViewModel()

    private init() {}

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.status = .recording
            self?.viewModel.isVisible = true
            self?.viewModel.audioLevel = 0
            self?.viewModel.partialText = ""
            self?.viewModel.previousText = ""
            self?.createAndShowWindow()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.isVisible = false
            self?.viewModel.audioLevel = 0

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.window?.orderOut(nil)
                self?.window = nil
                self?.hostingView = nil
            }
        }
    }

    func updateStatus(_ status: RecordingStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.status = status
        }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.audioLevel = CGFloat(level)
        }
    }

    func updatePartialText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.updateText(text)
            self?.resizeWindowIfNeeded()
        }
    }

    private func resizeWindowIfNeeded() {
        guard let window = window, let hostingView = hostingView else { return }
        let size = hostingView.fittingSize
        let newWidth = max(360, min(420, size.width))
        let newHeight = max(100, min(180, size.height))

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - newWidth / 2
            let y = screenFrame.maxY - newHeight - 60

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(NSRect(x: x, y: y, width: newWidth, height: newHeight), display: true)
            }
            hostingView.frame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
        }
    }

    private func createAndShowWindow() {
        if window != nil { return }

        let overlayView = RecordingOverlayView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: overlayView)

        // Start with a good default size
        let initialWidth: CGFloat = 360
        let initialHeight: CGFloat = 100
        hostingView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.ignoresMouseEvents = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - initialWidth / 2
            let y = screenFrame.maxY - initialHeight - 60
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
    }
}

enum RecordingStatus {
    case recording
    case transcribing
}

class RecordingOverlayViewModel: ObservableObject {
    @Published var status: RecordingStatus = .recording
    @Published var isVisible: Bool = false
    @Published var audioLevel: CGFloat = 0
    @Published var partialText: String = ""
    @Published var previousText: String = ""

    func updateText(_ newText: String) {
        previousText = partialText
        partialText = newText
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: RecordingOverlayViewModel
    @State private var textId = UUID()

    /// Get the last ~80 characters to show, keeping whole words
    private var displayText: (faded: String, bright: String) {
        let full = viewModel.partialText
        guard !full.isEmpty else { return ("", "") }

        let maxChars = 80
        if full.count <= maxChars {
            // Show all, highlight last ~20 chars
            let brightStart = max(0, full.count - 25)
            let faded = String(full.prefix(brightStart))
            let bright = String(full.suffix(full.count - brightStart))
            return (faded, bright)
        }

        // Trim to last maxChars, break at word boundary
        let trimmed = String(full.suffix(maxChars))
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: false)
        let display = words.dropFirst().joined(separator: " ")

        // Highlight last ~25 chars
        let brightStart = max(0, display.count - 25)
        let faded = String(display.prefix(brightStart))
        let bright = String(display.suffix(display.count - brightStart))
        return ("..." + faded, bright)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Status indicator with improved waveform
            HStack(spacing: 14) {
                if viewModel.status == .recording {
                    ImprovedWaveView(level: viewModel.audioLevel)
                        .frame(width: 48, height: 32)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                        .frame(width: 48, height: 32)
                }

                Text(viewModel.status == .recording ? "Listening..." : "Processing...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            // Live transcription - shows latest text, scrolls away old
            if !viewModel.partialText.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    (Text(displayText.faded)
                        .foregroundColor(.white.opacity(0.5))
                    + Text(displayText.bright)
                        .foregroundColor(.white)
                        .bold()
                    )
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: .white.opacity(0.25), radius: 6)
                    .id(textId)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .onChange(of: viewModel.partialText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        textId = UUID()
                    }
                }
            } else {
                Text(" ")
                    .font(.system(size: 16))
                    .frame(minHeight: 40)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(minWidth: 360, maxWidth: 440)
        .background {
            GlassBackground()
        }
        .opacity(viewModel.isVisible ? 1 : 0)
    }
}

struct GlassBackground: View {
    var body: some View {
        ZStack {
            // Base blur layer
            RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // Tinted overlay - more see-through
            RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                .fill(AppStyle.Colors.brand.opacity(0.55))

            // Glass edge highlight
            RoundedRectangle(cornerRadius: AppStyle.Layout.cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.2),
                            .clear,
                            .white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: AppStyle.Colors.brand.opacity(0.3), radius: 30, x: 0, y: 15)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

/// Improved waveform visualization with gradient and smooth animation
struct ImprovedWaveView: View {
    let level: CGFloat
    private let barCount = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                ImprovedWaveBar(
                    height: barHeight(for: index),
                    index: index,
                    totalBars: barCount
                )
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 0.12
        let centerIndex = CGFloat(barCount - 1) / 2.0
        let distance = abs(CGFloat(index) - centerIndex)
        let centerWeight = 1.0 - (distance / centerIndex) * 0.5

        // Create wave-like variation
        let phase = Double(index) * 0.8 + Double(level) * 12
        let variation = sin(phase) * 0.2

        let height = baseHeight + (level * centerWeight * 0.9) + variation
        return max(0.08, min(1.0, height))
    }
}

struct ImprovedWaveBar: View {
    let height: CGFloat
    let index: Int
    let totalBars: Int

    private var barGradient: LinearGradient {
        let centerIndex = CGFloat(totalBars - 1) / 2.0
        let distance = abs(CGFloat(index) - centerIndex) / centerIndex
        let opacity = 1.0 - (distance * 0.4)

        return LinearGradient(
            colors: [
                .white.opacity(opacity),
                .white.opacity(opacity * 0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(barGradient)
            .frame(width: 4, height: 6 + 22 * height)
            .shadow(color: .white.opacity(0.3), radius: 2)
            .animation(.easeOut(duration: 0.08), value: height)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        RecordingOverlayView(viewModel: {
            let vm = RecordingOverlayViewModel()
            vm.isVisible = true
            vm.status = .recording
            vm.audioLevel = 0.6
            vm.partialText = "This is a test of the live transcription feature showing how text appears"
            return vm
        }())
    }
    .frame(width: 500, height: 200)
}
