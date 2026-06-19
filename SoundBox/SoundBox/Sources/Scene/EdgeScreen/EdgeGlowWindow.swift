import AppKit
import QuartzCore

final class EdgeGlowWindow: NSPanel {
    private let visualSmoothingFactor: CGFloat = 0.05
    private let overlayLayer = CALayer()
    private let radarLayer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let outerRingLayer = CAShapeLayer()
    private let markerLayer = CALayer()
    private let centerLayer = CALayer()

    private var currentRGB: (CGFloat, CGFloat, CGFloat) = (0.16, 0.78, 0.25)
    private var currentOrientation: HeadOrientation = .neutral
    private var smoothedNormalizedX: CGFloat = 0
    private var smoothedNormalizedY: CGFloat = 0
    private var smoothedSeverity: CGFloat = 0
    private var smoothedMarkerPoint: CGPoint?
    private var smoothedMarkerScale: CGFloat = 1

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelKey.screenSaverWindow.rawValue))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false

        buildLayers(frame: screen.frame)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutRadar(in: frameRect)
    }

    private func buildLayers(frame: NSRect) {
        guard let root = contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = CGColor.clear

        overlayLayer.frame = frame
        root.layer?.addSublayer(overlayLayer)

        glowLayer.type = .radial
        glowLayer.colors = gradientColors()
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowLayer.opacity = 0
        radarLayer.addSublayer(glowLayer)

        outerRingLayer.fillColor = NSColor.clear.cgColor
        outerRingLayer.lineWidth = 2.2
        radarLayer.addSublayer(outerRingLayer)

        centerLayer.cornerRadius = 6
        centerLayer.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.90).cgColor
        centerLayer.borderWidth = 1.5
        centerLayer.shadowOpacity = 0.22
        centerLayer.shadowRadius = 10
        radarLayer.addSublayer(centerLayer)

        markerLayer.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        markerLayer.cornerRadius = 18
        markerLayer.shadowOpacity = 0.55
        markerLayer.shadowRadius = 18
        markerLayer.shadowOffset = .zero
        radarLayer.addSublayer(markerLayer)

        overlayLayer.addSublayer(radarLayer)
        layoutRadar(in: frame)
        applyColors()
        setOverlayOpacity(0)
    }

    private func layoutRadar(in frame: NSRect) {
        let diameter = min(frame.width, frame.height) * 1.22
        let radarFrame = CGRect(
            x: frame.midX - diameter / 2,
            y: frame.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        overlayLayer.frame = frame
        radarLayer.frame = radarFrame
        glowLayer.frame = radarLayer.bounds.insetBy(dx: -90, dy: -90)

        let center = CGPoint(x: radarLayer.bounds.midX, y: radarLayer.bounds.midY)
        let maxRadius = diameter * 0.49

        outerRingLayer.frame = radarLayer.bounds
        outerRingLayer.path = CGPath(
            ellipseIn: CGRect(
                x: center.x - maxRadius,
                y: center.y - maxRadius,
                width: maxRadius * 2,
                height: maxRadius * 2
            ),
            transform: nil
        )

        centerLayer.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        centerLayer.cornerRadius = 6
        centerLayer.position = center

        smoothedNormalizedX = 0
        smoothedNormalizedY = 0
        smoothedSeverity = 0
        smoothedMarkerPoint = center
        smoothedMarkerScale = 1
        updateMarkerPosition(for: currentOrientation, animated: false)
    }

    func update(orientation: HeadOrientation) {
        currentOrientation = orientation

        if orientation.postureState == .good {
            setOverlayOpacity(0)
            return
        }

        let color = orientation.postureState.color
        if color.r != currentRGB.0 || color.g != currentRGB.1 || color.b != currentRGB.2 {
            currentRGB = (color.r, color.g, color.b)
            applyColors()
        }

        setOverlayOpacity(orientation.postureState == .warning ? 0.78 : 1.0)
        updateMarkerPosition(for: orientation, animated: true)
    }

    private func updateMarkerPosition(for orientation: HeadOrientation, animated: Bool) {
        let center = CGPoint(x: radarLayer.bounds.midX, y: radarLayer.bounds.midY)
        let maxRadius = min(radarLayer.bounds.width, radarLayer.bounds.height) * 0.485

        let targetNormalizedX = clamp(-orientation.yaw / 28.0, -1.0, 1.0)
        // 화면 위쪽이 "앞으로 숙임" 방향이 되도록 pitch 양수를 위로 보냅니다.
        let targetNormalizedY = clamp(orientation.pitch / 22.0, -1.0, 1.0)
        let targetSeverity = max(0.38, pow(orientation.severity, 0.75) * 1.18)

        if animated {
            smoothedNormalizedX += (CGFloat(targetNormalizedX) - smoothedNormalizedX) * visualSmoothingFactor
            smoothedNormalizedY += (CGFloat(targetNormalizedY) - smoothedNormalizedY) * visualSmoothingFactor
            smoothedSeverity += (CGFloat(targetSeverity) - smoothedSeverity) * visualSmoothingFactor
        } else {
            smoothedNormalizedX = CGFloat(targetNormalizedX)
            smoothedNormalizedY = CGFloat(targetNormalizedY)
            smoothedSeverity = CGFloat(targetSeverity)
        }

        let targetPoint = CGPoint(
            x: center.x + smoothedNormalizedX * maxRadius * smoothedSeverity,
            y: center.y + smoothedNormalizedY * maxRadius * smoothedSeverity
        )
        let targetScale = 0.92 + smoothedSeverity * 0.72

        let nextPoint: CGPoint
        if animated, let smoothedMarkerPoint {
            nextPoint = CGPoint(
                x: smoothedMarkerPoint.x + (targetPoint.x - smoothedMarkerPoint.x) * visualSmoothingFactor,
                y: smoothedMarkerPoint.y + (targetPoint.y - smoothedMarkerPoint.y) * visualSmoothingFactor
            )
        } else {
            nextPoint = targetPoint
        }

        let nextScale: CGFloat
        if animated {
            nextScale = smoothedMarkerScale + (targetScale - smoothedMarkerScale) * visualSmoothingFactor
        } else {
            nextScale = targetScale
        }

        smoothedMarkerPoint = nextPoint
        smoothedMarkerScale = nextScale

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.08 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        markerLayer.position = nextPoint
        markerLayer.setAffineTransform(CGAffineTransform(scaleX: nextScale, y: nextScale))

        CATransaction.commit()
    }

    private func applyColors() {
        let accent = NSColor(red: currentRGB.0, green: currentRGB.1, blue: currentRGB.2, alpha: 1)
        let softAccent = accent.withAlphaComponent(0.05)
        let isOuterRingVisible = currentOrientation.postureState == .poor

        glowLayer.colors = gradientColors()
        outerRingLayer.strokeColor = accent.withAlphaComponent(isOuterRingVisible ? 0.34 : 0.0).cgColor
        centerLayer.borderColor = accent.withAlphaComponent(0.55).cgColor
        centerLayer.shadowColor = accent.withAlphaComponent(0.28).cgColor
        markerLayer.backgroundColor = accent.cgColor
        markerLayer.borderWidth = 2
        markerLayer.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        markerLayer.shadowColor = accent.cgColor
        radarLayer.backgroundColor = softAccent.cgColor
        radarLayer.cornerRadius = radarLayer.bounds.width / 2
        radarLayer.borderWidth = 0
        radarLayer.borderColor = nil
    }

    private func gradientColors() -> [CGColor] {
        let accent = NSColor(red: currentRGB.0, green: currentRGB.1, blue: currentRGB.2, alpha: 1)
        return [
            accent.withAlphaComponent(0.22).cgColor,
            accent.withAlphaComponent(0.07).cgColor,
            NSColor.clear.cgColor
        ]
    }

    private func setOverlayOpacity(_ value: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = radarLayer.presentation()?.opacity ?? radarLayer.opacity
        animation.toValue = value
        animation.duration = 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        radarLayer.add(animation, forKey: "radarOpacity")
        radarLayer.opacity = value
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
