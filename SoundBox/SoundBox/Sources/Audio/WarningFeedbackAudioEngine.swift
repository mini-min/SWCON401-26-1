@preconcurrency import AVFAudio
import Foundation

@MainActor
final class WarningFeedbackAudioEngine {
    private let baseVolume: Float = 1.65
    private let sustainedPoorPostureDelay: TimeInterval = 3.0

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()

    private var buffers: [FeedbackSoundOption: AVAudioPCMBuffer] = [:]
    private var bufferFormat: AVAudioFormat?
    private var lastFeedbackAt: Date = .distantPast
    private var poorPostureBeganAt: Date?
    private let feedbackCooldown: TimeInterval = 1.2

    private(set) var isReady = false

    /// 경고음 엔진을 초기화합니다.
    /// 모든 FeedbackSoundOption의 MP3를 모노 버퍼로 미리 로드하고 오디오 그래프를 구성한 뒤 엔진을 시작합니다.
    /// 이미 초기화된 경우(isReady == true) 아무 동작도 하지 않습니다.
    func setup() {
        guard !isReady else { return }

        do {
            let knockBuffer = try loadMonoBuffer(resourceName: FeedbackSoundOption.knockMono.resourceName)
            let coughBuffer = try loadMonoBuffer(resourceName: FeedbackSoundOption.coughManMono.resourceName)

            buffers[.knockMono] = knockBuffer
            buffers[.coughManMono] = coughBuffer
            bufferFormat = knockBuffer.format

            configureGraph(with: knockBuffer.format)
            try engine.start()
            isReady = true
        } catch {
            isReady = false
            print("Warning feedback setup failed: \(error.localizedDescription)")
        }
    }

    /// 매 프레임 자세 상태를 평가하고, 조건이 충족되면 경고음을 재생합니다.
    /// 자세 상태가 .poor일 때 sustainedPoorPostureDelay(3초) 이상 지속되고,
    /// feedbackCooldown(1.2초) 이후라면 선택된 경고음을 현재 자세 방향에서 재생합니다.
    /// - Parameters:
    ///   - orientation: 현재 머리 자세 (pitch/yaw/roll 및 postureState)
    ///   - selectedSound: 사용자가 선택한 경고음 종류
    ///   - strength: 공간 효과 강도 배율
    func update(orientation: HeadOrientation, selectedSound: FeedbackSoundOption, strength: Double) {
        guard isReady else { return }

        // 매 프레임 3D 음원 위치를 현재 자세에 맞게 갱신
        player.position = warningPosition(for: orientation, strength: strength)

        // .poor가 아니면 타이머 리셋 후 종료
        guard orientation.postureState == .poor else {
            poorPostureBeganAt = nil
            return
        }

        // .poor 진입 시점을 기록
        if poorPostureBeganAt == nil {
            poorPostureBeganAt = Date()
        }

        guard let poorPostureBeganAt else { return }
        guard Date().timeIntervalSince(poorPostureBeganAt) >= sustainedPoorPostureDelay else { return }
        guard Date().timeIntervalSince(lastFeedbackAt) >= feedbackCooldown else { return }

        play(option: selectedSound)
        lastFeedbackAt = Date()
    }

    /// 경고음 재생을 중지하고 자세 불량 타이머를 초기화합니다.
    /// 트래킹 중단 또는 피드백 비활성화 시 호출됩니다.
    func stopIfNeeded() {
        poorPostureBeganAt = nil
        guard player.isPlaying else { return }
        player.stop()
    }

    /// 오디오 엔진이 멈춰 있을 때만 재시작합니다.
    /// AirPods 연결/해제 등 오디오 장치 변경으로 엔진이 중단된 경우 복구하기 위해 호출됩니다.
    func restartEngineIfNeeded() {
        guard isReady, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Warning engine restart failed: \(error.localizedDescription)")
        }
    }

    /// AVAudioEngine 노드 그래프를 구성합니다.
    /// player → AVAudioEnvironmentNode(HRTF 공간음향) → mainMixerNode 순으로 연결하고
    /// 거리 감쇠, 잔향, 청취자 위치·방향 등 초기 파라미터를 설정합니다.
    private func configureGraph(with format: AVAudioFormat) {
        engine.attach(player)
        engine.attach(environment)

        engine.connect(player, to: environment, format: format)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        environment.renderingAlgorithm = .HRTFHQ
        environment.distanceAttenuationParameters.referenceDistance = 0.25
        environment.distanceAttenuationParameters.maximumDistance = 18.0
        environment.distanceAttenuationParameters.rolloffFactor = 0.9
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = -8
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )

        player.renderingAlgorithm = .HRTFHQ
        player.reverbBlend = 0.28
        player.volume = baseVolume
    }

    /// 미리 로드된 버퍼에서 지정된 경고음을 즉시 재생합니다.
    /// 이전 재생을 중단하고 새 버퍼를 스케줄링합니다.
    private func play(option: FeedbackSoundOption) {
        guard let buffer = buffers[option] else { return }

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
    }

    /// 현재 자세의 pitch/yaw/roll을 기반으로 경고음이 재생될 3D 위치를 계산합니다.
    /// 자세 이탈 방향에서 소리가 들리도록 x(좌우), y(상하), z(앞뒤) 좌표를 반환합니다.
    private func warningPosition(for orientation: HeadOrientation, strength: Double) -> AVAudio3DPoint {
        // pitch 음수 방향이 앞으로 숙임이므로 부호 반전 후 정규화
        let pitchNorm = clamp(-orientation.pitch / 45.0, -1.0, 1.0)
        let yawNorm = clamp(orientation.yaw / 60.0, -1.0, 1.0)
        let rollNorm = clamp(orientation.roll / 30.0, -1.0, 1.0)

        // severity 최솟값을 0.55로 보장해 경고음이 항상 충분한 거리감을 갖도록 함
        let severity = max(0.55, orientation.severity) * max(0.9, strength)

        return AVAudio3DPoint(
            x: Float((yawNorm * 2.4 + rollNorm * 1.2) * severity),
            y: Float((-rollNorm * 0.22) * severity),
            z: Float((-0.45 - pitchNorm * 1.15) * severity)
        )
    }

    /// 번들에서 지정된 MP3 파일을 읽어 모노 Float32 PCM 버퍼로 변환해 반환합니다.
    /// AVAudioEnvironmentNode는 모노 포맷 입력을 필요로 하므로, 스테레오 소스는 AVAudioConverter로 다운믹스합니다.
    /// - Parameter resourceName: 번들 내 MP3 파일 이름 (확장자 제외)
    private func loadMonoBuffer(resourceName: String) throws -> AVAudioPCMBuffer {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            throw NSError(domain: "SoundBox.Audio", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "\(resourceName).mp3를 번들에서 찾을 수 없습니다."
            ])
        }

        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let sourceFrameCount = AVAudioFrameCount(file.length)

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: sourceFrameCount
        ) else {
            throw NSError(domain: "SoundBox.Audio", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "경고음 원본 버퍼를 만들 수 없습니다."
            ])
        }
        try file.read(into: sourceBuffer)

        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        if sourceFormat.channelCount == 1, sourceFormat.commonFormat == .pcmFormatFloat32 {
            return sourceBuffer
        }

        let converter = AVAudioConverter(from: sourceFormat, to: monoFormat)!
        let outputCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) + 1024)
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "SoundBox.Audio", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "경고음 모노 버퍼를 만들 수 없습니다."
            ])
        }

        var provided = false
        var conversionError: NSError?
        let status = converter.convert(to: monoBuffer, error: &conversionError) { _, outStatus in
            if provided {
                outStatus.pointee = .endOfStream
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            throw NSError(domain: "SoundBox.Audio", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "경고음 모노 변환에 실패했습니다."
            ])
        }

        return monoBuffer
    }

    /// 값을 [lower, upper] 범위로 제한합니다.
    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
