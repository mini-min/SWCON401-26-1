import AppKit
import SwiftUI

final class CalibrationOverlayWindow: NSPanel {
    private let viewModel = CalibrationOverlayViewModel()

    init(screen: NSScreen) {
        let size = CGSize(width: 340, height: 170)
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelKey.statusWindow.rawValue) + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        alphaValue = 0

        contentViewController = NSHostingController(rootView: CalibrationOverlayView(viewModel: viewModel))
    }

    func update(state: CalibrationState, message: String?) {
        viewModel.state = state
        viewModel.message = message

        if message == nil {
            orderOut(nil)
            alphaValue = 0
            return
        }

        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }
}

@MainActor
@Observable
final class CalibrationOverlayViewModel {
    var state: CalibrationState = .idle
    var message: String?
}

struct CalibrationOverlayView: View {
    let viewModel: CalibrationOverlayViewModel

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 8)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color(red: 0.42, green: 0.84, blue: 0.56),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.95), value: progress)

                Text(centerLabel)
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            Text(primaryMessage)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(secondaryMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(width: 340, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var progress: CGFloat {
        switch viewModel.state {
        case .capturing(let secondsRemaining):
            return CGFloat(max(0, min(3, 4 - secondsRemaining))) / 3
        case .completed:
            return 1
        case .idle:
            return 0
        }
    }

    private var centerLabel: String {
        switch viewModel.state {
        case .capturing(let secondsRemaining):
            return "\(secondsRemaining)"
        case .completed:
            return "✓"
        case .idle:
            return "•"
        }
    }

    private var primaryMessage: String {
        switch viewModel.state {
        case .capturing:
            return "올바른 자세를 유지해 주세요"
        case .completed:
            return "기준 자세를 저장했습니다"
        case .idle:
            return viewModel.message ?? ""
        }
    }

    private var secondaryMessage: String {
        switch viewModel.state {
        case .capturing:
            return "3초 동안 머리 위치를 유지하면 현재 자세를 기준값으로 사용합니다."
        case .completed:
            return "이제 이 자세를 기준으로 자세 이탈을 판단합니다."
        case .idle:
            return ""
        }
    }
}
