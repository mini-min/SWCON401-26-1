import Foundation
import Observation

@MainActor
@Observable
final class SpatialAudioEngine {
    static let shared = SpatialAudioEngine()

    private static let selectedFeedbackSoundKey = "selectedFeedbackSound"
    private static let ambienceEnabledKey = "ambienceEnabled"
    private static let feedbackEnabledKey = "feedbackEnabled"

    var spatialStrength: Double = 0.7
    var isReady = false
    var isAmbienceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAmbienceEnabled, forKey: Self.ambienceEnabledKey)
            ambienceEngine.setEnabled(isAmbienceEnabled)
        }
    }
    var isFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFeedbackEnabled, forKey: Self.feedbackEnabledKey)
            if !isFeedbackEnabled {
                warningEngine.stopIfNeeded()
            }
        }
    }
    var selectedFeedbackSound: FeedbackSoundOption {
        didSet {
            UserDefaults.standard.set(selectedFeedbackSound.rawValue, forKey: Self.selectedFeedbackSoundKey)
        }
    }

    var isRecording: Bool { recorder.isRecording }
    var lastRecordingURL: URL?

    @ObservationIgnored private let ambienceEngine = AmbienceAudioEngine()
    @ObservationIgnored private let warningEngine = WarningFeedbackAudioEngine()
    @ObservationIgnored private let recorder = SpatialAudioRecorder()
    @ObservationIgnored private var isSuspended = false

    /// UserDefaults에서 이전 세션의 설정을 복원합니다.
    /// 저장된 값이 없으면 배경음·피드백은 켜짐, 효과음은 노크 소리로 기본값을 설정합니다.
    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.selectedFeedbackSoundKey),
           let option = FeedbackSoundOption(rawValue: rawValue) {
            selectedFeedbackSound = option
        } else {
            selectedFeedbackSound = .knockMono
        }

        if UserDefaults.standard.object(forKey: Self.ambienceEnabledKey) != nil {
            isAmbienceEnabled = UserDefaults.standard.bool(forKey: Self.ambienceEnabledKey)
        } else {
            isAmbienceEnabled = true
        }

        if UserDefaults.standard.object(forKey: Self.feedbackEnabledKey) != nil {
            isFeedbackEnabled = UserDefaults.standard.bool(forKey: Self.feedbackEnabledKey)
        } else {
            isFeedbackEnabled = true
        }
    }

    /// 배경음 엔진과 경고음 엔진을 초기화하고, 오디오 장치 변경 알림을 등록합니다.
    /// AVAudioEngineConfigurationChange 알림을 수신하면 각 엔진을 필요에 따라 재시작합니다.
    func setup() {
        ambienceEngine.setup()
        warningEngine.setup()
        ambienceEngine.setEnabled(isAmbienceEnabled)
        isReady = ambienceEngine.isReady && warningEngine.isReady

        if isReady {
            recorder.installPersistentTap(on: ambienceEngine.mainMixer)
        }

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // 오디오 장치 변경(AirPods 연결/해제) 시 엔진 재시작
            self.warningEngine.restartEngineIfNeeded()
            if !self.isSuspended && self.isAmbienceEnabled {
                self.ambienceEngine.restartEngineIfNeeded()
            }
        }
    }

    /// 매 프레임 최신 자세 데이터를 각 엔진에 전달합니다.
    /// 배경음은 항상 업데이트하고, 경고음은 isFeedbackEnabled가 true일 때만 처리합니다.
    func update(orientation: HeadOrientation) {
        ambienceEngine.update(orientation: orientation, strength: spatialStrength)
        if isFeedbackEnabled {
            warningEngine.update(
                orientation: orientation,
                selectedSound: selectedFeedbackSound,
                strength: spatialStrength
            )
        } else {
            warningEngine.stopIfNeeded()
        }
    }

    /// 트래킹이 비활성 상태일 때 오디오를 일시 중단합니다.
    /// 배경음을 끄고 경고음 재생을 멈춥니다. 이미 중단된 경우 무시합니다.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        ambienceEngine.setEnabled(false)
        warningEngine.stopIfNeeded()
    }

    /// 트래킹이 재개될 때 오디오를 복구합니다.
    /// 사용자 설정(isAmbienceEnabled)에 따라 배경음을 다시 활성화합니다.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        ambienceEngine.setEnabled(isAmbienceEnabled)
    }

    /// 배경음 활성화 상태를 토글합니다. 변경값은 UserDefaults에 자동 저장됩니다.
    func toggleAmbience() {
        isAmbienceEnabled.toggle()
    }

    /// 경고 피드백음 활성화 상태를 토글합니다. 변경값은 UserDefaults에 자동 저장됩니다.
    func toggleFeedback() {
        isFeedbackEnabled.toggle()
    }

    func startRecording() throws {
        let url = try recorder.start(format: ambienceEngine.outputFormat)
        lastRecordingURL = url
    }

    func stopRecording() {
        lastRecordingURL = recorder.stop()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            try? startRecording()
        }
    }
}
