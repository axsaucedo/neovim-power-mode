import Cocoa
import QuartzCore

// MARK: - Particle

struct Particle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var alpha: CGFloat
    var lifetime: CGFloat
    var maxLifetime: CGFloat
    var radius: CGFloat
    var color: NSColor
}

// MARK: - ParticleView

class ParticleView: NSView {

    // Toggle: true = CAEmitterLayer, false = Core Graphics manual particles
    var useEmitterLayer = false

    private var particles: [Particle] = []
    private let maxParticles = 300
    private let gravity: CGFloat = 200.0
    private let drag: CGFloat = 0.95

    // Combo state
    private var comboStreak: Int = 0
    private var comboLevel: Int = 0
    private var shakeOffset = CGPoint.zero

    // Glow state
    private var glowPosition: CGPoint? = nil
    private var glowAlpha: CGFloat = 0.0

    // Phrase state
    private var phraseText: String? = nil
    private var phraseTimer: CGFloat = 0.0

    // Emitter layer (GPU-accelerated alternative)
    private var emitterLayer: CAEmitterLayer?

    // Neon colors
    private let neonColors: [NSColor] = [
        NSColor(calibratedRed: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),       // cyan #00FFFF
        NSColor(calibratedRed: 1.0, green: 0.078, blue: 0.576, alpha: 1.0),    // pink #FF1493
        NSColor(calibratedRed: 0.749, green: 0.0, blue: 1.0, alpha: 1.0),      // purple #BF00FF
        NSColor(calibratedRed: 0.224, green: 1.0, blue: 0.078, alpha: 1.0),    // green #39FF14
    ]

    private let levelColors: [NSColor] = [
        NSColor(calibratedRed: 0.224, green: 1.0, blue: 0.078, alpha: 1.0),    // green
        NSColor(calibratedRed: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),        // cyan
        NSColor(calibratedRed: 1.0, green: 0.078, blue: 0.576, alpha: 1.0),    // pink
        NSColor(calibratedRed: 0.749, green: 0.0, blue: 1.0, alpha: 1.0),      // purple
        NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),        // red
    ]

    private let phrases = ["AWESOME!", "FANTASTIC!", "GODLIKE!", "UNSTOPPABLE!", "EPIC!", "BLAZING!"]

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = CGColor.clear

        if useEmitterLayer {
            setupEmitterLayer()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Public API

    func spawnParticles(at point: CGPoint, count: Int) {
        if useEmitterLayer {
            emitterLayer?.emitterPosition = point
            emitterLayer?.birthRate = Float(count) * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.emitterLayer?.birthRate = 0
            }
            return
        }

        let toSpawn = min(count, maxParticles - particles.count)
        for _ in 0..<toSpawn {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 80...250)
            let color = neonColors.randomElement()!
            let p = Particle(
                x: point.x,
                y: point.y,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                alpha: 1.0,
                lifetime: 0,
                maxLifetime: CGFloat.random(in: 0.4...1.2),
                radius: CGFloat.random(in: 2...5),
                color: color
            )
            particles.append(p)
        }
    }

    func updateCombo(streak: Int, level: Int) {
        comboStreak = streak
        comboLevel = level

        // Trigger phrase at milestones
        if streak > 0 && streak % 10 == 0 {
            phraseText = phrases.randomElement()
            phraseTimer = 1.5
        }
    }

    func updateGlow(at point: CGPoint) {
        glowPosition = point
        glowAlpha = 0.3
    }

    func update(dt: CGFloat) {
        // Update particles
        var alive: [Particle] = []
        for var p in particles {
            p.lifetime += dt
            if p.lifetime >= p.maxLifetime { continue }
            p.vy -= gravity * dt
            p.vx *= drag
            p.vy *= drag
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.alpha = max(0, 1.0 - (p.lifetime / p.maxLifetime))
            alive.append(p)
        }
        particles = alive

        // Fade glow
        if glowAlpha > 0 {
            glowAlpha -= dt * 0.5
            if glowAlpha < 0 { glowAlpha = 0 }
        }

        // Shake offset
        if comboStreak > 0 {
            let mag = CGFloat(comboLevel) * 2.0
            shakeOffset = CGPoint(
                x: CGFloat.random(in: -mag...mag),
                y: CGFloat.random(in: -mag...mag)
            )
        } else {
            shakeOffset = .zero
        }

        // Phrase timer
        if phraseTimer > 0 {
            phraseTimer -= dt
            if phraseTimer <= 0 {
                phraseText = nil
            }
        }
    }

    // MARK: - Drawing (Core Graphics)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        drawGlow(ctx: ctx)
        drawParticles(ctx: ctx)
        drawCombo(ctx: ctx)
    }

    private func drawParticles(ctx: CGContext) {
        for p in particles {
            let r = p.color.redComponent
            let g = p.color.greenComponent
            let b = p.color.blueComponent
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: p.alpha))
            let rect = CGRect(x: p.x - p.radius, y: p.y - p.radius,
                              width: p.radius * 2, height: p.radius * 2)
            ctx.fillEllipse(in: rect)
        }
    }

    private func drawGlow(ctx: CGContext) {
        guard let pos = glowPosition, glowAlpha > 0.01 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let levelIdx = min(comboLevel, levelColors.count - 1)
        let glowColor = levelColors[levelIdx]
        let r = glowColor.redComponent
        let g = glowColor.greenComponent
        let b = glowColor.blueComponent

        let colors: [CGFloat] = [r, g, b, glowAlpha, r, g, b, 0.0]
        let locations: [CGFloat] = [0.0, 1.0]

        guard let gradient = CGGradient(colorSpace: colorSpace, colorComponents: colors,
                                        locations: locations, count: 2) else { return }
        ctx.drawRadialGradient(gradient, startCenter: pos, startRadius: 0,
                               endCenter: pos, endRadius: 40,
                               options: .drawsAfterEndLocation)
    }

    private func drawCombo(ctx: CGContext) {
        guard comboStreak > 0 else { return }

        let levelIdx = min(comboLevel, levelColors.count - 1)
        let color = levelColors[levelIdx]

        // Position: top-right with shake
        let baseX = bounds.width - 180 + shakeOffset.x
        let baseY = bounds.height - 100 + shakeOffset.y

        // Title "COMBO"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: color.withAlphaComponent(0.8),
        ]
        let titleStr = NSAttributedString(string: "COMBO", attributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: baseX + 40, y: baseY + 50))

        // Number
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 48),
            .foregroundColor: color,
        ]
        let numStr = NSAttributedString(string: "\(comboStreak)", attributes: numAttrs)
        numStr.draw(at: NSPoint(x: baseX + 20, y: baseY))

        // Phrase
        if let phrase = phraseText, phraseTimer > 0 {
            let phraseAlpha = min(1.0, CGFloat(phraseTimer))
            let phraseAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: color.withAlphaComponent(phraseAlpha),
            ]
            let phraseStr = NSAttributedString(string: phrase, attributes: phraseAttrs)
            phraseStr.draw(at: NSPoint(x: baseX + 10, y: baseY - 30))
        }
    }

    // MARK: - CAEmitterLayer (GPU-accelerated alternative)

    private func setupEmitterLayer() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 1, height: 1)
        emitter.birthRate = 0

        let cells = neonColors.map { color -> CAEmitterCell in
            let cell = CAEmitterCell()
            cell.birthRate = 8
            cell.lifetime = 1.0
            cell.velocity = 150
            cell.velocityRange = 80
            cell.emissionRange = .pi * 2
            cell.scale = 0.05
            cell.scaleRange = 0.03
            cell.scaleSpeed = -0.02
            cell.alphaSpeed = -0.8
            cell.color = color.cgColor
            // Use a small white circle as content
            let size = CGSize(width: 12, height: 12)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            cell.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.yAcceleration = 200
            return cell
        }

        emitter.emitterCells = cells
        layer?.addSublayer(emitter)
        emitterLayer = emitter
    }
}
