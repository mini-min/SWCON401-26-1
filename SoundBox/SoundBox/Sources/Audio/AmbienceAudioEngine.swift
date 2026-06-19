@preconcurrency import AVFAudio
import Foundation
import simd

@MainActor
final class AmbienceAudioEngine {
    private let baseVolume: Float = 0.42

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)

    private var ambienceBuffer: AVAudioPCMBuffer?
    private var monoFormat: AVAudioFormat?
    var mainMixer: AVAudioMixerNode { engine.mainMixerNode }
    var outputFormat: AVAudioFormat { engine.mainMixerNode.outputFormat(forBus: 0) }
    private(set) var isReady = false
    private(set) var isPlaying = false

    /// 배경음 엔진을 초기화합니다.
    /// khuLibrary.mp3를 모노 버퍼로 로드하고, 오디오 노드 그래프를 구성한 뒤 엔진을 시작합니다.
    /// 이미 초기화된 경우(isReady == true) 아무 동작도 하지 않습니다.
    func setup() {
        guard !isReady else { return }

        do {
            let buffer = try loadMonoBuffer(resourceName: "khuLibrary")
            ambienceBuffer = buffer
            monoFormat = buffer.format

            configureGraph(with: buffer.format)
            try engine.start()
            isReady = true
        } catch {
            isReady = false
            print("Ambience setup failed: \(error.localizedDescription)")
        }
    }

    /// 배경음 재생을 켜거나 끕니다.
    /// - Parameter enabled: true이면 엔진 재시작 후 루프 재생을 시작하고, false이면 재생을 멈춥니다.
    func setEnabled(_ enabled: Bool) {
        guard isReady else { return }
        if enabled {
            restartEngineIfNeeded()
            startLoopIfNeeded()
        } else {
            stop()
        }
    }

    /// 오디오 엔진이 멈춰 있을 때만 재시작합니다.
    /// AirPods 연결/해제 등 오디오 장치 변경으로 엔진이 중단된 경우 복구하기 위해 호출됩니다.
    func restartEngineIfNeeded() {
        guard isReady, !engine.isRunning else { return }
        isPlaying = false
        do {
            try engine.start()
        } catch {
            print("Ambience engine restart failed: \(error.localizedDescription)")
        }
    }

    /// 현재 머리 자세를 기반으로 공간 음향 파라미터를 실시간 업데이트합니다.
    /// compositeScore(종합 자세 불량도)를 정규화한 deviation 값으로 음원 위치·폐색·잔향·음량·EQ를 조절합니다.
    /// - Parameters:
    ///   - orientation: 현재 머리 자세 (pitch/yaw/roll)
    ///   - strength: 공간 효과 강도 배율 (0~1, 설정에서 조절)
    func update(orientation: HeadOrientation, strength: Double) {
        guard isReady, isPlaying else { return }

        // severity 기반 이탈량: 정상(<15°)=0, 주의(15~30°)=0~0.5, 위험(30°+)=0.5~1.0
        // compositeScore/45 대신 severity를 사용해 정상 자세에서는 효과가 전혀 없도록 함
        let deviation = orientation.severity

        // 방향 정보: 공간 음향 3D 위치 계산용 (개별 축 유지)
        // pitch 음수 방향이 앞으로 숙임이므로 부호 반전 후 정규화
        let pitchNorm = clamp(max(0, -orientation.pitch) / 45.0, 0.0, 1.0)
        let rollNorm  = clamp(orientation.roll / 30.0, -1.0, 1.0)
        let yawNorm   = clamp(orientation.yaw  / 45.0, -1.0, 1.0)

        // 3D 음원 위치
        // pitch → z축: 숙일수록 소리가 뒤로 멀어짐
        // yaw/roll → x축: 좌우 비대칭 자세 시 소리가 치우침
        let x = Float((-yawNorm - rollNorm * 0.4) * strength)
        let y = Float(0)
        let z = Float((-0.25 + pitchNorm * 2.5) * strength)

        player.position = AVAudio3DPoint(x: x, y: y, z: z)
        // deviation이 클수록 소리가 막히는 느낌(occlusion), 잔향 증가, 음량 감소, 고음역 차단
        player.occlusion = Float(-deviation * 65.0 * strength)
        player.reverbBlend = Float(deviation * 0.7 * strength)
        player.volume = max(0.14, baseVolume - Float(deviation * 0.20 * strength))

        eq.bands[0].frequency = 20_000 - Float(deviation * strength) * (20_000 - 900)
        environment.reverbParameters.level = Float(-18 + deviation * 22 * strength)
    }

    /// AVAudioEngine 노드 그래프를 구성합니다.
    /// player → EQ(저역통과 필터) → AVAudioEnvironmentNode(HRTF 공간음향) → mainMixerNode 순으로 연결하고
    /// 청취자 위치와 방향, 거리 감쇠, 잔향 등 초기 파라미터를 설정합니다.
    private func configureGraph(with format: AVAudioFormat) {
        eq.bands[0].filterType = .lowPass
        eq.bands[0].frequency = 20_000
        eq.bands[0].bypass = false

        engine.attach(player)
        engine.attach(eq)
        engine.attach(environment)

        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: environment, format: format)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        environment.renderingAlgorithm = .HRTFHQ
        environment.distanceAttenuationParameters.referenceDistance = 0.5
        environment.distanceAttenuationParameters.maximumDistance = 30.0
        environment.distanceAttenuationParameters.rolloffFactor = 1.0
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumHall)
        environment.reverbParameters.level = -18
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )

        player.renderingAlgorithm = .HRTFHQ
        player.position = AVAudio3DPoint(x: 0, y: 0, z: -0.35)
        player.reverbBlend = 0.08
        player.volume = baseVolume
    }

    /// 아직 재생 중이 아닐 때 배경음 루프 재생을 시작합니다.
    /// 버퍼를 무한 루프로 스케줄링하고 플레이어를 실행합니다.
    private func startLoopIfNeeded() {
        guard !isPlaying, let ambienceBuffer else { return }

        player.stop()
        player.scheduleBuffer(ambienceBuffer, at: nil, options: [.loops, .interruptsAtLoop])
        player.play()
        isPlaying = true
    }

    /// 배경음 재생을 즉시 중지하고 isPlaying 상태를 false로 초기화합니다.
    private func stop() {
        player.stop()
        isPlaying = false
    }

    /// 번들에서 지정된 MP3 파일을 읽어 모노 Float32 PCM 버퍼로 변환해 반환합니다.
    /// AVAudioEnvironmentNode는 모노 포맷 입력을 필요로 하므로, 스테레오 소스는 AVAudioConverter로 다운믹스합니다.
    /// - Parameter resourceName: 번들 내 MP3 파일 이름 (확장자 제외)
    private func loadMonoBuffer(resourceName: String) throws -> AVAudioPCMBuffer {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            throw NSError(domain: "SoundBox.Audio", code: 1, userInfo: [
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
            throw NSError(domain: "SoundBox.Audio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "배경음 원본 버퍼를 만들 수 없습니다."
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
            throw NSError(domain: "SoundBox.Audio", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "배경음 모노 버퍼를 만들 수 없습니다."
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
            throw NSError(domain: "SoundBox.Audio", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "배경음 모노 변환에 실패했습니다."
            ])
        }

        return monoBuffer
    }

    /// 값을 [lower, upper] 범위로 제한합니다.
    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
