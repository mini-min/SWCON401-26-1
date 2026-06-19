import SwiftUI

@main
struct SoundBoxCompanionApp: App {
    @State private var peerManager = CompanionPeerManager()

    var body: some Scene {
        WindowGroup {
            CompanionContentView()
                .environment(peerManager)
                .onAppear { peerManager.start() }
        }
    }
}

struct CompanionContentView: View {
    @Environment(CompanionPeerManager.self) private var peer

    var body: some View {
        VStack(spacing: 0) {
            connectionHeader

            Spacer()

            SpatialRadarView(state: peer.currentState)
                .padding(.horizontal, 32)

            Spacer()

            sensorFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var connectionHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(peer.isConnected ? Color.green : Color.red.opacity(0.7))
                .frame(width: 8, height: 8)

            Text(peer.isConnected
                 ? "\(peer.connectedMacName ?? "Mac")에 연결됨"
                 : "Sound Box 검색 중...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var sensorFooter: some View {
        VStack(spacing: 12) {
            Text("공간음향")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 24) {
                sensorValue("Pitch", value: peer.currentState.pitch)
                sensorValue("Yaw", value: peer.currentState.yaw)
                sensorValue("Roll", value: peer.currentState.roll)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(postureColor)
                    .frame(width: 8, height: 8)
                Text(postureLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(postureColor)
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func sensorValue(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(Int(value.rounded()))°")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var postureColor: Color {
        switch peer.currentState.postureState {
        case "warning": return Color(red: 0.99, green: 0.80, blue: 0.18)
        case "poor": return Color(red: 1.00, green: 0.22, blue: 0.18)
        default: return Color(red: 0.16, green: 0.82, blue: 0.30)
        }
    }

    private var postureLabel: String {
        switch peer.currentState.postureState {
        case "warning": return "주의"
        case "poor": return "자세 교정 필요"
        default: return "정자세"
        }
    }
}
