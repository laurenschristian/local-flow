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

    private func createAndShowWindow() {
        if window != nil { return }

        let overlayView = RecordingOverlayView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 160, height: 52)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 52),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Use a container view to prevent constraint issues
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 52))
        containerView.wantsLayer = true
        containerView.addSubview(hostingView)
        window.contentView = containerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.ignoresMouseEvents = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.maxY - windowFrame.height - 60
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
}

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: RecordingOverlayViewModel

    private let brandColor = Color(red: 0, green: 0.094, blue: 0.278) // #001847

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if viewModel.status == .recording {
                    LiveWaveView(level: viewModel.audioLevel)
                        .frame(width: 28, height: 28)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(width: 28, height: 28)

            Text(viewModel.status == .recording ? "Listening" : "Processing")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(brandColor)
                .shadow(color: brandColor.opacity(0.5), radius: 16, x: 0, y: 8)
        )
        .opacity(viewModel.isVisible ? 1 : 0)
    }
}

struct LiveWaveView: View {
    let level: CGFloat
    private let barCount = 5

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveBar(height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 0.15
        let centerIndex = CGFloat(barCount - 1) / 2.0
        let distance = abs(CGFloat(index) - centerIndex)
        let centerWeight = 1.0 - (distance / centerIndex) * 0.4

        // Add some variation based on index
        let variation = sin(Double(index) * 1.5 + level * 10) * 0.15

        let height = baseHeight + (level * centerWeight * 0.85) + variation
        return max(0.1, min(1.0, height))
    }
}

struct WaveBar: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .frame(width: 3, height: 4 + 18 * height)
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
            vm.audioLevel = 0.5
            return vm
        }())
    }
    .frame(width: 300, height: 150)
}
