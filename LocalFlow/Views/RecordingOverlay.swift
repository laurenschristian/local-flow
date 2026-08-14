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
            guard let self else { return }
            self.viewModel.status = .recording
            self.viewModel.isVisible = true
            self.viewModel.audioLevel = 0
            self.viewModel.partialText = ""
            self.viewModel.previousText = ""
            self.viewModel.micName = AudioDeviceManager.activeInputDeviceName()
            self.viewModel.recordingStart = Date()
            self.viewModel.peakLevel = 0
            self.viewModel.smoothedLevel = 0
            self.viewModel.showsSilenceHint = false
            self.viewModel.stopHint = Settings.shared.recordingMode == .toggle
                ? "Tap \(Settings.shared.triggerKey.displayName) to stop"
                : nil
            self.createAndShowWindow()
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
            guard let vm = self?.viewModel else { return }
            vm.audioLevel = CGFloat(level)
            vm.peakLevel = max(vm.peakLevel, CGFloat(level))
            // Fast attack, slow decay: keeps the waveform lively without jitter.
            let target = CGFloat(level)
            vm.smoothedLevel = target > vm.smoothedLevel
                ? vm.smoothedLevel * 0.4 + target * 0.6
                : vm.smoothedLevel * 0.85 + target * 0.15
            // Surface a dead mic while recording instead of failing silently after.
            let elapsed = Date().timeIntervalSince(vm.recordingStart)
            let silent = vm.status == .recording && elapsed > 2.5 && vm.peakLevel < 0.02
            if vm.showsSilenceHint != silent {
                vm.showsSilenceHint = silent
                self?.resizeWindowIfNeeded()
            }
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
    @Published var micName: String = ""
    @Published var showsSilenceHint: Bool = false
    @Published var stopHint: String?
    var recordingStart: Date = .distantPast
    var peakLevel: CGFloat = 0
    // Read every frame by the TimelineView canvas; not published on purpose.
    var smoothedLevel: CGFloat = 0

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
                    WaveformView(viewModel: viewModel)
                        .frame(width: 48, height: 32)
                } else {
                    PulsingDotsView()
                        .frame(width: 48, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.status == .recording ? "Listening..." : "Processing...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))

                    if !viewModel.micName.isEmpty {
                        Text(viewModel.micName)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                if viewModel.status == .recording, let hint = viewModel.stopHint {
                    Spacer(minLength: 12)
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            if viewModel.showsSilenceHint {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("No audio detected. Check your microphone.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
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

/// Frame-driven waveform: continuous motion from a per-frame canvas, amplitude
/// from the smoothed mic level. No SwiftUI animation churn, no jitter.
struct WaveformView: View {
    @ObservedObject var viewModel: RecordingOverlayViewModel
    private let barCount = 5
    private let barWidth: CGFloat = 4

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let level = min(1, viewModel.smoothedLevel * 1.6)
                let spacing = (size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)
                let center = CGFloat(barCount - 1) / 2

                for i in 0..<barCount {
                    let dist = abs(CGFloat(i) - center) / max(center, 1)
                    let weight = 1.0 - dist * 0.45
                    let wobble = 0.5 + 0.5 * sin(t * 7 + Double(i) * 1.15)
                    let height = 4 + (size.height - 4) * level * weight * (0.55 + 0.45 * wobble)
                    let rect = CGRect(
                        x: CGFloat(i) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(.white.opacity(0.95 - Double(dist) * 0.3))
                    )
                }
            }
        }
    }
}

/// Three softly pulsing dots for the transcribing state.
struct PulsingDotsView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = max(0, sin(t * 4 - Double(i) * 0.7))
                    Circle()
                        .fill(.white.opacity(0.4 + 0.5 * phase))
                        .frame(width: 6, height: 6)
                        .scaleEffect(1 + 0.3 * phase)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
