import Cocoa

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
            let screenX = CGFloat(col) * 8.0 + 80.0
            let screenY = CGFloat(row) * 16.0 + 50.0
            let pt = CGPoint(x: screenX, y: particleView.bounds.height - screenY)
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
