import Cocoa

// MARK: - iTerm2 Window Bounds Helper

private var cachedBounds: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)?
private var lastBoundsTime: Date = .distantPast
private var boundsLock = NSLock()
private var fetchingBounds = false

func getCachedItermBounds() -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? {
    boundsLock.lock()
    let result = cachedBounds
    let shouldFetch = !fetchingBounds && Date().timeIntervalSince(lastBoundsTime) >= 2.0
    if shouldFetch { fetchingBounds = true }
    boundsLock.unlock()
    
    if shouldFetch {
        DispatchQueue.global(qos: .utility).async {
            let bounds = getItermWindowBoundsSync()
            boundsLock.lock()
            if let b = bounds {
                cachedBounds = b
            }
            lastBoundsTime = Date()
            fetchingBounds = false
            boundsLock.unlock()
        }
    }
    return result
}

private func getItermWindowBoundsSync() -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? {
    let script = """
    tell application "iTerm2"
        set w to front window
        set b to bounds of w
        set x1 to item 1 of b as text
        set y1 to item 2 of b as text
        set x2 to item 3 of b as text
        set y2 to item 4 of b as text
        return x1 & "," & y1 & "," & x2 & "," & y2
    end tell
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = output.components(separatedBy: ",").compactMap { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 0) }
        guard parts.count == 4 else { return nil }
        return (x: parts[0], y: parts[1], w: parts[2] - parts[0], h: parts[3] - parts[1])
    } catch {
        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow!
    var particleView: ParticleView!
    var jsonReader: JsonReader!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        overlayWindow = OverlayWindow(frame: frame)

        particleView = ParticleView(frame: frame)
        overlayWindow.contentView = particleView
        overlayWindow.makeKeyAndOrderFront(nil)

        jsonReader = JsonReader { [weak self] event in
            DispatchQueue.main.async {
                self?.handleEvent(event)
            }
        }
        jsonReader.start()

        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.particleView.update(dt: 1.0/60.0)
            self?.particleView.needsDisplay = true
        }
    }

    func handleEvent(_ event: [String: Any]) {
        guard let type = event["event"] as? String else { return }
        switch type {
        case "keystroke":
            let row = event["row"] as? Double ?? 0
            let col = event["col"] as? Double ?? 0
            let combo = event["combo"] as? Int ?? 0
            let level = event["level"] as? Int ?? 0
            let bounds = getCachedItermBounds()
            let cellW: CGFloat = 8.0
            let cellH: CGFloat = 16.0
            let yOffset: CGFloat = 70
            let xOffset: CGFloat = 4
            let screenX = (bounds?.x ?? 0) + xOffset + CGFloat(col) * cellW
            let screenFrame = NSScreen.main?.frame ?? .zero
            let screenY = screenFrame.height - ((bounds?.y ?? 0) + yOffset + CGFloat(row) * cellH)
            let pt = CGPoint(x: screenX, y: screenY)
            particleView.spawnParticles(at: pt, count: 3 + level * 2)
            particleView.updateCombo(streak: combo, level: level)
            particleView.updateGlow(at: pt)
        default:
            break
        }
    }
}

// Handle SIGINT for graceful shutdown
signal(SIGINT) { _ in
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
