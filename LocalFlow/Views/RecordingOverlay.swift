import SwiftUI
import AppKit

class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    // Fixed transparent canvas: SwiftUI animates the pill inside it, so the window
    // never resizes (resizing per text update made the old overlay jitter).
    private static let canvasSize = NSSize(width: 520, height: 200)
    private static let topInset: CGFloat = 36

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?
    private let viewModel = RecordingOverlayViewModel()

    private init() {}

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideWork?.cancel()
            let vm = self.viewModel
            vm.status = .recording
            vm.audioLevel = 0
            vm.partialText = ""
            vm.micName = AudioDeviceManager.activeInputDeviceName()
            vm.recordingStart = Date()
            vm.peakLevel = 0
            vm.smoothedLevel = 0
            vm.showsSilenceHint = false
            vm.stopHint = Settings.shared.recordingMode == .toggle
                ? "Tap \(Settings.shared.triggerKey.displayName) to stop"
                : nil
            self.createWindowIfNeeded()
            self.positionWindow()
            self.window?.orderFrontRegardless()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                vm.isVisible = true
            }
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                self.viewModel.isVisible = false
            }
            self.viewModel.audioLevel = 0
            let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    func updateStatus(_ status: RecordingStatus) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                self?.viewModel.status = status
            }
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    vm.showsSilenceHint = silent
                }
            }
        }
    }

    func updatePartialText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                self?.viewModel.partialText = text
            }
        }
    }

    private func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = Self.canvasSize
        window.setFrame(NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - Self.topInset + 24,
            width: size.width,
            height: size.height
        ), display: false)
    }

    private func createWindowIfNeeded() {
        guard window == nil else { return }
        let hostingView = NSHostingView(rootView: RecordingOverlayView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hasShadow = false
        // The canvas is mostly transparent; it must never swallow clicks.
        window.ignoresMouseEvents = true
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
    @Published var micName: String = ""
    @Published var showsSilenceHint: Bool = false
    @Published var stopHint: String?
    var recordingStart: Date = .distantPast
    var peakLevel: CGFloat = 0
    // Read every frame by the TimelineView canvas; not published on purpose.
    var smoothedLevel: CGFloat = 0
}

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: RecordingOverlayViewModel

    /// Last ~90 characters, cut at a word boundary.
    private var displayText: String {
        let full = viewModel.partialText
        guard full.count > 90 else { return full }
        let tail = full.suffix(90)
        let words = tail.split(separator: " ").dropFirst()
        return "\u{2026}" + words.joined(separator: " ")
    }

    private var hasText: Bool { !viewModel.partialText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            pill
                .scaleEffect(viewModel.isVisible ? 1 : 0.9, anchor: .top)
                .offset(y: viewModel.isVisible ? 0 : -10)
                .opacity(viewModel.isVisible ? 1 : 0)
                .blur(radius: viewModel.isVisible ? 0 : 4)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pill: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    if viewModel.status == .recording {
                        WaveformView(viewModel: viewModel)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        PulsingDotsView()
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .frame(width: 26, height: 16)

                Text(viewModel.status == .recording ? "Listening" : "Transcribing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.opacity)

                if viewModel.status == .recording {
                    ElapsedTimeView(start: viewModel.recordingStart)
                        .transition(.opacity)
                }

                if viewModel.status == .recording, let hint = viewModel.stopHint {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                        .padding(.leading, 4)
                        .transition(.opacity)
                }
            }

            if viewModel.showsSilenceHint {
                Label("No audio. Check your microphone.", systemImage: "mic.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if hasText {
                Text(displayText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400, alignment: .leading)
                    .contentTransition(.opacity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: hasText || viewModel.showsSilenceHint ? 16 : 22, style: .continuous)
                .fill(Color(red: 0.08, green: 0.085, blue: 0.1).opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: hasText || viewModel.showsSilenceHint ? 16 : 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .fixedSize(horizontal: !hasText, vertical: true)
    }
}

/// mm:ss since the recording started, ticking once a second.
struct ElapsedTimeView: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(start)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
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
            vm.recordingStart = Date()
            return vm
        }())
    }
    .frame(width: 500, height: 200)
}
