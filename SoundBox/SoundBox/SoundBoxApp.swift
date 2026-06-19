import AppKit
import SwiftUI
import QuartzCore

@main
struct SoundBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .environment(HeadTrackingEngine.shared)
        .environment(SpatialAudioEngine.shared)
        .commands {
            CommandMenu("Sound Box") {
                Button(appDelegate.isVisualEffectsEnabled ? "시각 효과 끄기" : "시각 효과 켜기") {
                    appDelegate.toggleVisualEffects()
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Button(SpatialAudioEngine.shared.isAmbienceEnabled ? "배경음 끄기" : "배경음 켜기") {
                    SpatialAudioEngine.shared.toggleAmbience()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Button(SpatialAudioEngine.shared.isFeedbackEnabled ? "피드백 끄기" : "피드백 켜기") {
                    SpatialAudioEngine.shared.toggleFeedback()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("현재 자세 보정") {
                    appDelegate.calibrate()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let edgeGlowEnabledKey = "glowEnabled"

    private var calibrationOverlayWindow: CalibrationOverlayWindow?
    private var edgeGlowWindow: EdgeGlowWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var isEdgeGlowEnabled = UserDefaults.standard.object(forKey: edgeGlowEnabledKey) == nil ? true : UserDefaults.standard.bool(forKey: edgeGlowEnabledKey)
    private var lastStatusItemText = ""
    private var lastStatusItemImageName = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherRunningInstances()
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        updateStatusItemAppearance(
            orientation: HeadTrackingEngine.shared.orientation,
            postureState: HeadTrackingEngine.shared.postureState,
            trackingStatus: HeadTrackingEngine.shared.trackingStatus
        )

        if let screen = NSScreen.main {
            calibrationOverlayWindow = CalibrationOverlayWindow(screen: screen)
            edgeGlowWindow = EdgeGlowWindow(screen: screen)
            applyVisualEffectVisibility()
        }

        HeadTrackingEngine.shared.start()
        SpatialAudioEngine.shared.setup()
        PeerSessionManager.shared.start()

        HeadTrackingEngine.shared.onOrientationUpdate = { [weak self] orientation in
            DispatchQueue.main.async {
                let trackingStatus = HeadTrackingEngine.shared.trackingStatus
                self?.updateStatusItemAppearance(
                    orientation: orientation,
                    postureState: orientation.postureState,
                    trackingStatus: trackingStatus
                )
                self?.edgeGlowWindow?.update(orientation: orientation)
                if trackingStatus == .active || trackingStatus == .simulating {
                    SpatialAudioEngine.shared.resume()
                    SpatialAudioEngine.shared.update(orientation: orientation)
                } else {
                    SpatialAudioEngine.shared.suspend()
                }
                PeerSessionManager.shared.send(orientation)
            }
        }
        HeadTrackingEngine.shared.onCalibrationStateChange = { [weak self] state, message in
            DispatchQueue.main.async {
                self?.calibrationOverlayWindow?.update(state: state, message: message)
            }
        }
    }

    // MARK: Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.imagePosition = .imageTrailing
            button.appearsDisabled = false
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "Sound Box"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.imageScaling = .scaleProportionallyUpOrDown
            button.wantsLayer = true
        }

        statusItem?.isVisible = true

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentSize = NSSize(width: 500, height: 212)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                onSetEdgeGlowEnabled: { [weak self] in self?.setEdgeGlowEnabled($0) },
                onCalibrate: { [weak self] in self?.calibrate() }
            )
            .environment(HeadTrackingEngine.shared)
            .environment(SpatialAudioEngine.shared)
        )
        self.popover = popover
    }

    private func updateStatusItemAppearance(
        orientation: HeadOrientation,
        postureState: PostureState,
        trackingStatus: TrackingStatus
    ) {
        guard let button = statusItem?.button else { return }

        let imageName = statusItemImageName(postureState: postureState, trackingStatus: trackingStatus)
        let text = statusItemValueText(orientation: orientation, trackingStatus: trackingStatus)

        button.image = statusItemImage(named: imageName)
        button.title = ""
        button.attributedTitle = statusItemAttributedText(
            orientation: orientation,
            text: text,
            trackingStatus: trackingStatus
        )
        button.contentTintColor = nil

        lastStatusItemImageName = imageName
        lastStatusItemText = text
    }

    private func statusItemImageName(postureState: PostureState, trackingStatus: TrackingStatus) -> String {
        switch trackingStatus {
        case .active:
            switch postureState {
            case .good:
                return "normal_level"
            case .warning:
                return "yellow_level"
            case .poor:
                return "red_level"
            }
        case .searching, .simulating:
            return "yellow_level"
        case .idle, .disconnected, .unauthorized, .unavailable, .failed:
            return "normal_level"
        }
    }

    private func statusItemImage(named assetName: String) -> NSImage? {
        let image = NSImage(named: assetName)
        image?.size = NSSize(width: 21, height: 21)
        image?.isTemplate = false
        return image
    }

    private func statusItemValueText(orientation: HeadOrientation, trackingStatus: TrackingStatus) -> String {
        switch trackingStatus {
        case .active, .simulating:
            return String(format: " %2d°", Int(orientation.pitch.rounded()))
        case .searching:
            return " ..."
        case .idle, .disconnected, .unauthorized, .unavailable, .failed:
            return " --"
        }
    }

    private func statusItemAttributedText(
        orientation: HeadOrientation,
        text: String,
        trackingStatus: TrackingStatus
    ) -> NSAttributedString {
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(
                rootView: MenuBarPopoverView(
                    onSetEdgeGlowEnabled: { [weak self] in self?.setEdgeGlowEnabled($0) },
                    onCalibrate: { [weak self] in self?.calibrate() }
                )
                .environment(HeadTrackingEngine.shared)
                .environment(SpatialAudioEngine.shared)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let rootView = SettingsView()
                .environment(HeadTrackingEngine.shared)
                .environment(SpatialAudioEngine.shared)

            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sound Box Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleVisualEffects() {
        setVisualEffectsEnabled(!isVisualEffectsEnabled)
    }

    func toggleEdgeGlow() {
        setEdgeGlowEnabled(!isEdgeGlowEnabled)
    }

    func calibrate() {
        HeadTrackingEngine.shared.calibrate()
    }

    var isVisualEffectsEnabled: Bool {
        isEdgeGlowEnabled
    }

    func setVisualEffectsEnabled(_ enabled: Bool) {
        isEdgeGlowEnabled = enabled
        persistVisualEffectState()
        applyVisualEffectVisibility()
    }

    func setEdgeGlowEnabled(_ enabled: Bool) {
        isEdgeGlowEnabled = enabled
        persistVisualEffectState()
        applyVisualEffectVisibility()
    }

    private func persistVisualEffectState() {
        UserDefaults.standard.set(isEdgeGlowEnabled, forKey: Self.edgeGlowEnabledKey)
    }

    private func applyVisualEffectVisibility() {
        if isEdgeGlowEnabled {
            edgeGlowWindow?.orderFrontRegardless()
        } else {
            edgeGlowWindow?.orderOut(nil)
        }
    }

    private func terminateOtherRunningInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }

        for instance in otherInstances {
            instance.terminate()
        }
    }
}
