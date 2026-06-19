import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(HeadTrackingEngine.self) private var tracking
    @Environment(SpatialAudioEngine.self) private var audio
    @AppStorage("glowEnabled") private var isEdgeGlowEnabled = true

    let onSetEdgeGlowEnabled: (Bool) -> Void
    let onCalibrate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            trackingPanel
            feedbackPanel
        }
        .padding(10)
        .frame(width: 410, height: 248)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.18, blue: 0.16),
                    Color(red: 0.15, green: 0.14, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("헤드 트래킹")

            statusRow("활성", value: tracking.isConnected ? "켜짐" : "꺼짐", accent: tracking.isConnected ? .green : .secondary)
            statusRow("자세", value: tracking.postureState.label, accent: postureColor)
            statusRow("이탈 강도", value: "\(Int(tracking.orientation.severity * 100))%", accent: statusColor)

            Divider().overlay(Color.white.opacity(0.10))

            VStack(alignment: .leading, spacing: 4) {
                Text("센서값")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text("P \(Int(sensorOrientation.pitch))°  Y \(Int(sensorOrientation.yaw))°  R \(Int(sensorOrientation.roll))°")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            Button("현재 자세 보정", action: onCalibrate)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(red: 0.39, green: 0.69, blue: 0.57))
                .disabled(tracking.calibrationState.isRunning || !canCalibrate)
        }
        .panelCard()
    }

    private var feedbackPanel: some View {
        FeedbackPanelView(audio: audio, edgeGlowBinding: edgeGlowEnabledBinding)
    }

    private func panelTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
    }

    private func statusRow(_ title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var sensorOrientation: HeadOrientation {
        (tracking.trackingStatus == .active || tracking.trackingStatus == .simulating)
            ? tracking.orientation
            : .neutral
    }

    private var postureColor: Color {
        let color = tracking.postureState.color
        return Color(red: color.r, green: color.g, blue: color.b)
    }

    private var canCalibrate: Bool {
        tracking.trackingStatus == .active || tracking.trackingStatus == .simulating
    }

    private var statusColor: Color {
        switch tracking.trackingStatus {
        case .active:
            return Color(red: 0.50, green: 0.85, blue: 0.60)
        case .searching, .simulating:
            return Color(red: 0.95, green: 0.78, blue: 0.34)
        case .idle, .disconnected, .unauthorized, .unavailable, .failed:
            return Color.white.opacity(0.90)
        }
    }

    private var edgeGlowEnabledBinding: Binding<Bool> {
        Binding(
            get: { isEdgeGlowEnabled },
            set: { newValue in
                onSetEdgeGlowEnabled(newValue)
                isEdgeGlowEnabled = newValue
            }
        )
    }
}

private struct FeedbackPanelView: View {
    @Bindable var audio: SpatialAudioEngine
    let edgeGlowBinding: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("피드백")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            toggleRow(title: "집중 배경음 (Beta)", shortcut: "⌘⌥B", isOn: $audio.isAmbienceEnabled)
            toggleRow(title: "자세 알림음 (Beta)", shortcut: "⌘⌥F", isOn: $audio.isFeedbackEnabled)

            HStack(alignment: .center, spacing: 10) {
                Text("알림음 종류")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 64, alignment: .leading)

                Picker("", selection: $audio.selectedFeedbackSound) {
                    ForEach(FeedbackSoundOption.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!audio.isFeedbackEnabled)
            }

            Divider().overlay(Color.white.opacity(0.10))

            toggleRow(title: "화면 안내", shortcut: "⌘⌥V", isOn: edgeGlowBinding)

            Divider().overlay(Color.white.opacity(0.10))

            HStack(alignment: .center, spacing: 10) {
                Text("공간음향 녹음")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(width: 64, alignment: .leading)

                Spacer(minLength: 0)

                if audio.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)

                    Text("녹음 중")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button(audio.isRecording ? "중지" : "녹음") {
                    audio.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(audio.isRecording ? .red : Color(red: 0.39, green: 0.69, blue: 0.57))
                .disabled(!audio.isAmbienceEnabled)
            }

            Spacer(minLength: 0)
        }
        .panelCard()
    }

    private func toggleRow(title: String, shortcut: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            Text(shortcut)
                .font(.system(size: 9, weight: .medium).monospaced())
                .foregroundStyle(.white.opacity(0.50))

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private extension View {
    func panelCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
