import Foundation

struct SpatialState: Codable {
    var yaw: Double
    var pitch: Double
    var roll: Double
    var severity: Double
    var postureState: String

    static let neutral = SpatialState(yaw: 0, pitch: 0, roll: 0, severity: 0, postureState: "good")
}
