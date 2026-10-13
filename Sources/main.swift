import AppKit
import QuartzCore

// MARK: - Helpers

@inline(__always) func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}

// Resolving a rounded-design font descriptor is surprisingly expensive, and this
// is called from the per-frame draw path (speech bubble, particle glyphs) — cache
// by exact (size, weight) so repeated frames at the same size are a dictionary hit.
private var roundedFontCache: [String: NSFont] = [:]

/// Time since the last keyboard, mouse, or scroll event, system-wide.
func secondsSinceUserInput() -> CFTimeInterval {
    let types: [CGEventType] = [
        .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
    ]
    return types.reduce(CFTimeInterval.greatestFiniteMagnitude) {
        min($0, CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $1))
    }
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight = .bold) -> NSFont {
    let key = "\(size)-\(weight.rawValue)"
    if let cached = roundedFontCache[key] { return cached }
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    let result = f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
    roundedFontCache[key] = result
    return result
}

extension CGPoint {
    static func + (a: CGPoint, b: CGVector) -> CGPoint { CGPoint(x: a.x + b.dx, y: a.y + b.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}

extension CGVector {
    var length: CGFloat { hypot(dx, dy) }
    static func * (v: CGVector, k: CGFloat) -> CGVector { CGVector(dx: v.dx * k, dy: v.dy * k) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Palette {
    static let fur = NSColor(hex: 0xF7A541)
    static let furDark = NSColor(hex: 0xE07F22)
    static let outline = NSColor(hex: 0x8A4A16)
    static let cream = NSColor(hex: 0xFFEBCD)
    static let pink = NSColor(hex: 0xFF9AA8)
    static let eye = NSColor(hex: 0x3A2618)
    static let mouth = NSColor(hex: 0x8B2B3A)
    static let yarn = NSColor(hex: 0xE8587A)
    static let yarnDark = NSColor(hex: 0xB93A5C)
    static let yarnLight = NSColor(hex: 0xFF9DB4)
    static let text = NSColor(hex: 0x5A3212)
}

// MARK: - Cat drawing

enum EyeStyle { case open, closed, happy, sleepy, surprised }
enum MouthStyle { case smile, open, flat }

struct CatPose {
    var time: Double = 0
    var eyes: EyeStyle = .open
    var mouth: MouthStyle = .smile
    var look = CGVector.zero      // -1...1, in the cat's local (possibly mirrored) space
    var pawRaise: CGFloat = 0     // 0 = resting, 1 = raised high
    var tailSwing: CGFloat = 0    // -1...1
    var earTwitch: CGFloat = 0    // 0...1
    var sleeping = false
}

/// Draws the cat in local units: ground at y = 0, centered on x = 0, ~210 units tall.
/// The raised paw is on +x and the tail on -x; callers mirror the context to face left.
enum CatRenderer {
    static let line: CGFloat = 4

    static func fillStroke(_ path: NSBezierPath, _ fill: NSColor, width: CGFloat = line) {
        fill.setFill(); path.fill()
        Palette.outline.setStroke(); path.lineWidth = width; path.stroke()
    }

    /// Local position of the right paw for a given raise amount.
    static func pawPoint(_ raise: CGFloat) -> CGPoint {
        P(lerp(22, 62, raise), lerp(8, 92, raise))
    }

    static func draw(_ p: CatPose, includeTail: Bool = true) {
        let breath = CGFloat(sin(p.time * (p.sleeping ? 1.6 : 3.0)))
        let hy: CGFloat = 122 + breath * (p.sleeping ? 2.5 : 1.5)

        if includeTail { drawTail(p.tailSwing) }

        // Body
        fillStroke(oval(0, 50, 118 + breath * 2, 100), Palette.fur)
        Palette.furDark.setStroke()
        for side: CGFloat in [-1, 1] {
            for y: CGFloat in [66, 50, 34] {
                let s = NSBezierPath()
                s.move(to: P(side * 54, y)); s.line(to: P(side * 42, y + 3))
                s.lineWidth = 5; s.lineCapStyle = .round; s.stroke()
            }
        }
        Palette.cream.setFill(); oval(0, 40, 46, 62).fill()

        // Ears + head
        drawEar(side: -1, hy: hy, twitch: 0)
        drawEar(side: 1, hy: hy, twitch: p.earTwitch)
        fillStroke(oval(0, hy, 144, 112), Palette.fur)

        // Forehead stripes
        Palette.furDark.setStroke()
        for (a, b) in [(P(-15, hy + 50), P(-10, hy + 37)), (P(0, hy + 54), P(0, hy + 39)), (P(15, hy + 50), P(10, hy + 37))] {
            let s = NSBezierPath(); s.move(to: a); s.line(to: b)
            s.lineWidth = 5.5; s.lineCapStyle = .round; s.stroke()
        }

        drawFace(p, hy: hy)

        // Front legs (drawn last so a raised paw is in front of the face)
        drawLeg(from: P(-28, 44), to: P(-22, 8), pads: 0)
        drawLeg(from: P(28, 44), to: pawPoint(p.pawRaise), pads: clamp((p.pawRaise - 0.4) / 0.4, 0, 1))
    }

    static func drawTail(_ swing: CGFloat) {
        let tail = NSBezierPath()
        let end = P(-92 + swing * 16, 100 - abs(swing) * 8)
        tail.move(to: P(-40, 22))
        tail.curve(to: end, controlPoint1: P(-104, 16), controlPoint2: P(-114 + swing * 22, 62))
        tail.lineCapStyle = .round
        Palette.outline.setStroke(); tail.lineWidth = 22; tail.stroke()
        Palette.fur.setStroke(); tail.lineWidth = 22 - 2 * line; tail.stroke()
        Palette.furDark.setFill(); oval(end.x, end.y, 14, 14).fill()
    }

    static func drawEar(side: CGFloat, hy: CGFloat, twitch: CGFloat) {
        let outer = NSBezierPath()
        outer.move(to: P(side * 64, hy + 18))
        outer.line(to: P(side * (54 + twitch * 8), hy + 84 - twitch * 10))
        outer.line(to: P(side * 12, hy + 50))
        outer.close()
        outer.lineJoinStyle = .round
        fillStroke(outer, Palette.fur)

        let inner = NSBezierPath()
        inner.move(to: P(side * 52, hy + 34))
        inner.line(to: P(side * (50 + twitch * 7), hy + 72 - twitch * 9))
        inner.line(to: P(side * 27, hy + 50))
        inner.close()
        Palette.pink.setFill(); inner.fill()
    }

    static func drawLeg(from shoulder: CGPoint, to paw: CGPoint, pads: CGFloat) {
        let leg = NSBezierPath()
        leg.move(to: shoulder); leg.line(to: paw)
        leg.lineCapStyle = .round
        Palette.outline.setStroke(); leg.lineWidth = 24; leg.stroke()
        Palette.fur.setStroke(); leg.lineWidth = 24 - 2 * line; leg.stroke()
        // Hide the outline cap where the leg joins the body.
        Palette.fur.setFill(); oval(shoulder.x, shoulder.y, 24, 24).fill()

        fillStroke(oval(paw.x, paw.y, 32, 22), Palette.cream, width: 3.5)
        if pads > 0 {
            Palette.pink.withAlphaComponent(pads).setFill()
            oval(paw.x, paw.y - 2, 12, 8).fill()
            for dx: CGFloat in [-8, 0, 8] { oval(paw.x + dx, paw.y + (dx == 0 ? 7 : 5), 5, 5).fill() }
        } else {
            Palette.outline.setStroke()
            for dx: CGFloat in [-5, 5] {
                let t = NSBezierPath(); t.move(to: P(paw.x + dx, paw.y - 8)); t.line(to: P(paw.x + dx, paw.y - 2))
                t.lineWidth = 2; t.lineCapStyle = .round; t.stroke()
            }
        }
    }

    static func drawFace(_ p: CatPose, hy: CGFloat) {
        for side: CGFloat in [-1, 1] { drawEye(side * 30, hy + 4, p.eyes, p.look) }

        Palette.pink.withAlphaComponent(0.55).setFill()
        oval(-48, hy - 16, 24, 13).fill(); oval(48, hy - 16, 24, 13).fill()

        let nose = NSBezierPath()
        nose.move(to: P(-7, hy - 6)); nose.line(to: P(7, hy - 6)); nose.line(to: P(0, hy - 13)); nose.close()
        nose.lineJoinStyle = .round
        Palette.pink.setFill(); nose.fill()
        Palette.pink.setStroke(); nose.lineWidth = 3; nose.stroke()

        Palette.outline.setStroke()
        switch p.mouth {
        case .smile:
            let m = NSBezierPath()
            m.move(to: P(0, hy - 13)); m.line(to: P(0, hy - 17))
            m.move(to: P(-11, hy - 17))
            m.curve(to: P(0, hy - 17), controlPoint1: P(-10, hy - 25), controlPoint2: P(-1, hy - 25))
            m.curve(to: P(11, hy - 17), controlPoint1: P(1, hy - 25), controlPoint2: P(10, hy - 25))
            m.lineWidth = 2.8; m.lineCapStyle = .round; m.stroke()
        case .open:
            let m = oval(0, hy - 24, 15, 15)
            Palette.mouth.setFill(); m.fill()
            Palette.pink.setFill(); oval(0, hy - 28, 9, 6).fill()
            m.lineWidth = 2.5; m.stroke()
        case .flat:
            let m = NSBezierPath()
            m.move(to: P(-6, hy - 19)); m.curve(to: P(6, hy - 19), controlPoint1: P(-2, hy - 22), controlPoint2: P(2, hy - 22))
            m.lineWidth = 2.5; m.lineCapStyle = .round; m.stroke()
        }

        Palette.outline.withAlphaComponent(0.6).setStroke()
        for side: CGFloat in [-1, 1] {
            for (y0, y1) in [(hy - 6, hy), (hy - 12, hy - 13), (hy - 18, hy - 26)] {
                let w = NSBezierPath(); w.move(to: P(side * 54, y0)); w.line(to: P(side * 84, y1))
                w.lineWidth = 2; w.lineCapStyle = .round; w.stroke()
            }
        }
    }

    static func drawEye(_ cx: CGFloat, _ cy: CGFloat, _ style: EyeStyle, _ look: CGVector) {
        func arc(_ dy0: CGFloat, _ dyC: CGFloat) {
            let a = NSBezierPath()
            a.move(to: P(cx - 10, cy + dy0))
            a.curve(to: P(cx + 10, cy + dy0), controlPoint1: P(cx - 6, cy + dyC), controlPoint2: P(cx + 6, cy + dyC))
            Palette.eye.setStroke(); a.lineWidth = 3.8; a.lineCapStyle = .round; a.stroke()
        }
        switch style {
        case .open:
            let x = cx + look.dx * 5, y = cy + look.dy * 4
            Palette.eye.setFill(); oval(x, y, 17, 23).fill()
            NSColor.white.setFill(); oval(x + 3.5, y + 5, 7, 8).fill(); oval(x - 3.5, y - 5.5, 3.5, 3.5).fill()
        case .surprised:
            let o = oval(cx, cy, 24, 27)
            NSColor.white.setFill(); o.fill()
            Palette.outline.setStroke(); o.lineWidth = 2.5; o.stroke()
            let x = cx + look.dx * 4, y = cy + look.dy * 4
            Palette.eye.setFill(); oval(x, y, 11, 12).fill()
            NSColor.white.setFill(); oval(x + 2, y + 2.5, 3.5, 3.5).fill()
        case .closed: arc(-1, -7)
        case .sleepy: arc(-2, -6)
        case .happy: arc(-4, 9)
        }
    }

    static func drawBall(at c: CGPoint, radius r: CGFloat, angle: CGFloat, scale: CGFloat = 1, highlight: Bool = true) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.saveGState()
        ctx.rotate(by: angle)

        let thread = NSBezierPath()
        thread.move(to: P(r * 0.6, -r * 0.75))
        thread.curve(to: P(r * 1.55, -r * 1.2), controlPoint1: P(r * 1.1, -r * 0.7), controlPoint2: P(r * 1.15, -r * 1.45))
        thread.curve(to: P(r * 1.9, -r * 0.8), controlPoint1: P(r * 1.85, -r * 1.05), controlPoint2: P(r * 2.0, -r * 0.95))
        Palette.yarnDark.setStroke(); thread.lineWidth = 2.5; thread.lineCapStyle = .round; thread.stroke()

        let body = oval(0, 0, r * 2, r * 2)
        Palette.yarn.setFill(); body.fill()
        ctx.saveGState()
        body.addClip()
        Palette.yarnLight.setStroke()
        for i in 0..<3 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(i) * .pi / 3 + 0.3)
            let s = oval(0, 0, r * 2.1, r * 0.9); s.lineWidth = 2; s.stroke()
            ctx.restoreGState()
        }
        ctx.rotate(by: -0.8)
        let s = oval(r * 0.25, r * 0.15, r * 1.3, r * 0.5); s.lineWidth = 1.6; s.stroke()
        ctx.restoreGState()
        Palette.yarnDark.setStroke(); body.lineWidth = 2.5; body.stroke()
        ctx.restoreGState()

        if highlight {
            NSColor.white.withAlphaComponent(0.45).setFill()
            oval(-r * 0.35, r * 0.42, r * 0.55, r * 0.32).fill()
        }
        ctx.restoreGState()
    }
}

// MARK: - Game state

final class Ball {
    enum State { case none, held, flying, resting, returning }
    var state: State = .none
    var pos = CGPoint.zero
    var vel = CGVector.zero
    var angle: CGFloat = 0
    var spin: CGFloat = 0
    var returnFrom = CGPoint.zero
    var returnStart: Double = 0
    var returnDuration: Double = 0.6
    var restSince: Double = 0
    var nagLevel = 0
    var appearedAt: Double = 0
    var visible: Bool { state != .none }
}

struct Particle {
    var pos: CGPoint
    var vel: CGVector
    var born: Double
    var life: Double
    var glyph: String
    var color: NSColor
    var size: CGFloat
    var layer: CALayer? = nil
}

final class GameView: NSView {
    enum Target { case nothing, cat, ball }

    // Tuning
    let catScale: CGFloat = 0.72
    let ballR: CGFloat = 15
    let ballGravity: CGFloat = 2000
    let catGravity: CGFloat = 2400

    weak var hostWindow: NSWindow?
    var playArea = CGRect.zero          // screen's visible frame, in view coordinates
    var soundOn = true

    // Cat
    var catPos = CGPoint.zero           // bottom-center
    var catVy: CGFloat = 0
    var catAirborne = false
    var facing: CGFloat = -1
    var pose = CatPose()

    // Timeline
    var now = CACurrentMediaTime()
    var timer: Timer?
    var happyUntil = 0.0, surprisedUntil = 0.0, meowUntil = 0.0
    var blinkUntil = 0.0, nextBlink = 0.0
    var earTwitchStart = -10.0, nextEarTwitch = 0.0
    var jumpStart: Double?, jumpHeight: CGFloat = 16
    var landStart: Double?
    var throwStart: Double?, throwReleased = false, throwPower: CGFloat = 1
    var pendingThrowAt: Double?
    var sleeping = false, nextZ = 0.0
    var lastInteraction = CACurrentMediaTime()
    var recentPets: [Double] = []
    var combo = 0

    // Speech bubble
    var bubbleText: String?
    var bubbleStart = 0.0, bubbleUntil = 0.0

    // Daytime eye-rest reminder. Active computer use between 09:00 and 20:00.
    var restReminderOn = UserDefaults.standard.object(forKey: "restReminderEnabled") as? Bool ?? true
    var activeUse: Double = 0
    var remindAfter: Double = 60 * 60
    var restBubble = false
    var restShownAt = 0.0
    var restButtonDown = false
    var restHit = CGRect.zero
    var restButtonRect = CGRect.zero
    let restFirstUse: Double = 60 * 60
    let restRepeatUse: Double = 30 * 60

    // Input
    var pressed: Target = .nothing
    var mouseDownPoint = CGPoint.zero
    var dragOffset = CGVector.zero
    var dragging = false
    var mouse = CGPoint(x: -9999, y: -9999)

    let ball = Ball()
    var particles: [Particle] = []
    var sounds: [String: NSSound] = [:]

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Rendering is done entirely with sublayers; see the Rendering section.
        wantsLayer = true
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Setup

    func layout(for screen: NSScreen) {
        guard let window = hostWindow else { return }
        window.setFrame(screen.frame, display: true)
        frame = CGRect(origin: .zero, size: screen.frame.size)
        playArea = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        if catPos == .zero {
            resetPosition()
        } else {
            catPos.x = clamp(catPos.x, playArea.minX + 80, playArea.maxX - 80)
            catPos.y = max(playArea.minY, min(catPos.y, playArea.maxY - 220 * catScale))
            catAirborne = catPos.y > playArea.minY
        }
        if ball.state == .flying || ball.state == .resting {
            ball.pos.x = clamp(ball.pos.x, playArea.minX + ballR, playArea.maxX - ballR)
            ball.pos.y = max(ball.pos.y, playArea.minY + ballR)
            ball.state = .flying
        }
        rebuildStaticImages()
        render()
    }

    func resetPosition() {
        catPos = CGPoint(x: playArea.maxX - 150, y: playArea.minY)
        catAirborne = false
        catVy = 0
    }

    func start() {
        now = CACurrentMediaTime()
        nextBlink = now + 2
        nextEarTwitch = now + 4
        say("喵~ 点我一起玩！", duration: 3)
        scheduleTick(after: 1.0 / 60.0)
    }

    // MARK: Main loop

    /// Runs at a full 60fps while anything is actually moving on screen, and
    /// drops to a cheap idle rate while the cat is asleep — a sleeping cat only
    /// has its slow breathing + the occasional drifting "z" to animate, so it
    /// doesn't need 60 redraws/sec. (The only particles that can exist while
    /// sleeping are those drifting z's — hearts/stars/notes all come from
    /// play events that wake the cat via wake(), so no need to check for them.)
    var isFullyIdle: Bool {
        !restBubble && sleeping && !dragging && !catAirborne
            && ball.state == .none
            && jumpStart == nil && landStart == nil && throwStart == nil
            && now >= bubbleUntil
            && now >= happyUntil && now >= surprisedUntil && now >= meowUntil
    }

    /// Fast motion that looks choppy below 60fps; everything else (breathing,
    /// tail sway, blinking) is smooth enough at 30.
    var needsFullRate: Bool {
        dragging || catAirborne || jumpStart != nil || landStart != nil || throwStart != nil
            || ball.state == .flying || ball.state == .returning || !particles.isEmpty
    }

    func scheduleTick(after interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func tick() {
        let t = CACurrentMediaTime()
        let elapsed = t - now
        let dt = CGFloat(min(elapsed, 1.0 / 20.0))
        now = t
        if let w = hostWindow {
            let m = NSEvent.mouseLocation
            mouse = CGPoint(x: m.x - w.frame.minX, y: m.y - w.frame.minY)
        }
        updateCat(dt)
        updatePose(dt)
        updateBall(dt)
        updateBehavior()
        updateRestReminder(elapsed)
        updateParticles(dt)
        updatePassThrough()
        render()
        scheduleTick(after: isFullyIdle ? 1.0 / 15.0 : needsFullRate ? 1.0 / 60.0 : 1.0 / 30.0)
    }

    var jumpOffset: CGFloat {
        guard let js = jumpStart else { return 0 }
        let e = now - js
        return e > 0.38 ? 0 : jumpHeight * CGFloat(sin(.pi * e / 0.38))
    }

    var headCenter: CGPoint { CGPoint(x: catPos.x, y: catPos.y + jumpOffset + 125 * catScale) }
    var headTop: CGFloat { catPos.y + jumpOffset + 210 * catScale }

    func updateCat(_ dt: CGFloat) {
        if let js = jumpStart, now - js > 0.38 { jumpStart = nil }
        if let ls = landStart, now - ls > 0.35 { landStart = nil }

        if !dragging && catAirborne {
            catVy -= catGravity * dt
            catPos.y += catVy * dt
            if catPos.y <= playArea.minY {
                let hard = catVy < -900
                catPos.y = playArea.minY
                catAirborne = false
                catVy = 0
                landStart = now
                if hard { say("稳稳落地！"); spawn("✦", color: NSColor(hex: 0xFFC93C), at: catPos, count: 5, speed: 60...140, size: 14, life: 0.6) }
            }
        }
        if now > nextBlink {
            blinkUntil = now + 0.14
            nextBlink = now + Double.random(in: 2.0...5.0)
        }
        if now > nextEarTwitch {
            earTwitchStart = now
            nextEarTwitch = now + Double.random(in: 4.0...9.0)
        }
    }

    func updatePose(_ dt: CGFloat) {
        pose.time = now
        pose.sleeping = sleeping

        if sleeping { pose.eyes = .sleepy }
        else if dragging || now < surprisedUntil { pose.eyes = .surprised }
        else if now < happyUntil { pose.eyes = .happy }
        else if now < blinkUntil { pose.eyes = .closed }
        else { pose.eyes = .open }

        if sleeping { pose.mouth = .flat }
        else if dragging || now < meowUntil { pose.mouth = .open }
        else { pose.mouth = .smile }

        if sleeping { pose.tailSwing = CGFloat(sin(now * 0.8)) * 0.2 }
        else if dragging { pose.tailSwing = CGFloat(sin(now * 14)) }
        else if now < happyUntil { pose.tailSwing = CGFloat(sin(now * 9)) * 0.9 }
        else { pose.tailSwing = CGFloat(sin(now * 2.2)) * 0.6 }

        let e = now - earTwitchStart
        pose.earTwitch = e < 0.25 ? CGFloat(sin(e / 0.25 * .pi)) : 0

        // Eyes follow the ball while it's in play, otherwise the cursor when it's nearby.
        var target = CGVector.zero
        let head = headCenter
        if ball.state == .flying || ball.state == .resting || ball.state == .returning {
            let d = ball.pos - head
            target = CGVector(dx: clamp(d.dx / 220, -1, 1), dy: clamp(d.dy / 220, -1, 1))
        } else {
            let d = mouse - head
            if d.length < 500 { target = CGVector(dx: clamp(d.dx / 220, -1, 1), dy: clamp(d.dy / 220, -1, 1)) }
        }
        target.dx *= facing
        let k = min(1, dt * 10)
        pose.look = CGVector(dx: lerp(pose.look.dx, target.dx, k), dy: lerp(pose.look.dy, target.dy, k))

        var pawTarget: CGFloat = 0
        if ball.state == .held { pawTarget = 0.62 }
        if let ts = throwStart { pawTarget = now - ts < 0.28 ? 1 : 0 }
        if ball.state == .returning, returnProgress > 0.45 { pawTarget = 1 }
        pose.pawRaise = lerp(pose.pawRaise, pawTarget, min(1, dt * 14))
    }

    var squash: CGFloat {
        if dragging { return -0.06 }
        if let ls = landStart { return 0.18 * CGFloat(sin(.pi * (now - ls) / 0.35)) }
        return 0
    }

    func pawWorld(_ raise: CGFloat) -> CGPoint {
        let p = CatRenderer.pawPoint(raise)
        return CGPoint(x: catPos.x + facing * catScale * p.x, y: catPos.y + jumpOffset + catScale * p.y)
    }

    func heldBallPoint(_ raise: CGFloat) -> CGPoint {
        pawWorld(quantizedPawRaise(raise)) + CGVector(dx: 0, dy: 10 * catScale + ballR * 0.85)
    }

    var returnProgress: CGFloat {
        CGFloat(clamp((now - ball.returnStart) / ball.returnDuration, 0, 1))
    }

    func updateBall(_ dt: CGFloat) {
        switch ball.state {
        case .none:
            break
        case .held:
            ball.pos = heldBallPoint(pose.pawRaise)
        case .resting:
            break
        case .returning:
            let t = returnProgress
            let to = heldBallPoint(1)
            let from = ball.returnFrom
            let lift = max(90, abs(to.x - from.x) * 0.35)
            let ctrl = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + lift)
            let u = 1 - t
            ball.pos = CGPoint(x: u * u * from.x + 2 * u * t * ctrl.x + t * t * to.x,
                               y: u * u * from.y + 2 * u * t * ctrl.y + t * t * to.y)
            ball.angle += dt * 14
            if t >= 1 { catchBall() }
        case .flying:
            let floor = playArea.minY + ballR
            ball.vel.dy -= ballGravity * dt
            ball.pos = ball.pos + ball.vel * dt
            var onFloor = false
            if ball.pos.y <= floor {
                ball.pos.y = floor
                onFloor = true
                if ball.vel.dy < -140 {
                    if ball.vel.dy < -500 { play("Pop", volume: Float(min(0.35, -ball.vel.dy / 3000))) }
                    ball.vel.dy *= -0.5
                    ball.vel.dx *= 0.85
                } else {
                    ball.vel.dy = 0
                }
            }
            if ball.pos.x < playArea.minX + ballR {
                ball.pos.x = playArea.minX + ballR; ball.vel.dx = abs(ball.vel.dx) * 0.7
            } else if ball.pos.x > playArea.maxX - ballR {
                ball.pos.x = playArea.maxX - ballR; ball.vel.dx = -abs(ball.vel.dx) * 0.7
            }
            if ball.pos.y > playArea.maxY - ballR {
                ball.pos.y = playArea.maxY - ballR; ball.vel.dy = -abs(ball.vel.dy) * 0.5
            }
            if onFloor && ball.vel.dy == 0 {
                ball.vel.dx *= CGFloat(exp(-1.6 * Double(dt)))
                ball.angle -= ball.vel.dx * dt / ballR
                if abs(ball.vel.dx) < 10 {
                    ball.vel = .zero
                    ball.state = .resting
                    ball.restSince = now
                    ball.nagLevel = 0
                }
            } else {
                ball.angle += ball.spin * dt
            }
        }
    }

    func updateBehavior() {
        if let pt = pendingThrowAt, now >= pt {
            if dragging { pendingThrowAt = now + 0.5 } else { pendingThrowAt = nil; startThrow() }
        }
        if let ts = throwStart {
            if !throwReleased && now - ts >= 0.28 { releaseBall(); throwReleased = true }
            if now - ts > 0.6 { throwStart = nil }
        }
        if ball.state == .resting {
            let e = now - ball.restSince
            if ball.nagLevel == 0 && e > 7 {
                ball.nagLevel = 1
                meowUntil = now + 0.4
                say(["喵？把球丢回来嘛~", "球球！点一下毛线球~", "喵喵！快丢回来！"].randomElement()!)
                play("Purr", volume: 0.3)
            } else if ball.nagLevel == 1 && e > 20 {
                ball.nagLevel = 2
                if combo > 0 { combo = 0 }
                say("喵呜…不陪我玩了吗？")
            }
        }

        let busy = ball.state == .flying || ball.state == .returning || ball.state == .held
            || throwStart != nil || pendingThrowAt != nil || dragging || catAirborne
        if !sleeping && !busy && now - lastInteraction > 45 {
            sleeping = true
            nextZ = now
            say("好困…", duration: 1.5)
        }
        if sleeping && now >= nextZ {
            nextZ = now + 1.3
            let p = CGPoint(x: catPos.x + facing * 40 * catScale, y: headTop - 10)
            particles.append(Particle(pos: p, vel: CGVector(dx: facing * 22, dy: 32), born: now, life: 2.4,
                                      glyph: Bool.random() ? "z" : "Z", color: NSColor(hex: 0x8C7BB5),
                                      size: CGFloat.random(in: 13...20)))
        }
    }

    func updateParticles(_ dt: CGFloat) {
        for p in particles where now - p.born > p.life { p.layer?.removeFromSuperlayer() }
        particles.removeAll { now - $0.born > $0.life }
        for i in particles.indices {
            particles[i].pos = particles[i].pos + particles[i].vel * dt
            particles[i].vel = particles[i].vel * CGFloat(exp(-1.5 * Double(dt)))
        }
    }

    /// The overlay covers the whole screen, so only accept clicks while the cursor is over the cat, the ball, or the rest reminder.
    func updatePassThrough() {
        guard let w = hostWindow else { return }
        if let layout = restLayout() {
            restHit = layout.hit
            restButtonRect = layout.button
        } else {
            restHit = .zero
            restButtonRect = .zero
        }
        let overRest = restBubble && restHit.contains(mouse)
        let interactive = dragging || pressed != .nothing || restButtonDown || overRest || hitBall(mouse) || hitCat(mouse)
        if w.ignoresMouseEvents == interactive { w.ignoresMouseEvents = !interactive }
    }

    func isRestHours(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 9 && hour < 20
    }

    /// Pauses while the user is away, resets after a 5-minute break, and prompts after 1 hour of use (then every 30 minutes).
    func updateRestReminder(_ elapsed: Double) {
        guard restReminderOn, isRestHours() else {
            if restBubble { restBubble = false }
            activeUse = 0
            remindAfter = restFirstUse
            return
        }
        let idle = secondsSinceUserInput()
        if idle >= 5 * 60 {
            restBubble = false
            restButtonDown = false
            activeUse = 0
            remindAfter = restFirstUse
            return
        }
        if restBubble {
            lastInteraction = now
            return
        }
        guard idle <= 90 else { return }
        activeUse += elapsed
        if activeUse >= remindAfter { showRestReminder() }
    }

    func showRestReminder() {
        guard !restBubble else { return }
        restBubble = true
        restShownAt = now
        restButtonDown = false
        bubbleUntil = now
        if sleeping { sleeping = false }
        lastInteraction = now
        surprisedUntil = now + 0.8
        meowUntil = now + 0.4
        play("Glass", volume: 0.4)
    }

    func acknowledgeRestReminder() {
        restBubble = false
        restButtonDown = false
        bubbleKey = ""
        activeUse = 0
        remindAfter = restRepeatUse
    }

    func setRestReminderOn(_ on: Bool) {
        restReminderOn = on
        UserDefaults.standard.set(on, forKey: "restReminderEnabled")
        if !on {
            restBubble = false
            restButtonDown = false
            activeUse = 0
            remindAfter = restFirstUse
            bubbleKey = ""
        }
        scheduleTick(after: 0)
    }

    // MARK: Actions

    func say(_ text: String, duration: Double? = nil) {
        bubbleText = text
        bubbleStart = now
        bubbleUntil = now + (duration ?? max(1.6, Double(text.count) * 0.12 + 1.1))
    }

    func play(_ name: String, volume: Float = 0.5) {
        guard soundOn else { return }
        let s = sounds[name] ?? NSSound(named: NSSound.Name(name))
        guard let sound = s else { return }
        sounds[name] = sound
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    func jump(_ height: CGFloat = 16) {
        guard !dragging && !catAirborne && jumpStart == nil else { return }
        jumpHeight = height
        jumpStart = now
    }

    func spawn(_ glyph: String, color: NSColor, at p: CGPoint, count: Int, speed: ClosedRange<CGFloat>,
               upward: Bool = false, size: CGFloat, life: Double) {
        for _ in 0..<count {
            let a = upward ? CGFloat.random(in: 1.1...2.0) : CGFloat.random(in: 0...(2 * .pi))
            let v = CGFloat.random(in: speed)
            particles.append(Particle(pos: p, vel: CGVector(dx: cos(a) * v, dy: sin(a) * v), born: now,
                                      life: life * Double.random(in: 0.8...1.2), glyph: glyph, color: color,
                                      size: size * CGFloat.random(in: 0.8...1.2)))
        }
    }

    func spawnHearts(_ n: Int) {
        spawn("♥", color: NSColor(hex: 0xFF6F91), at: CGPoint(x: catPos.x, y: headTop - 10), count: n,
              speed: 70...130, upward: true, size: 18, life: 1.2)
    }

    func wake(_ text: String) {
        sleeping = false
        surprisedUntil = now + 0.7
        meowUntil = now + 0.4
        say(text)
        play("Bottle", volume: 0.4)
    }

    func clickCat() {
        lastInteraction = now
        if sleeping { wake("喵！？"); return }

        recentPets = recentPets.filter { now - $0 < 2.5 } + [now]
        happyUntil = now + 1.1
        meowUntil = now + 0.35
        jump()
        play("Purr", volume: 0.5)

        if recentPets.count >= 5 {
            recentPets.removeAll()
            spawnHearts(8)
            say("呼噜呼噜~ 好舒服~")
            return
        }
        spawnHearts(3)

        switch ball.state {
        case .none:
            say("喵~ 一起玩毛线球吧！")
            pendingThrowAt = now + 0.9
        case .flying, .resting:
            say(["球在那边！丢回来给我~", "快点快点~ 点毛线球！", "喵！那个球！"].randomElement()!)
        case .held:
            say(["嘿嘿~", "准备好了吗？", "喵呜~"].randomElement()!)
            pendingThrowAt = min(pendingThrowAt ?? now + 0.4, now + 0.4)
        case .returning:
            break
        }
    }

    func startThrow() {
        guard throwStart == nil else { return }
        switch ball.state {
        case .none:
            ball.state = .held
            ball.appearedAt = now
            ball.pos = heldBallPoint(pose.pawRaise)
        case .held:
            break
        default:
            return
        }
        sleeping = false

        let leftSpace = catPos.x - playArea.minX
        let rightSpace = playArea.maxX - catPos.x
        var dir: CGFloat = leftSpace > rightSpace ? -1 : 1
        if min(leftSpace, rightSpace) > 350 && Double.random(in: 0...1) < 0.3 { dir = -dir }
        facing = dir

        if Double.random(in: 0...1) < 0.2 {
            throwPower = 1.35
            say("看我大力丢！")
        } else {
            throwPower = CGFloat.random(in: 0.7...1.05)
        }
        throwStart = now
        throwReleased = false
    }

    func releaseBall() {
        guard ball.state == .held else { return }
        ball.pos = heldBallPoint(pose.pawRaise)
        ball.state = .flying
        let span = max(120, (facing < 0 ? catPos.x - playArea.minX : playArea.maxX - catPos.x) - 60)
        let vy = CGFloat.random(in: 650...950) * (0.8 + 0.3 * throwPower)
        let flight = 2 * vy / ballGravity
        let dist = span * CGFloat.random(in: 0.3...0.65) * throwPower
        ball.vel = CGVector(dx: facing * dist / flight, dy: vy)
        ball.spin = -facing * 9
        meowUntil = now + 0.3
        play("Pop", volume: 0.6)
    }

    func clickBall() {
        guard ball.state == .flying || ball.state == .resting else { return }
        lastInteraction = now
        ball.returnFrom = ball.pos
        ball.returnStart = now
        let d = (heldBallPoint(1) - ball.pos).length
        ball.returnDuration = Double(clamp(d / 1300, 0.4, 0.95))
        ball.state = .returning
        ball.nagLevel = 0
        if !dragging { facing = ball.pos.x < catPos.x ? -1 : 1 }
        if sleeping { wake("喵！？球！") } else { surprisedUntil = now + 0.3 }
        spawn("✦", color: NSColor(hex: 0xFFC93C), at: ball.pos, count: 4, speed: 50...110, size: 12, life: 0.5)
        play("Tink", volume: 0.4)
    }

    func catchBall() {
        ball.state = .held
        combo += 1
        happyUntil = now + 1.0
        meowUntil = now + 0.4
        jump(20)
        lastInteraction = now
        spawn("✦", color: NSColor(hex: 0xFFC93C), at: ball.pos, count: 6, speed: 80...160, size: 14, life: 0.6)
        play("Tink", volume: 0.5)

        if combo % 10 == 0 {
            say("连续接住 \(combo) 次！你是最棒的铲屎官！", duration: 2.6)
            spawnHearts(10)
        } else if combo % 5 == 0 {
            say("\(combo) 连击！喵喵喵！")
            spawn("♪", color: NSColor(hex: 0x6FA8FF), at: CGPoint(x: catPos.x, y: headTop), count: 4,
                  speed: 60...110, upward: true, size: 18, life: 1.2)
        } else {
            say(["接住啦！", "喵~ 再来一次！", "好玩好玩！", "嘿！看我的！", "喵呜~", "再丢远一点！"].randomElement()!)
        }
        pendingThrowAt = now + Double.random(in: 1.0...1.6)
    }

    // Menu bar actions
    func menuThrow() {
        lastInteraction = now
        if sleeping { wake("喵？") }
        switch ball.state {
        case .none: startThrow()
        case .held: pendingThrowAt = now
        case .flying, .resting: clickBall()
        case .returning: break
        }
        scheduleTick(after: 0)
    }

    func toggleSleep() {
        if sleeping {
            lastInteraction = now
            wake("喵~ 睡醒啦")
        } else if ball.state == .none || ball.state == .resting {
            lastInteraction = now - 1000
        }
        scheduleTick(after: 0)
    }

    func menuResetPosition() {
        dragging = false
        resetPosition()
        lastInteraction = now
        scheduleTick(after: 0)
    }

    // MARK: Input

    func hitCat(_ p: CGPoint) -> Bool {
        let s = catScale
        return CGRect(x: catPos.x - 72 * s, y: catPos.y + jumpOffset, width: 144 * s, height: 205 * s).contains(p)
    }

    func hitBall(_ p: CGPoint) -> Bool {
        guard ball.state == .flying || ball.state == .resting else { return false }
        return (p - ball.pos).length < ballR + (ball.state == .flying ? 22 : 12)
    }

    override func mouseDown(with event: NSEvent) {
        scheduleTick(after: 0)  // guarantee a full-rate tick picks up whatever this click triggers
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        mouseDownPoint = p
        if restBubble && restHit.contains(p) {
            pressed = .nothing
            restButtonDown = restButtonRect.contains(p)
            render()
            return
        }
        if hitBall(p) {
            pressed = .ball
            clickBall()
        } else if hitCat(p) {
            pressed = .cat
            dragOffset = p - catPos
        } else {
            pressed = .nothing
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if restButtonDown {
            mouse = convert(event.locationInWindow, from: nil)
            render()
            return
        }
        guard pressed == .cat else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !dragging {
            guard (p - mouseDownPoint).length > 4 else { return }
            dragging = true
            catAirborne = false
            catVy = 0
            jumpStart = nil
            sleeping = false
            lastInteraction = now
            say(["喵呜！放我下来~", "哇啊啊~", "要去哪里呀？"].randomElement()!)
            play("Purr", volume: 0.3)
        }
        catPos = CGPoint(x: clamp(p.x - dragOffset.dx, playArea.minX + 40, playArea.maxX - 40),
                         y: clamp(p.y - dragOffset.dy, playArea.minY, playArea.maxY - 200 * catScale))
        render()  // mouseDragged fires at display-link rate, independent of our throttled timer
    }

    override func mouseUp(with event: NSEvent) {
        if restButtonDown {
            let p = convert(event.locationInWindow, from: nil)
            restButtonDown = false
            if restButtonRect.contains(p) { acknowledgeRestReminder() }
            scheduleTick(after: 0)
            return
        }
        defer { pressed = .nothing }
        guard pressed == .cat else { return }
        if dragging {
            dragging = false
            catAirborne = catPos.y > playArea.minY + 0.5
            catVy = 0
            lastInteraction = now
        } else {
            clickCat()
        }
        scheduleTick(after: 0)
    }


    // MARK: Rendering
    //
    // Everything on screen is a Core Animation layer. Bitmaps are only re-rendered
    // when the cat's *appearance* changes (eyes, mouth, paw, ears); continuous motion —
    // position, jump, squash, breathing, tail sway, ball spin — is just layer transforms,
    // which the GPU composites for almost nothing. Redrawing the vector cat every frame
    // was what kept CPU at 10–25%.

    /// Cat image bounds in CatRenderer's local units (ground-center at the origin).
    static let catLocal = CGRect(x: -135, y: -12, width: 270, height: 232)
    static let tailRoot = CGPoint(x: -40, y: 22)

    let shadowLayer = CAShapeLayer()
    let catRoot = CALayer()
    let tailLayer = CALayer()
    let bodyLayer = CALayer()
    let ballShadowLayer = CAShapeLayer()
    let ballLayer = CALayer()
    let ballGloss = CAShapeLayer()
    let bubbleLayer = CALayer()
    var layersReady = false
    var bodyKey = ""
    var bubbleKey = ""
    var catImageCache: [String: CGImage] = [:]
    var catImageOrder: [String] = []  // least recently used first; each image is ~0.5MB, so keep it small
    var glyphCache: [String: CGImage] = [:]
    var cachedBubble: (start: Double, str: NSAttributedString, size: NSSize)?

    var backingScale: CGFloat { hostWindow?.backingScaleFactor ?? 2 }
    var ballExtent: CGFloat { ballR * 2.1 + 4 }

    /// The paw is rendered in 12 discrete positions so its bitmap can be cached.
    func quantizedPawRaise(_ r: CGFloat) -> CGFloat { (r * 12).rounded() / 12 }

    /// Renders AppKit drawing code into a bitmap of `size` points at screen resolution.
    func makeImage(size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        let scale = backingScale
        guard let ctx = CGContext(data: nil, width: max(1, Int(ceil(size.width * scale))),
                                  height: max(1, Int(ceil(size.height * scale))), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    func setupLayers() {
        guard !layersReady, let root = layer else { return }
        layersReady = true
        let s = catScale, local = Self.catLocal
        let catBounds = CGRect(x: 0, y: 0, width: local.width * s, height: local.height * s)
        let groundAnchor = CGPoint(x: -local.minX / local.width, y: -local.minY / local.height)

        shadowLayer.path = CGPath(ellipseIn: CGRect(x: -65 * s, y: -7 * s, width: 130 * s, height: 14 * s), transform: nil)
        ballShadowLayer.path = CGPath(ellipseIn: CGRect(x: -ballR, y: -3, width: 2 * ballR, height: 6), transform: nil)
        ballGloss.path = CGPath(ellipseIn: CGRect(x: -0.275 * ballR, y: -0.16 * ballR, width: 0.55 * ballR, height: 0.32 * ballR), transform: nil)
        shadowLayer.fillColor = NSColor.black.cgColor
        ballShadowLayer.fillColor = NSColor.black.cgColor
        ballGloss.fillColor = NSColor.white.withAlphaComponent(0.45).cgColor

        catRoot.bounds = catBounds
        catRoot.anchorPoint = groundAnchor
        bodyLayer.bounds = catBounds
        bodyLayer.anchorPoint = groundAnchor
        bodyLayer.position = CGPoint(x: -local.minX * s, y: -local.minY * s)
        // The tail swings by rotating around its root instead of being redrawn.
        tailLayer.bounds = catBounds
        tailLayer.anchorPoint = CGPoint(x: (Self.tailRoot.x - local.minX) / local.width,
                                        y: (Self.tailRoot.y - local.minY) / local.height)
        tailLayer.position = CGPoint(x: (Self.tailRoot.x - local.minX) * s, y: (Self.tailRoot.y - local.minY) * s)
        catRoot.addSublayer(tailLayer)
        catRoot.addSublayer(bodyLayer)

        ballLayer.bounds = CGRect(x: 0, y: 0, width: 2 * ballExtent, height: 2 * ballExtent)
        bubbleLayer.anchorPoint = .zero

        for l in [shadowLayer, ballShadowLayer, catRoot, ballLayer, ballGloss, bubbleLayer] { root.addSublayer(l) }
    }

    /// (Re)renders the bitmaps that never change with pose; also needed when the backing scale changes.
    func rebuildStaticImages() {
        setupLayers()
        let scale = backingScale
        for l in [shadowLayer, ballShadowLayer, ballGloss, catRoot, tailLayer, bodyLayer, ballLayer, bubbleLayer] {
            l.contentsScale = scale
        }
        catImageCache.removeAll()
        catImageOrder.removeAll()
        glyphCache.removeAll()
        bodyKey = ""
        bubbleKey = ""
        for i in particles.indices {
            particles[i].layer?.removeFromSuperlayer()
            particles[i].layer = nil
        }
        let s = catScale, local = Self.catLocal
        tailLayer.contents = makeImage(size: tailLayer.bounds.size) { ctx in
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -local.minX, y: -local.minY)
            CatRenderer.drawTail(0)
        }
        let e = ballExtent
        ballLayer.contents = makeImage(size: ballLayer.bounds.size) { _ in
            CatRenderer.drawBall(at: CGPoint(x: e, y: e), radius: ballR, angle: 0, highlight: false)
        }
    }

    func glyphImage(_ glyph: String, _ color: NSColor) -> CGImage? {
        let key = glyph + color.description
        if let g = glyphCache[key] { return g }
        let str = NSAttributedString(string: glyph, attributes: [.font: roundedFont(40, .heavy), .foregroundColor: color])
        let sz = str.size(), side: CGFloat = 56
        let img = makeImage(size: CGSize(width: side, height: side)) { _ in
            str.draw(at: CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2))
        }
        glyphCache[key] = img
        return img
    }

    struct RestLayout {
        var body: CGRect
        var button: CGRect
        var hit: CGRect
        var tailX: CGFloat
        var imageSize: CGSize
        var layerOrigin: CGPoint
        var text: NSAttributedString
        var imageText: CGRect
        var imageButton: CGRect
    }

    func restMessage() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 3
        return NSAttributedString(string: "该休息眼睛了\n出去活动 5 分钟再回来~", attributes: [
            .font: roundedFont(15),
            .foregroundColor: Palette.text,
            .paragraphStyle: style,
        ])
    }

    /// Dialog above the cat, shifted aside when the cat is too close to the top of the screen.
    func restLayout() -> RestLayout? {
        guard restBubble else { return nil }
        let text = restMessage()
        let measured = text.boundingRect(with: CGSize(width: 280, height: 80), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textW = ceil(measured.width), textH = ceil(measured.height)
        let buttonW: CGFloat = 96, buttonH: CGFloat = 28
        let padX: CGFloat = 18, padTop: CGFloat = 14, padBottom: CGFloat = 12, gap: CGFloat = 10
        let w = max(textW, buttonW) + padX * 2
        let h = padTop + textH + gap + buttonH + padBottom

        var x = clamp(catPos.x - w / 2, playArea.minX + 8, playArea.maxX - w - 8)
        var y = headTop + 16
        if y + h > playArea.maxY - 8 || y < catPos.y + 170 * catScale {
            let left = catPos.x - playArea.minX
            let right = playArea.maxX - catPos.x
            if left >= right {
                x = clamp(catPos.x - 70 * catScale - w - 10, playArea.minX + 8, playArea.maxX - w - 8)
            } else {
                x = clamp(catPos.x + 70 * catScale + 10, playArea.minX + 8, playArea.maxX - w - 8)
            }
            y = clamp(headCenter.y - h / 2, playArea.minY + 8, playArea.maxY - h - 8)
        }
        let body = CGRect(x: x, y: y, width: w, height: h)
        let button = CGRect(x: body.midX - buttonW / 2, y: body.minY + padBottom, width: buttonW, height: buttonH)
        let tailX = clamp(catPos.x, body.minX + 18, body.maxX - 18) - body.minX
        let tail = CGRect(x: body.minX + tailX - 10, y: body.minY - 12, width: 20, height: 14)
        let imageBody = CGRect(x: 2, y: 11, width: w, height: h)
        let imageText = CGRect(x: imageBody.minX + padX, y: imageBody.minY + padBottom + buttonH + gap,
                               width: w - padX * 2, height: textH)
        let imageButton = CGRect(x: imageBody.midX - buttonW / 2, y: imageBody.minY + padBottom, width: buttonW, height: buttonH)
        return RestLayout(body: body, button: button, hit: body.union(tail).insetBy(dx: -4, dy: -4),
                          tailX: tailX, imageSize: CGSize(width: w + 4, height: h + 16),
                          layerOrigin: CGPoint(x: x - 2, y: y - 11), text: text, imageText: imageText,
                          imageButton: imageButton)
    }

    func drawRestBubble() {
        guard let layout = restLayout() else {
            bubbleLayer.isHidden = true
            return
        }
        restHit = layout.hit
        restButtonRect = layout.button
        let pressed = restButtonDown && layout.button.contains(mouse)
        let hover = !restButtonDown && layout.button.contains(mouse)
        let key = "rest|\(layout.tailX.rounded())|\(pressed)|\(hover)"
        if key != bubbleKey {
            bubbleKey = key
            bubbleLayer.bounds = CGRect(origin: .zero, size: layout.imageSize)
            bubbleLayer.contents = makeImage(size: layout.imageSize) { _ in
                let r = CGRect(x: 2, y: 11, width: layout.body.width, height: layout.body.height)
                let path = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
                let tx = r.minX + layout.tailX
                let tail = NSBezierPath()
                tail.move(to: P(tx - 8, r.minY + 1))
                tail.line(to: P(tx, r.minY - 10))
                tail.line(to: P(tx + 8, r.minY + 1))
                tail.lineJoinStyle = .round
                NSColor.white.withAlphaComponent(0.98).setFill()
                Palette.outline.setStroke()
                path.lineWidth = 2.5
                path.stroke()
                tail.lineWidth = 2.5
                tail.stroke()
                path.fill()
                tail.fill()
                layout.text.draw(with: layout.imageText, options: [.usesLineFragmentOrigin, .usesFontLeading])
                let button = NSBezierPath(roundedRect: layout.imageButton, xRadius: layout.imageButton.height / 2, yRadius: layout.imageButton.height / 2)
                let fill = pressed ? Palette.furDark : (hover ? NSColor(hex: 0xFFB85C) : Palette.fur)
                fill.setFill()
                button.fill()
                Palette.outline.setStroke()
                button.lineWidth = 1.6
                button.stroke()
                let title = NSAttributedString(string: "我知道了", attributes: [
                    .font: roundedFont(13),
                    .foregroundColor: Palette.text,
                ])
                let sz = title.size()
                title.draw(at: CGPoint(x: layout.imageButton.midX - sz.width / 2, y: layout.imageButton.midY - sz.height / 2))
            }
        }
        bubbleLayer.shadowColor = NSColor.black.cgColor
        bubbleLayer.shadowOpacity = 0.18
        bubbleLayer.shadowRadius = 10
        bubbleLayer.shadowOffset = CGSize(width: 0, height: -2)
        bubbleLayer.isHidden = false
        bubbleLayer.position = layout.layerOrigin
        bubbleLayer.opacity = Float(min(1, (now - restShownAt) / 0.12))
    }

    func render() {
        guard layersReady, let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let s = catScale
        let floor = playArea.minY

        // Cat body bitmap, cached per quantized pose.
        var p = pose
        p.time = 0
        p.tailSwing = 0
        p.pawRaise = quantizedPawRaise(pose.pawRaise)
        p.earTwitch = (pose.earTwitch * 2).rounded() / 2
        p.look = (p.eyes == .open || p.eyes == .surprised)
            ? CGVector(dx: (pose.look.dx * 2).rounded() / 2, dy: (pose.look.dy * 2).rounded() / 2) : .zero
        let key = "\(p.eyes)|\(p.mouth)|\(p.look.dx),\(p.look.dy)|\(p.pawRaise)|\(p.earTwitch)"
        if key != bodyKey {
            bodyKey = key
            if let img = catImageCache[key] {
                bodyLayer.contents = img
                catImageOrder.removeAll { $0 == key }
                catImageOrder.append(key)
            } else if let img = makeImage(size: bodyLayer.bounds.size, { ctx in
                ctx.scaleBy(x: s, y: s)
                ctx.translateBy(x: -Self.catLocal.minX, y: -Self.catLocal.minY)
                CatRenderer.draw(p, includeTail: false)
            }) {
                if catImageOrder.count >= 40 { catImageCache[catImageOrder.removeFirst()] = nil }
                catImageCache[key] = img
                catImageOrder.append(key)
                bodyLayer.contents = img
            }
        }

        let breath = CGFloat(sin(now * (sleeping ? 1.6 : 3.0)))
        bodyLayer.transform = CATransform3DMakeScale(1 + breath * (sleeping ? 0.012 : 0.008),
                                                     1 + breath * (sleeping ? 0.02 : 0.012), 1)
        tailLayer.transform = CATransform3DMakeRotation(-pose.tailSwing * 0.28, 0, 0, 1)
        catRoot.position = CGPoint(x: catPos.x, y: catPos.y + jumpOffset)
        catRoot.transform = CATransform3DMakeScale(facing * (1 + squash), 1 - squash, 1)

        let lift = catPos.y + jumpOffset - floor
        let k = max(0.3, 1 - lift / 400)
        shadowLayer.position = CGPoint(x: catPos.x, y: floor + 2)
        shadowLayer.transform = CATransform3DMakeScale(k, k, 1)
        shadowLayer.opacity = Float(0.13 * k)

        // Ball
        ballLayer.isHidden = !ball.visible
        ballGloss.isHidden = !ball.visible
        ballShadowLayer.isHidden = !ball.visible
        if ball.visible {
            let age = now - ball.appearedAt
            let pop: CGFloat = age < 0.25 ? CGFloat(sin(age / 0.25 * .pi * 0.75)) / 0.7071 : 1
            let sc = max(0.05, min(pop, 1.2))
            ballLayer.position = ball.pos
            ballLayer.transform = CATransform3DScale(CATransform3DMakeRotation(ball.angle, 0, 0, 1), sc, sc, 1)
            ballGloss.position = ball.pos + CGVector(dx: -0.35 * ballR * sc, dy: 0.42 * ballR * sc)
            ballGloss.transform = CATransform3DMakeScale(sc, sc, 1)
            let bk = max(0.3, 1 - (ball.pos.y - floor) / 500)
            ballShadowLayer.position = CGPoint(x: ball.pos.x, y: floor + 2)
            ballShadowLayer.transform = CATransform3DMakeScale(bk, bk, 1)
            ballShadowLayer.opacity = Float(0.15 * bk)
        }

        // Particles
        for i in particles.indices {
            let pt = particles[i]
            let l: CALayer
            if let existing = pt.layer {
                l = existing
            } else {
                l = CALayer()
                l.contentsScale = backingScale
                l.contents = glyphImage(pt.glyph, pt.color)
                l.bounds = CGRect(x: 0, y: 0, width: pt.size * 1.4, height: pt.size * 1.4)
                root.insertSublayer(l, below: bubbleLayer)
                particles[i].layer = l
            }
            let age = now - pt.born
            let fade = CGFloat(age / pt.life)
            let grow = max(0.05, CGFloat(min(1, age / 0.15)))
            l.position = pt.pos
            l.transform = CATransform3DMakeScale(grow, grow, 1)
            l.opacity = Float(1 - fade * fade)
        }

        if restBubble {
            drawRestBubble()
            return
        }
        bubbleLayer.shadowOpacity = 0

        // Speech bubble: bitmap re-rendered only when its text (or tail offset) changes.
        guard let text = bubbleText, now < bubbleUntil else {
            bubbleLayer.isHidden = true
            return
        }
        if cachedBubble?.start != bubbleStart {
            let str = NSAttributedString(string: text, attributes: [.font: roundedFont(14), .foregroundColor: Palette.text])
            cachedBubble = (bubbleStart, str, str.size())
        }
        guard let c = cachedBubble else { return }
        let w = ceil(c.size.width) + 26, h = ceil(c.size.height) + 14
        let x = clamp(catPos.x - w / 2, playArea.minX + 6, playArea.maxX - w - 6)
        let y = min(headTop + 14, bounds.maxY - h - 4)
        let tailX = (clamp(catPos.x, x + 16, x + w - 16) - x).rounded()
        let bKey = "\(bubbleStart)|\(tailX)"
        if bKey != bubbleKey {
            bubbleKey = bKey
            bubbleLayer.bounds = CGRect(x: 0, y: 0, width: w + 4, height: h + 14)
            bubbleLayer.contents = makeImage(size: bubbleLayer.bounds.size) { _ in
                let r = CGRect(x: 2, y: 11, width: w, height: h)
                let path = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
                let tx = r.minX + tailX
                let tail = NSBezierPath()
                tail.move(to: P(tx - 7, r.minY + 1)); tail.line(to: P(tx, r.minY - 9)); tail.line(to: P(tx + 7, r.minY + 1))
                tail.lineJoinStyle = .round
                NSColor.white.withAlphaComponent(0.97).setFill()
                Palette.outline.setStroke()
                path.lineWidth = 2; path.stroke()
                tail.lineWidth = 2; tail.stroke()
                path.fill(); tail.fill()
                c.str.draw(at: CGPoint(x: r.minX + 13, y: r.minY + 7))
            }
        }
        bubbleLayer.isHidden = false
        bubbleLayer.position = CGPoint(x: x - 2, y: y - 11)
        bubbleLayer.opacity = Float(min(1, (now - bubbleStart) / 0.12, (bubbleUntil - now) / 0.3))
    }
}

// MARK: - Menu

/// Status-item row with a label and an NSSwitch. A plain menu item can only show a checkmark.
final class RestSwitchRow: NSView {
    let label = NSTextField(labelWithString: "休息提醒")
    let toggle = NSSwitch()

    init(isOn: Bool, target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        addSubview(label)
        addSubview(toggle)
        layoutManual()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        layoutManual()
    }

    /// Menu tracking delivers the click to the row, not the switch control inside it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        toggle.state = toggle.state == .on ? .off : .on
        if let action = toggle.action {
            NSApp.sendAction(action, to: toggle.target, from: toggle)
        }
    }

    func layoutManual() {
        let sw = toggle.fittingSize
        toggle.frame = NSRect(x: bounds.width - sw.width - 16, y: (bounds.height - sw.height) / 2, width: sw.width, height: sw.height)
        label.sizeToFit()
        label.frame = NSRect(x: 18, y: (bounds.height - label.frame.height) / 2,
                             width: max(40, toggle.frame.minX - 26), height: label.frame.height)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var game: GameView!
    var statusItem: NSStatusItem!
    var soundItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screen = NSScreen.main ?? NSScreen.screens[0]

        // A non-activating panel so clicking the cat never steals focus from the user's current app.
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        game = GameView(frame: CGRect(origin: .zero, size: screen.frame.size))
        game.hostWindow = panel
        panel.contentView = game
        game.layout(for: screen)
        panel.orderFrontRegardless()
        game.start()

        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        let menu = NSMenu()
        menu.addItem(withTitle: "丢毛线球", action: #selector(throwBall), keyEquivalent: "").target = self
        menu.addItem(withTitle: "睡觉 / 叫醒", action: #selector(toggleSleep), keyEquivalent: "").target = self
        menu.addItem(withTitle: "回到右下角", action: #selector(resetPosition), keyEquivalent: "").target = self
        let restItem = NSMenuItem()
        restItem.view = RestSwitchRow(isOn: game.restReminderOn, target: self, action: #selector(toggleRestReminder(_:)))
        menu.addItem(restItem)
        soundItem = menu.addItem(withTitle: "音效", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = .on
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出橘猫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func throwBall() { game.menuThrow() }
    @objc func toggleSleep() { game.toggleSleep() }
    @objc func resetPosition() { game.menuResetPosition() }
    @objc func toggleRestReminder(_ sender: NSSwitch) {
        game.setRestReminderOn(sender.state == .on)
    }
    @objc func toggleSound() {
        game.soundOn.toggle()
        soundItem.state = game.soundOn ? .on : .off
    }
    @objc func screensChanged() {
        game.layout(for: NSScreen.main ?? NSScreen.screens[0])
    }
}

// MARK: - Icon rendering (used by build.sh)

enum IconRenderer {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let specs: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in specs {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: px, height: px)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            drawIcon(size: CGFloat(px))
            NSGraphicsContext.restoreGraphicsState()
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            }
        }
    }

    static func drawIcon(size: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = size * 0.1
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
        NSGradient(starting: NSColor(hex: 0xFFF6E6), ending: NSColor(hex: 0xFFD49A))?.draw(in: bg, angle: -90)

        ctx.saveGState()
        bg.addClip()
        let s = rect.width / 270
        let origin = CGPoint(x: rect.midX - rect.width * 0.04, y: rect.minY + rect.height * 0.07)
        NSColor.black.withAlphaComponent(0.12).setFill()
        oval(origin.x, origin.y + 2 * s, 130 * s, 14 * s).fill()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: s, y: s)
        var pose = CatPose()
        pose.eyes = .happy
        pose.mouth = .open
        pose.pawRaise = 1
        pose.tailSwing = 0.4
        CatRenderer.draw(pose)
        let paw = CatRenderer.pawPoint(1)
        CatRenderer.drawBall(at: CGPoint(x: paw.x, y: paw.y + 10 + 18), radius: 21, angle: 0.4)
        ctx.restoreGState()
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--render-icon" {
    IconRenderer.render(to: args[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
