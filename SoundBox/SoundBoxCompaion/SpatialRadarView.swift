import SwiftUI

struct SpatialRadarView: View {
    let state: SpatialState

    private static let bumpPositions: [(angle: Double, color: Color)] = [
        (30, .red),      // 1시 - 오른쪽 앞
        (120, .red),     // 4시 - 오른쪽 뒤
        (180, .green),   // 6시 - 뒤
        (240, .blue),    // 8시 - 왼쪽 뒤
        (330, .blue),    // 11시 - 왼쪽 앞
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.82

            ZStack {
                outerRing(size: size)
                radarGrid(size: size)
                fixedBumps(size: size)
                headphoneIcon(size: size)
                positionDot(size: size)
                directionLabels(size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Outer Ring

    private func outerRing(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                .frame(width: size, height: size)

            ForEach(0..<36, id: \.self) { i in
                let isCardinal = i % 9 == 0
                let isMajor = i % 3 == 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(isCardinal ? 0.5 : (isMajor ? 0.25 : 0.12)))
                    .frame(
                        width: isCardinal ? 3 : 1.5,
                        height: isCardinal ? 10 : (isMajor ? 6 : 3)
                    )
                    .offset(y: -size / 2 + (isCardinal ? 5 : (isMajor ? 3 : 1.5)))
                    .rotationEffect(.degrees(Double(i) * 10))
            }
        }
    }

    // MARK: - Grid

    private func radarGrid(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                .frame(width: size * 0.66, height: size * 0.66)

            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                .frame(width: size * 0.33, height: size * 0.33)

            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 0.5, height: size)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
    }

    // MARK: - Fixed Bumps

    private var horizontalOffset: Double {
        state.yaw + state.roll * 0.8
    }

    private func soundAngle() -> Double {
        atan2(-horizontalOffset, state.pitch) * 180 / .pi
    }

    private func soundMagnitude() -> Double {
        sqrt(horizontalOffset * horizontalOffset + state.pitch * state.pitch)
    }

    private func bumpIntensity(at bumpAngle: Double) -> Double {
        let mag = soundMagnitude()
        guard mag > 2 else { return 0 }

        let sound = soundAngle()
        let normalizedSound = sound < 0 ? sound + 360 : sound
        let normalizedBump = bumpAngle < 0 ? bumpAngle + 360 : bumpAngle

        var diff = abs(normalizedSound - normalizedBump)
        if diff > 180 { diff = 360 - diff }

        let proximity = max(0, 1 - diff / 50)
        return proximity * min(1, mag / 20)
    }

    private func fixedBumps(size: CGFloat) -> some View {
        let ringRadius = size / 2
        let minBumpSize = size * 0.10
        let maxBumpSize = size * 0.28

        return ZStack {
            ForEach(0..<Self.bumpPositions.count, id: \.self) { i in
                let pos = Self.bumpPositions[i]
                let intensity = bumpIntensity(at: pos.angle)
                let bumpDiameter = minBumpSize + (maxBumpSize - minBumpSize) * CGFloat(intensity)
                let angleRad = (pos.angle - 90) * .pi / 180
                let outward = ringRadius + bumpDiameter * 0.25

                Circle()
                    .fill(pos.color.opacity(0.18 + 0.72 * intensity))
                    .frame(width: bumpDiameter, height: bumpDiameter)
                    .offset(
                        x: cos(angleRad) * outward,
                        y: sin(angleRad) * outward
                    )
            }
        }
        .animation(.easeOut(duration: 0.1), value: state.yaw)
        .animation(.easeOut(duration: 0.1), value: state.pitch)
    }

    // MARK: - Headphone

    private func headphoneIcon(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.28, height: size * 0.28)

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                .frame(width: size * 0.28, height: size * 0.28)

            Image(systemName: "headphones")
                .font(.system(size: size * 0.10, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Position Dot

    private func positionDot(size: CGFloat) -> some View {
        let maxOffset = size * 0.46
        let normalizer = maxOffset / 40.0

        let rawX = CGFloat(-horizontalOffset) * normalizer
        let rawY = CGFloat(-state.pitch) * normalizer

        let dist = sqrt(rawX * rawX + rawY * rawY)
        let clampedDist = min(dist, maxOffset)
        let scale: CGFloat = dist > 0.001 ? clampedDist / dist : 0
        let x = rawX * scale
        let y = rawY * scale

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 16, height: 16)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 10, height: 10)
        }
        .shadow(color: .white.opacity(0.2), radius: 6)
        .offset(x: x, y: y)
        .animation(.easeOut(duration: 0.08), value: state.yaw)
        .animation(.easeOut(duration: 0.08), value: state.pitch)
    }

    // MARK: - Labels

    private func directionLabels(size: CGFloat) -> some View {
        let offset = size / 2 + 22
        return ZStack {
            Text("앞").offset(y: -offset)
            Text("뒤").offset(y: offset)
            Text("좌").offset(x: -offset)
            Text("우").offset(x: offset)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
    }
}
