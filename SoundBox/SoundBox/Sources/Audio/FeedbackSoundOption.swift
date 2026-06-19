import Foundation

enum FeedbackSoundOption: String, CaseIterable {
    case knockMono          // 나무 위에서 문 두둘기는 소리
    case coughManMono       // 남자 기침 소리

    var title: String {
        switch self {
        case .knockMono:
            return "노크 소리"
        case .coughManMono:
            return "기침 소리"
        }
    }

    var resourceName: String {
        switch self {
        case .knockMono:
            return "knock_mono"
        case .coughManMono:
            return "coughMan_mono"
        }
    }
}
