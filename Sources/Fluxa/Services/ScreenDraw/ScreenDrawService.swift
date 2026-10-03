import AppKit
import FluxaCore
import Observation
import ScreenCaptureKit
import SwiftUI

// MARK: - ScreenDrawService

/// Coordinates screen drawing overlays across all connected displays, mouse interaction,
/// presentation tools (laser pointer, spotlight, disappearing ink), and floating HUD toolbar.
@Observable
@MainActor
final class ScreenDrawService {

    // MARK: - State

    private(set) var isActive = false
    var activeTool: ScreenDrawTool = .pen
    var activeMode: ScreenDrawMode = .standard
    var selectedColor: ScreenDrawColor = .red
    var strokeWidth: Double = 5.0
    var disappearingTimeout: TimeInterval = 3.0
    var background: ScreenDrawBackground = .transparent
    var isClickThrough: Bool = false {
        didSet {
            updateClickThroughState()
        }
    }
    var showHUD: Bool = true {
        didSet {
            updateHUDVisibility()
        }
    }

    private static let hideHUDKey = "fluxa_screen_draw_hide_hud_from_capture"

    /// When true, the floating HUD toolbar is excluded from screen capture (Zoom, Teams, Meet, QuickTime).
    var hideHUDFromScreenCapture: Bool {
        didSet {
            UserDefaults.standard.set(hideHUDFromScreenCapture, forKey: Self.hideHUDKey)
            updateHUDSharingType()
        }
    }

    /// Source of the visual style the floating HUD follows.
    let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        if UserDefaults.standard.object(forKey: Self.hideHUDKey) == nil {
            self.hideHUDFromScreenCapture = true
        } else {
            self.hideHUDFromScreenCapture = UserDefaults.standard.bool(forKey: Self.hideHUDKey)
        }
    }

    // MARK: - Laser Pointer & Spotlight
    struct LaserSample: Equatable {
        var point: CGPoint
        var timestamp: TimeInterval
    }
    var laserPosition: CGPoint?
    var laserTrail: [LaserSample] = []
    var spotlightPosition: CGPoint?
    var spotlightRadius: CGFloat = 130.0

    func adjustSpotlightRadius(delta: CGFloat) {
        let newRadius = spotlightRadius + delta
        spotlightRadius = min(max(newRadius, 60.0), 400.0)
    }

    // MARK: - Mini-HUD & Collapsed State
    var isHUDCollapsed: Bool = false {
        didSet {
            hudPanel?.updateSizeAnchored()
        }
    }

    // MARK: - Shift Constraint State
    var isShiftPressed: Bool = false

    // MARK: - Text Tool State
    struct TextInputSession: Equatable {
        var screen: NSScreen
        var position: CGPoint
        var text: String = ""
    }
    var activeTextSession: TextInputSession?

    // MARK: - Screenshot Feedback State
    var isScreenshotCopied: Bool = false

    /// Live sampled points for the stroke currently being drawn.
    var activePoints: [DrawingPoint] = []

    /// Central stroke history from FluxaCore.
    let history = DrawingHistory()

    // MARK: - Private Properties

    private var overlayPanels: [ScreenDrawOverlayPanel] = []
    private var hudPanel: ScreenDrawHUDPanel?
    private var localEventMonitor: Any?
    private var flagsEventMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?
    private var temporaryClickThroughActive = false
    private var previouslyActiveApplication: NSRunningApplication?
    private var pruneTimer: Timer?

    // MARK: - Lifecycle

    func activate() {
        guard !isActive else { return }
        let currentApplication = NSRunningApplication.current
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != currentApplication.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        }

        isActive = true
        installMonitors()
        installScreenObserver()
        startPruneTimer()
        rebuildOverlays()

        if showHUD {
            presentHUD()
        }
    }

    func deactivate() {
        guard isActive else { return }
        if activeTextSession != nil {
            commitTextSession()
        }
        isActive = false
        stopPruneTimer()
        removeMonitors()
        removeScreenObserver()

        overlayPanels.forEach { $0.close() }
        overlayPanels.removeAll()

        hudPanel?.close()
        hudPanel = nil

        let appToRestore = previouslyActiveApplication
        previouslyActiveApplication = nil
        if let appToRestore, !appToRestore.isTerminated {
            NSApp.yieldActivation(to: appToRestore)
            _ = appToRestore.activate(from: .current, options: [])
        }
    }

    func toggleActive() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    // MARK: - Stroke Actions

    func undo() {
        history.undo()
    }

    func redo() {
        history.redo()
    }

    func clear() {
        history.clear()
        activePoints.removeAll()
    }

    // MARK: - Drawing Input Handling

    func handleMouseDown(at point: CGPoint, screen: NSScreen) {
        if activeTool == .text {
            startTextSession(at: point, screen: screen)
            return
        }

        if activeTextSession != nil {
            commitTextSession()
        }

        let drawPoint = DrawingPoint(x: point.x, y: point.y)
        switch activeTool {
        case .eraser:
            history.erase(at: drawPoint, radius: strokeWidth * 2.0)
        case .laserPointer:
            laserPosition = point
        case .spotlight:
            spotlightPosition = point
        case .text:
            break
        default:
            activePoints = [drawPoint]
        }
    }

    func handleMouseDragged(to point: CGPoint, screen: NSScreen) {
        let drawPoint = DrawingPoint(x: point.x, y: point.y)
        switch activeTool {
        case .eraser:
            history.erase(at: drawPoint, radius: strokeWidth * 2.0)
        case .laserPointer:
            let now = ProcessInfo.processInfo.systemUptime
            laserPosition = point
            laserTrail.append(LaserSample(point: point, timestamp: now))
            laserTrail.removeAll(where: { now - $0.timestamp > 0.45 })
        case .spotlight:
            spotlightPosition = point
        case .pen, .highlighter:
            activePoints.append(drawPoint)
        case .arrow, .line, .rectangle, .ellipse:
            let effectivePoint: DrawingPoint
            if isShiftPressed, let start = activePoints.first {
                effectivePoint = ShapeConstraints.snap(start: start, current: drawPoint, tool: activeTool)
            } else {
                effectivePoint = drawPoint
            }
            if activePoints.isEmpty {
                activePoints = [effectivePoint]
            } else if activePoints.count == 1 {
                activePoints.append(effectivePoint)
            } else {
                activePoints[1] = effectivePoint
            }
        case .text:
            break
        }
    }

    func handleMouseUp(at point: CGPoint, screen: NSScreen) {
        defer {
            activePoints.removeAll()
        }

        guard activeTool.isDrawingShape, activeTool != .text, !activePoints.isEmpty else { return }

        var completedPoints = activePoints
        if isShiftPressed, completedPoints.count >= 2 {
            completedPoints[1] = ShapeConstraints.snap(start: completedPoints[0], current: completedPoints[1], tool: activeTool)
        }

        let opacity = (activeTool == .highlighter) ? 0.45 : 1.0
        let effectiveWidth = (activeTool == .highlighter) ? strokeWidth * 2.5 : strokeWidth

        let stroke = DrawingStroke(
            tool: activeTool,
            points: completedPoints,
            color: selectedColor,
            lineWidth: effectiveWidth,
            opacity: opacity,
            createdAt: Date()
        )
        history.addStroke(stroke)
    }

    func handleMouseMoved(to point: CGPoint) {
        if activeTool == .laserPointer {
            let now = ProcessInfo.processInfo.systemUptime
            laserPosition = point
            laserTrail.append(LaserSample(point: point, timestamp: now))
            laserTrail.removeAll(where: { now - $0.timestamp > 0.45 })
        } else if activeTool == .spotlight {
            spotlightPosition = point
        }
    }

    // MARK: - Text Tool Handling

    func startTextSession(at point: CGPoint, screen: NSScreen) {
        if let existing = activeTextSession, !existing.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitTextSession()
        }
        let safeX = min(max(point.x, 16.0), screen.frame.width - 120.0)
        let safeY = min(max(point.y, 16.0), screen.frame.height - 40.0)
        activeTextSession = TextInputSession(screen: screen, position: CGPoint(x: safeX, y: safeY), text: "")
        if let panel = overlayPanels.first(where: { $0.targetScreen == screen }) {
            panel.makeKey()
        }
    }

    func commitTextSession() {
        guard let session = activeTextSession else { return }
        let trimmed = session.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let screenWidth = session.screen.frame.width
            let maxAllowedWidth = max(200.0, min(500.0, screenWidth - session.position.x - 30.0))
            let fontSize = max(16.0, strokeWidth * 2.5)
            let approxCharWidth = fontSize * 0.58
            let maxChars = max(15, Int(maxAllowedWidth / approxCharWidth))
            let wrapped = TextWrapping.wrap(text: trimmed, maxCharactersPerLine: maxChars)

            let lines = wrapped.components(separatedBy: "\n")
            let maxLineChars = lines.map(\.count).max() ?? 1
            let boundsW = Double(maxLineChars) * approxCharWidth
            let boundsH = Double(lines.count) * fontSize * 1.3

            let stroke = DrawingStroke(
                tool: .text,
                points: [DrawingPoint(x: session.position.x, y: session.position.y)],
                color: selectedColor,
                lineWidth: strokeWidth,
                opacity: 1.0,
                createdAt: Date(),
                text: wrapped,
                textBoundsWidth: boundsW,
                textBoundsHeight: boundsH
            )
            history.addStroke(stroke)
        }
        activeTextSession = nil
    }

    func cancelTextSession() {
        activeTextSession = nil
    }

    // MARK: - Screenshot Capture

    func captureAnnotatedScreenshot() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            NSSound.beep()
            return
        }

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Pick display containing the mouse cursor
                let mouseLocation = NSEvent.mouseLocation
                let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
                let targetDisplayID = (targetScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()

                guard let display = content.displays.first(where: { $0.displayID == targetDisplayID }) ?? content.displays.first else {
                    return
                }

                var excludedWindows: [SCWindow] = []
                if let hudNumber = self.hudPanel?.windowNumber {
                    excludedWindows = content.windows.filter { $0.windowID == CGWindowID(hudNumber) }
                }

                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let config = SCStreamConfiguration()
                let scale = Int(targetScreen?.backingScaleFactor ?? 2.0)
                config.width = display.width * scale
                config.height = display.height * scale
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                let image = NSImage(size: NSSize(width: display.width, height: display.height))
                image.addRepresentation(rep)

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])

                self.isScreenshotCopied = true
                NSSound(named: "Purr")?.play()

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.isScreenshotCopied = false
            } catch {
                NSSound.beep()
            }
        }
    }

    // MARK: - Stroke Width Stepping

    func stepStrokeWidth(increment: Bool) {
        let presets: [Double] = [3.0, 6.0, 12.0]
        if increment {
            if let next = presets.first(where: { $0 > strokeWidth }) {
                strokeWidth = next
            } else {
                strokeWidth = min(24.0, strokeWidth + 2.0)
            }
        } else {
            if let prev = presets.last(where: { $0 < strokeWidth }) {
                strokeWidth = prev
            } else {
                strokeWidth = max(2.0, strokeWidth - 2.0)
            }
        }
    }

    // MARK: - Overlay Management

    private func rebuildOverlays() {
        overlayPanels.forEach { $0.close() }
        overlayPanels.removeAll()

        for screen in NSScreen.screens {
            let panel = ScreenDrawOverlayPanel.create(screen: screen, service: self)
            overlayPanels.append(panel)
            panel.orderFrontRegardless()
        }

        overlayPanels.first?.makeKey()
        updateClickThroughState()
    }

    private func updateClickThroughState() {
        let ignores = isClickThrough || temporaryClickThroughActive
        for panel in overlayPanels {
            panel.ignoresMouseEvents = ignores
        }
    }

    // MARK: - Floating HUD Toolbar

    private func presentHUD() {
        if hudPanel == nil {
            hudPanel = ScreenDrawHUDPanel.create(service: self)
        }
        updateHUDSharingType()
        hudPanel?.orderFrontRegardless()
    }

    private func updateHUDVisibility() {
        if showHUD && isActive {
            presentHUD()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    private func updateHUDSharingType() {
        hudPanel?.sharingType = hideHUDFromScreenCapture ? .none : .readOnly
    }

    // MARK: - Event Monitoring

    private func installMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // When editing text, delegate keys or handle Enter / Escape
            if self.activeTextSession != nil {
                if event.keyCode == 36 { // Enter / Return
                    if event.modifierFlags.contains(.shift) {
                        return event // Allow Shift+Enter for multiline line-break
                    } else {
                        self.commitTextSession()
                        return nil
                    }
                }
                if event.keyCode == 53 { // ESC
                    self.cancelTextSession()
                    return nil
                }
                return event
            }

            // ESC (53) -> exit
            if event.keyCode == 53 {
                self.deactivate()
                return nil
            }
            // Cmd+Z -> Undo / Redo
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "z" {
                if event.modifierFlags.contains(.shift) {
                    self.redo()
                } else {
                    self.undo()
                }
                return nil
            }
            // Cmd+S -> Copy screenshot
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "s" {
                self.captureAnnotatedScreenshot()
                return nil
            }
            // Cmd+K or Cmd+Backspace -> Clear all
            if event.modifierFlags.contains(.command) &&
                (event.charactersIgnoringModifiers?.lowercased() == "k" || event.keyCode == 51) {
                self.clear()
                return nil
            }

            // Shortcuts without command modifier:
            if !event.modifierFlags.contains(.command) {
                // Number shortcuts 1-9, 0 for tools
                switch event.charactersIgnoringModifiers {
                case "1": self.activeTool = .pen; return nil
                case "2": self.activeTool = .highlighter; return nil
                case "3": self.activeTool = .arrow; return nil
                case "4": self.activeTool = .line; return nil
                case "5": self.activeTool = .rectangle; return nil
                case "6": self.activeTool = .ellipse; return nil
                case "7": self.activeTool = .text; return nil
                case "8": self.activeTool = .laserPointer; return nil
                case "9": self.activeTool = .spotlight; return nil
                case "0": self.activeTool = .eraser; return nil
                default: break
                }

                // Letter keys for colors:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "r": self.selectedColor = .red; return nil
                case "o": self.selectedColor = .orange; return nil
                case "y": self.selectedColor = .yellow; return nil
                case "g": self.selectedColor = .green; return nil
                case "b": self.selectedColor = .cyan; return nil
                case "p": self.selectedColor = .purple; return nil
                case "w": self.selectedColor = .white; return nil
                case "[":
                    self.stepStrokeWidth(increment: false)
                    return nil
                case "]":
                    self.stepStrokeWidth(increment: true)
                    return nil
                default: break
                }
            }

            return event
        }

        // Holding Option (⌥) or Fn temporarily enables click-through; Shift (⇧) enables shape constraint
        flagsEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let shiftPressed = event.modifierFlags.contains(.shift)
            if self.isShiftPressed != shiftPressed {
                self.isShiftPressed = shiftPressed
            }

            let optionPressed = event.modifierFlags.contains(.option)
            if self.temporaryClickThroughActive != optionPressed {
                self.temporaryClickThroughActive = optionPressed
                self.updateClickThroughState()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = flagsEventMonitor {
            NSEvent.removeMonitor(monitor)
            flagsEventMonitor = nil
        }
    }

    private func installScreenObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isActive == true else { return }
                self?.rebuildOverlays()
            }
        }
    }

    private func removeScreenObserver() {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParametersObserver = nil
        }
    }

    // MARK: - Disappearing Ink Prune Timer

    private func startPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeMode == .disappearing else { return }
                _ = self.history.pruneExpired(timeout: self.disappearingTimeout)
            }
        }
    }

    private func stopPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = nil
    }
}
