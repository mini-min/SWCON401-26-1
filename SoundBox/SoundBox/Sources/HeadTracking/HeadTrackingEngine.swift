import CoreMotion
import Foundation
import Observation

// MARK: - HeadOrientation

struct HeadOrientation {
    var pitch: Double  // - = 앞으로 숙임 (거북목)
    var roll: Double   // + = 오른쪽으로 기울임
    var yaw: Double    // + = 오른쪽으로 회전

    static let neutral = HeadOrientation(pitch: 0, roll: 0, yaw: 0)

    /// 종합 자세 불량도 = max(-Pitch, 0) + |Yaw| × 0.5 + |Roll| × 0.8
    /// 센서 기준 앞으로 숙일 때 pitch가 음수로 나오므로 부호를 반전해 사용
    var compositeScore: Double {
        max(-pitch, 0) + abs(yaw) * 0.5 + abs(roll) * 0.8
    }

    /// 종합 자세 불량도 기반 심각도 (0~1)
    /// - < 15°: 정상 → 0
    /// - 15~30°: 주의 → 0~0.5
    /// - 30°+: 위험 → 0.5~1.0
    var severity: Double {
        let score = compositeScore
        if score < 15 {
            return 0
        } else if score < 30 {
            return (score - 15) / 15 * 0.5
        } else {
            return 0.5 + min((score - 30) / 30, 1.0) * 0.5
        }
    }

    var postureState: PostureState {
        let score = compositeScore
        switch score {
        case ..<15:   return .good    // 정상: 바른 자세
        case 15..<30: return .warning // 주의: 가벼운 자세 이탈
        default:      return .poor    // 위험: 심각한 전방머리자세
        }
    }
}

// MARK: - PostureState

enum PostureState: Equatable {
    case good
    case warning
    case poor

    var color: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .good: return (0.16, 0.82, 0.30)
        case .warning: return (0.99, 0.80, 0.18)
        case .poor: return (1.00, 0.22, 0.18)
        }
    }

    var label: String {
        switch self {
        case .good: return "정자세"
        case .warning: return "주의"
        case .poor: return "자세 교정 필요"
        }
    }

    var soundDescription: String {
        switch self {
        case .good: return "소리가 바로 앞에서 선명하게 들려요"
        case .warning: return "소리가 뒤로 물러나고 있어요"
        case .poor: return "소리가 뒤에서 먹먹하게 들려요"
        }
    }
}

// MARK: - TrackingStatus

enum TrackingStatus: Equatable {
    case idle
    case searching
    case active
    case simulating
    case disconnected
    case unauthorized
    case unavailable
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "대기 중"
        case .searching: return "헤드폰 탐색 중"
        case .active: return "헤드 트래킹 활성"
        case .simulating: return "시뮬레이션 모드"
        case .disconnected: return "헤드폰 미연결"
        case .unauthorized: return "모션 권한 필요"
        case .unavailable: return "헤드 트래킹 사용 불가"
        case .failed: return "센서 시작 실패"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "헤드 트래킹을 시작할 준비가 되었습니다."
        case .searching:
            return "AirPods 연결과 헤드 트래킹 사용 가능 여부를 확인하고 있습니다."
        case .active:
            return "실시간으로 AirPods 머리 움직임을 수신 중입니다."
        case .simulating:
            return "실제 헤드 트래킹이 없어 시각 피드백을 시뮬레이션으로 표시 중입니다."
        case .disconnected:
            return "헤드 트래킹을 지원하는 AirPods를 연결한 뒤 다시 확인하세요."
        case .unauthorized:
            return "시스템 설정에서 이 앱의 모션 및 피트니스 접근을 허용해야 합니다."
        case .unavailable:
            return "현재 환경에서 헤드폰 모션 데이터를 사용할 수 없습니다."
        case .failed(let message):
            return message
        }
    }
}

// MARK: - CalibrationState

enum CalibrationState: Equatable {
    case idle
    case capturing(secondsRemaining: Int)
    case completed

    var isRunning: Bool {
        if case .capturing = self {
            return true
        }
        return false
    }
}

// MARK: - HeadTrackingEngine

@MainActor
@Observable
final class HeadTrackingEngine: NSObject {
    static let shared = HeadTrackingEngine()

    var orientation: HeadOrientation = .neutral
    var postureState: PostureState = .good
    var isConnected = false
    var trackingStatus: TrackingStatus = .idle
    var calibrationState: CalibrationState = .idle
    var calibrationMessage: String?

    @ObservationIgnored var onOrientationUpdate: ((HeadOrientation) -> Void)?
    @ObservationIgnored var onCalibrationStateChange: ((CalibrationState, String?) -> Void)?

    private let smoothing: Double = 0.75

    @ObservationIgnored private var smoothed = HeadOrientation.neutral
    @ObservationIgnored private var motionManager: CMHeadphoneMotionManager?
    @ObservationIgnored private var neutralOffset = HeadOrientation.neutral
    @ObservationIgnored private var simTimer: Timer?
    @ObservationIgnored private var simPhase: Double = 0
    @ObservationIgnored private var updateQueue = OperationQueue()
    @ObservationIgnored private var calibrationTask: Task<Void, Never>?
    @ObservationIgnored private var calibrationSamples: [HeadOrientation] = []

    private override init() {
        super.init()
        updateQueue.name = "SoundBox.HeadTracking"
        updateQueue.qualityOfService = .userInteractive
        updateQueue.maxConcurrentOperationCount = 1
    }

    // MARK: Lifecycle

    /// 헤드 트래킹을 시작합니다.
    /// CMHeadphoneMotionManager를 생성하고 AirPods 연결 상태 감지를 시작합니다.
    /// AirPods가 연결된 경우 모션 업데이트를, 없는 경우 시뮬레이션 모드를 시작합니다.
    func start() {
        if motionManager == nil {
            let manager = CMHeadphoneMotionManager()
            manager.delegate = self
            motionManager = manager
        }

        guard let motionManager else { return }

        trackingStatus = .searching
        refreshAuthorizationStatus()
        motionManager.startConnectionStatusUpdates()

        if motionManager.isDeviceMotionAvailable {
            startMotionUpdatesIfPossible()
        } else if trackingStatus != .unauthorized {
            trackingStatus = .disconnected
            startSimulationIfNeeded()
        }
    }

    /// 헤드 트래킹을 완전히 중단합니다.
    /// 모션 업데이트, 연결 감지, 시뮬레이션, 보정 작업을 모두 정지하고 상태를 초기화합니다.
    func stop() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager?.stopConnectionStatusUpdates()
        stopSimulation()
        calibrationTask?.cancel()
        updateCalibrationState(.idle, message: nil)
        trackingStatus = .idle
        isConnected = false
    }

    /// 현재 자세를 기준 자세로 보정합니다.
    /// 3초 동안 센서 샘플을 수집하고, 완료 후 해당 평균값을 중립 오프셋으로 저장합니다.
    /// 트래킹이 활성 또는 시뮬레이션 상태일 때만 실행됩니다.
    func calibrate() {
        guard trackingStatus == .active || trackingStatus == .simulating else { return }

        calibrationTask?.cancel()
        calibrationSamples.removeAll(keepingCapacity: true)
        updateCalibrationState(.capturing(secondsRemaining: 3), message: "3초 동안 올바른 자세를 유지해 주세요")

        calibrationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for remaining in stride(from: 3, through: 1, by: -1) {
                self.updateCalibrationState(.capturing(secondsRemaining: remaining), message: "3초 동안 올바른 자세를 유지해 주세요")
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }

            self.finishCalibration()
        }
    }

    // MARK: Connection / Authorization

    /// 모션 권한 상태를 확인하고 trackingStatus를 갱신합니다.
    /// 권한이 거부된 경우 .unauthorized, 미결정인 경우 .searching으로 설정합니다.
    @discardableResult
    private func refreshAuthorizationStatus() -> CMAuthorizationStatus {
        let status = CMHeadphoneMotionManager.authorizationStatus()
        switch status {
        case .authorized:
            if trackingStatus == .unauthorized {
                trackingStatus = .searching
            }
        case .denied, .restricted:
            trackingStatus = .unauthorized
            isConnected = false
        case .notDetermined:
            trackingStatus = .searching
        @unknown default:
            trackingStatus = .failed("알 수 없는 모션 권한 상태입니다.")
        }
        return status
    }

    /// 권한과 가용성을 확인한 뒤 실제 AirPods 모션 업데이트를 시작합니다.
    /// 권한이 없거나 장치가 사용 불가한 경우 시뮬레이션 모드로 전환합니다.
    private func startMotionUpdatesIfPossible() {
        guard let motionManager else { return }
        guard refreshAuthorizationStatus() == .authorized || CMHeadphoneMotionManager.authorizationStatus() == .notDetermined else {
            return
        }

        guard motionManager.isDeviceMotionAvailable else {
            isConnected = false
            trackingStatus = .unavailable
            startSimulationIfNeeded()
            return
        }

        if motionManager.isDeviceMotionActive {
            stopSimulation()
            isConnected = true
            trackingStatus = .active
            return
        }

        motionManager.startDeviceMotionUpdates(to: updateQueue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.isConnected = false
                    self.trackingStatus = .failed(error.localizedDescription)
                    self.startSimulationIfNeeded()
                }
                return
            }

            guard let motion else { return }
            Task { @MainActor in
                self.stopSimulation()
                self.isConnected = true
                self.trackingStatus = .active
                self.process(motion)
            }
        }
    }

    // MARK: Processing

    /// CMDeviceMotion에서 라디안 단위의 attitude를 도(°) 단위 HeadOrientation으로 변환합니다.
    private func process(_ motion: CMDeviceMotion) {
        let attitude = motion.attitude
        let raw = HeadOrientation(
            pitch: attitude.pitch * 180 / .pi,
            roll: attitude.roll * 180 / .pi,
            yaw: attitude.yaw * 180 / .pi
        )

        applyProcessed(raw)
    }

    /// 시뮬레이션 모드에서 생성된 원시 HeadOrientation을 처리 파이프라인에 전달합니다.
    private func applyRaw(_ raw: HeadOrientation) {
        applyProcessed(raw)
    }

    /// 원시 자세값에 보정 오프셋을 적용하고, 지수 이동 평균(EMA)으로 스무딩한 뒤 상태를 업데이트합니다.
    /// 보정 진행 중이면 샘플을 수집하고, 최종적으로 onOrientationUpdate 콜백을 호출합니다.
    private func applyProcessed(_ raw: HeadOrientation) {
        if calibrationState.isRunning {
            calibrationSamples.append(raw)
        }

        // 중립 오프셋(사용자가 보정한 기준 자세)을 빼서 상대적 이탈량을 계산
        let adjusted = HeadOrientation(
            pitch: raw.pitch - neutralOffset.pitch,
            roll: raw.roll - neutralOffset.roll,
            yaw: raw.yaw - neutralOffset.yaw
        )

        // 지수 이동 평균으로 떨림 제거 (smoothing=0.75: 이전 값 75%, 새 값 25% 반영)
        let alpha = 1 - smoothing
        smoothed = HeadOrientation(
            pitch: smoothed.pitch * smoothing + adjusted.pitch * alpha,
            roll: smoothed.roll * smoothing + adjusted.roll * alpha,
            yaw: smoothed.yaw * smoothing + adjusted.yaw * alpha
        )
        orientation = smoothed
        postureState = smoothed.postureState
        onOrientationUpdate?(smoothed)
    }

    /// 3초간 수집된 샘플의 평균값을 중립 오프셋으로 저장하고 보정을 완료합니다.
    /// 샘플이 없으면 실패 메시지를 표시합니다.
    private func finishCalibration() {
        guard !calibrationSamples.isEmpty else {
            updateCalibrationState(.idle, message: "보정에 필요한 움직임 데이터를 받지 못했습니다.")
            clearCalibrationMessageLater()
            return
        }

        let count = Double(calibrationSamples.count)
        neutralOffset = HeadOrientation(
            pitch: calibrationSamples.map(\.pitch).reduce(0, +) / count,
            roll: calibrationSamples.map(\.roll).reduce(0, +) / count,
            yaw: calibrationSamples.map(\.yaw).reduce(0, +) / count
        )

        calibrationSamples.removeAll(keepingCapacity: true)
        smoothed = .neutral
        orientation = .neutral
        postureState = .good
        updateCalibrationState(.completed, message: "기준 자세를 저장했습니다.")
        onOrientationUpdate?(orientation)
        clearCalibrationMessageLater()
    }

    /// 보정 완료 메시지를 2초 후 자동으로 지웁니다.
    private func clearCalibrationMessageLater() {
        calibrationTask?.cancel()
        calibrationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.updateCalibrationState(.idle, message: nil)
        }
    }

    /// 보정 상태와 메시지를 동시에 업데이트하고 외부 콜백을 호출합니다.
    private func updateCalibrationState(_ state: CalibrationState, message: String?) {
        calibrationState = state
        calibrationMessage = message
        onCalibrationStateChange?(state, message)
    }

    // MARK: Simulation

    /// AirPods 없이도 UI·오디오 피드백을 테스트할 수 있도록 30Hz 타이머로 자세를 시뮬레이션합니다.
    /// 사인파 기반으로 고개 숙임(pitch)과 측면 기울임(roll/yaw)을 주기적으로 생성합니다.
    private func startSimulationIfNeeded() {
        guard simTimer == nil else { return }
        trackingStatus = .simulating
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.simPhase += 0.045
                let slouch = max(0, sin(self.simPhase)) * 0.9
                let drift = sin(self.simPhase * 0.6) * 0.25
                self.applyRaw(
                    HeadOrientation(
                        pitch: slouch * 42 + sin(self.simPhase * 2.8) * 1.5,
                        roll: drift * 14,
                        yaw: sin(self.simPhase * 1.2) * 9
                    )
                )
            }
        }
    }

    /// 시뮬레이션 타이머를 무효화하고 nil로 초기화합니다.
    private func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
    }
}

extension HeadTrackingEngine: CMHeadphoneMotionManagerDelegate {
    /// AirPods가 연결되면 시뮬레이션을 중단하고 실제 모션 업데이트를 시작합니다.
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopSimulation()
            self.isConnected = true
            if self.refreshAuthorizationStatus() != .authorized {
                return
            }
            self.startMotionUpdatesIfPossible()
        }
    }

    /// AirPods가 해제되면 모션 업데이트를 중단하고 자세 상태를 중립으로 초기화합니다.
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        manager.stopDeviceMotionUpdates()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopSimulation()
            self.isConnected = false
            self.trackingStatus = .disconnected
            self.smoothed = .neutral
            self.orientation = .neutral
            self.postureState = .good
            self.onOrientationUpdate?(.neutral)
        }
    }
}
