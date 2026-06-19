import SwiftUI

struct SettingsView: View {
    @Environment(HeadTrackingEngine.self) private var tracking
    @Environment(SpatialAudioEngine.self) private var audio

    var body: some View {
        TabView {
            StatusTab()
                .tabItem { Label("상태", systemImage: "sensor.tag.radiowaves.forward") }
            AudioTab()
                .tabItem { Label("오디오", systemImage: "waveform") }
        }
        .frame(width: 460, height: 340)
        .environment(tracking)
        .environment(audio)
    }
}

// MARK: - Status Tab

struct StatusTab: View {
    @Environment(HeadTrackingEngine.self) private var tracking

    var body: some View {
        Form {
            Section("연결") {
                LabeledContent("AirPods") {
                    Text(tracking.isConnected ? "연결됨" : "미연결")
                        .foregroundStyle(tracking.isConnected ? .green : .secondary)
                }
                LabeledContent("트래킹 상태") {
                    Text(tracking.trackingStatus.title)
                        .foregroundStyle(statusColor)
                        .fontWeight(.semibold)
                }
                Text(tracking.trackingStatus.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let calibrationMessage = tracking.calibrationMessage {
                    Text(calibrationMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if case .capturing(let secondsRemaining) = tracking.calibrationState {
                        Text("\(secondsRemaining)초 동안 정자세를 유지하면 그 값을 기준 자세로 저장합니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(calibrationButtonTitle) { tracking.calibrate() }
                    .disabled(!canCalibrate || tracking.calibrationState.isRunning)
            }

            Section("Sound Box 피드백") {
                LabeledContent("자세") {
                    Text(tracking.postureState.label)
                        .foregroundStyle(stateColor)
                        .fontWeight(.semibold)
                }
                LabeledContent("소리 피드백") {
                    Text(tracking.postureState.soundDescription)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                LabeledContent("이탈 강도") {
                    ProgressView(value: tracking.orientation.severity)
                        .frame(width: 120)
                        .tint(stateColor)
                }
            }

            Section("실시간 센서 (°)") {
                LabeledContent("피치 – 앞뒤 기울기") {
                    Text("\(Int(tracking.orientation.pitch))°").monospacedDigit()
                }
                LabeledContent("요 – 좌우 회전") {
                    Text("\(Int(tracking.orientation.yaw))°").monospacedDigit()
                }
                LabeledContent("롤 – 좌우 기울기") {
                    Text("\(Int(tracking.orientation.roll))°").monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var stateColor: Color {
        let color = tracking.postureState.color
        return Color(red: color.r, green: color.g, blue: color.b)
    }

    private var statusColor: Color {
        switch tracking.trackingStatus {
        case .active:
            return .green
        case .searching, .simulating:
            return .yellow
        case .idle, .disconnected, .unauthorized, .unavailable, .failed:
            return .secondary
        }
    }

    private var canCalibrate: Bool {
        tracking.trackingStatus == .active || tracking.trackingStatus == .simulating
    }

    private var calibrationButtonTitle: String {
        if case .capturing(let secondsRemaining) = tracking.calibrationState {
            return "자세 기록 중 \(secondsRemaining)초"
        }
        return "3초 자세 보정 시작"
    }
}

// MARK: - Audio Tab

struct AudioTab: View {
    @Environment(SpatialAudioEngine.self) private var audio
    @AppStorage("glowEnabled") private var glowOn = true

    var body: some View {
        @Bindable var audio = audio
        return Form {
            Section("배경음") {
                Toggle("집중용 배경음 켜기", isOn: $audio.isAmbienceEnabled)

                Text(audio.isAmbienceEnabled ? "khuLibrary.mp3가 재생되며 자세가 무너지면 소리가 멀어지고 왜곡됩니다." : "배경음이 꺼져 있습니다.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }

            Section("피드백 사운드") {
                Toggle("경고 피드백 켜기", isOn: $audio.isFeedbackEnabled)

                Picker("효과음", selection: $audio.selectedFeedbackSound) {
                    ForEach(FeedbackSoundOption.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!audio.isFeedbackEnabled)

                Text("현재 선택: \(audio.selectedFeedbackSound.title)")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }

            Section("Sound Box 안내") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "ear.and.waveform")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("자세 피드백 방향")
                            .font(.system(size: 12, weight: .semibold))
                        Text("배경음은 올바른 머리 위치에서 가장 자연스럽고 가깝게 들립니다.\n자세가 나빠지면 배경음이 왜곡되고, 나쁜 자세에서는 선택한 경고음이 해당 방향에서 들립니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("화면 피드백") {
                Toggle("화면 안내 오버레이 표시", isOn: $glowOn)

                Text(glowOn ? "화면 전체의 원형 가이드가 머리 치우침 방향을 보여줍니다." : "화면 안내 오버레이가 꺼져 있습니다.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

}
