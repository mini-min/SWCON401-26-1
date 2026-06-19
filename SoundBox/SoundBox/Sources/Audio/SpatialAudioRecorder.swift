@preconcurrency import AVFAudio
import Foundation

@MainActor
final class SpatialAudioRecorder {
    private(set) var isRecording = false
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private let writeQueue = DispatchQueue(label: "SoundBox.Recorder")
    private var isWriting = false

    func installPersistentTap(on node: AVAudioMixerNode) {
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }

        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, self.isWriting else { return }
            self.writeQueue.async {
                try? self.audioFile?.write(from: buffer)
            }
        }
    }

    func start(format: AVAudioFormat) throws -> URL {
        guard !isRecording else {
            throw NSError(domain: "SoundBox.Recorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "이미 녹음 중입니다."])
        }

        let url = makeFileURL()
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        isWriting = true
        isRecording = true
        print("[Recorder] Started: \(url.lastPathComponent)")
        return url
    }

    func stop() -> URL? {
        guard isRecording else { return nil }

        isWriting = false
        writeQueue.sync {}
        audioFile = nil
        isRecording = false
        print("[Recorder] Stopped: \(recordingURL?.lastPathComponent ?? "")")
        return recordingURL
    }

    private func makeFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileName = "SoundBox_\(timestamp).caf"

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent(fileName)
    }
}
