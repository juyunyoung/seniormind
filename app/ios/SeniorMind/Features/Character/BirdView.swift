import SwiftUI
import Observation

// 아기 새 캐릭터. 시안 "기억이, 두 가지 모습"(11/2)의 그리기·동작 값을 그대로 옮겼다.
// 값의 원본: 앱 계획서 v0.3.3 1.4 (포즈·날개·몸 동작 표). Android도 같은 값을 쓴다.

/// 표정 포즈(시안 `poses`).
struct BirdPose: Equatable, Sendable {
    var eye: Double, smile: Double, brow: Double, open: Double, blush: Double

    static let neutral = BirdPose(eye: 1, smile: 0, brow: 0, open: 0, blush: 0.12)
    static let happy = BirdPose(eye: 0.04, smile: 1, brow: 0, open: 0.12, blush: 0.38)
    static let empathy = BirdPose(eye: 0.82, smile: 0, brow: 1, open: 0, blush: 0.15)
    static let surprised = BirdPose(eye: 1.22, smile: 0, brow: -0.65, open: 0.72, blush: 0.12)

    static func of(_ e: Expression) -> BirdPose {
        switch e { case .neutral: .neutral; case .happy: .happy; case .empathy: .empathy; case .surprised: .surprised }
    }
    static func mix(_ a: BirdPose, _ b: BirdPose, _ t: Double) -> BirdPose {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return .init(eye: m(a.eye, b.eye), smile: m(a.smile, b.smile), brow: m(a.brow, b.brow),
                     open: m(a.open, b.open), blush: m(a.blush, b.blush))
    }
}

/// 몸 전체(얼굴·날개 포함) 늘이기·줄이기·점프. x·y는 배율, lift는 캐릭터 높이 대비 점프 높이.
struct BodyMotion: Equatable, Sendable {
    var x = 1.0, y = 1.0, lift = 0.0
    static let rest = BodyMotion()
}

enum BirdMotion {
    /// 시안 `bodyFrames`: [초, 가로 배율, 세로 배율, 점프 높이]
    static let frames: [Expression: [(Double, Double, Double, Double)]] = [
        .happy: [(0, 1, 1, 0), (0.12, 1.1, 0.9, 0), (0.23, 0.94, 1.13, 0.035),
                 (0.4, 0.98, 1.05, 0.12), (0.58, 1, 1, 0.045), (0.68, 1.12, 0.87, 0), (0.82, 1, 1, 0)],
        .surprised: [(0, 1, 1, 0), (0.1, 1.06, 0.94, 0), (0.27, 0.9, 1.2, 0.035),
                     (0.5, 0.96, 1.08, 0.015), (0.72, 1.04, 0.96, 0), (1, 1, 1, 0)],
        .empathy: [(0, 1, 1, 0), (0.42, 1.045, 0.94, 0), (0.9, 0.98, 1.025, 0), (1.65, 1, 1, 0)],
    ]

    static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// 시안 `reactionMotion`. 기쁨은 3번 콩콩(회차마다 15% 약하게), 나머지는 1회.
    static func body(_ e: Expression, elapsed: Double, reduced: Bool) -> BodyMotion {
        guard !reduced, e != .neutral, let f = frames[e], let duration = f.last?.0 else { return .rest }
        let hop = e == .happy ? Int(elapsed / duration) : 0
        if hop >= 3 || (e != .happy && elapsed >= duration) { return .rest }
        let time = e == .happy ? elapsed.truncatingRemainder(dividingBy: duration) : elapsed
        guard let end = f.firstIndex(where: { $0.0 >= time }), end > 0 else { return .rest }
        let a = f[end - 1], b = f[end]
        let ease = smooth((time - a.0) / (b.0 - a.0))
        let strength = e == .happy ? 1 - Double(hop) * 0.15 : 1
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * ease }
        return BodyMotion(x: 1 + (mix(a.1, b.1) - 1) * strength,
                          y: 1 + (mix(a.2, b.2) - 1) * strength,
                          lift: mix(a.3, b.3) * strength)
    }

    /// 시안 `wingReaction`: (각도, 길이). 공감은 날개를 모은 채 유지.
    static func wing(_ e: Expression, elapsed: Double, reduced: Bool) -> (angle: Double, length: Double) {
        if e == .empathy { return (-Double.pi / 2, 1.35) }
        if reduced || e == .neutral { return (0, 1) }
        let flaps = e == .happy ? 2.0 : 1.0
        let duration = e == .happy ? 0.7 : 0.9
        let time = elapsed - 0.16
        if time <= 0 || time >= flaps * duration { return (0, 1) }
        return (pow(sin(.pi * time / duration), 2) * 2.25, 1)
    }
}

/// 표정·동작 상태. 화면 갱신마다 frame(at:)으로 다음 값을 계산한다.
@Observable @MainActor
final class BirdModel {
    private(set) var expression: Expression = .neutral
    @ObservationIgnored private var from = BirdPose.neutral
    @ObservationIgnored private var target = BirdPose.neutral
    @ObservationIgnored private var current = BirdPose.neutral
    @ObservationIgnored private var changedAt = Date.distantPast
    @ObservationIgnored private var motionFrom = BodyMotion.rest
    @ObservationIgnored private var motion = BodyMotion.rest
    @ObservationIgnored private var wingAngle = 0.0
    @ObservationIgnored private var wingLength = 1.0
    @ObservationIgnored private var mouth = 0.0
    @ObservationIgnored private var lastTick = Date.now
    /// 0~1. 기억이가 말하는 음량(또는 말하는 중 신호). 입 움직임에 쓴다.
    @ObservationIgnored var mouthLevel: () -> Double = { 0 }

    /// 화면의 @State 기본값으로도 만들 수 있게 격리 없는 생성자.
    nonisolated init() {}

    /// intensity < 1이면 기본 표정 쪽으로 약하게(놀람 → 0.65).
    func setExpression(_ e: Expression, intensity: Double = 1) {
        expression = e
        from = current
        target = BirdPose.mix(.neutral, .of(e), intensity)
        motionFrom = motion
        changedAt = .now
    }

    struct Frame: Sendable {
        var pose: BirdPose, blink: Double, mouth: Double
        var wingAngle: Double, wingLength: Double
        var body: BodyMotion, breath: Double
    }

    func frame(at now: Date, reduceMotion reduced: Bool) -> Frame {
        let dt = min(0.05, max(0.001, now.timeIntervalSince(lastTick))); lastTick = now
        let elapsed = now.timeIntervalSince(changedAt)
        let t = min(1, elapsed / (reduced ? 0.001 : 0.52))
        current = BirdPose.mix(from, target, BirdMotion.smooth(t))

        let next = BirdMotion.body(expression, elapsed: elapsed, reduced: reduced)
        let blend = min(1, elapsed / 0.14)
        motion = BodyMotion(x: motionFrom.x + (next.x - motionFrom.x) * blend,
                            y: motionFrom.y + (next.y - motionFrom.y) * blend,
                            lift: motionFrom.lift + (next.lift - motionFrom.lift) * blend)

        let w = BirdMotion.wing(expression, elapsed: elapsed, reduced: reduced)
        let k = reduced ? 1 : 1 - exp(-dt / 0.08)
        wingAngle += (w.angle - wingAngle) * k
        wingLength += (w.length - wingLength) * k

        mouth += (mouthLevel() - mouth) * (1 - exp(-dt / 0.065))
        let s = now.timeIntervalSinceReferenceDate
        let blinkPhase = (s * 1000).truncatingRemainder(dividingBy: 4700) / 180
        let blink = !reduced && blinkPhase < 1 ? pow(sin(.pi * blinkPhase), 2) : 0
        let breath = reduced ? 0 : sin(s * 1.7) * 0.006
        return Frame(pose: current, blink: blink, mouth: mouth, wingAngle: wingAngle, wingLength: wingLength,
                     body: motion, breath: breath)
    }
}

/// 몸·날개 이미지 위에 눈·볼·부리를 코드로 그린다. 좌표계는 시안 캔버스(1100×1100) 그대로.
/// 몸 동작은 캔버스 안이 아니라 뷰 전체에 적용해 머리·깃이 잘리지 않게 한다.
struct BirdView: View {
    let model: BirdModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: false)) { timeline in
            let f = model.frame(at: timeline.date, reduceMotion: reduceMotion)
            Canvas { ctx, size in Self.draw(&ctx, size: size, frame: f) }
                .scaleEffect(x: f.body.x, y: f.body.y + f.breath, anchor: UnitPoint(x: 0.5, y: 0.85))
                .visualEffect { content, proxy in content.offset(y: -f.body.lift * 0.85 * proxy.size.height) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(model.expression.title) 표정의 기억이")
    }

    private static let bodyImage = Image("bird-motion-body")
    private static let wingImage = Image("bird-wing")

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, frame f: BirdModel.Frame) {
        ctx.scaleBy(x: size.width / 1100, y: size.height / 1100)
        ctx.translateBy(x: 50, y: 20)
        ctx.draw(bodyImage, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        drawWing(&ctx, side: -1, f)
        drawWing(&ctx, side: 1, f)
        ctx.translateBy(x: 0, y: 101)
        drawFeatures(&ctx, f)
    }

    /// 시안 `drawWing`: 어깨를 고정한 채 회전하고, 어깨→끝 축 방향으로만 늘린다.
    private static func drawWing(_ ctx: inout GraphicsContext, side: Double, _ f: BirdModel.Frame) {
        var w = ctx
        w.translateBy(x: side < 0 ? 250 : 750, y: 560)
        if side > 0 { w.scaleBy(x: -1, y: 1) }
        w.rotate(by: .radians(f.wingAngle))
        let axis = atan2(184.0, -106.0)
        w.rotate(by: .radians(axis))
        w.scaleBy(x: f.wingLength, y: 1)
        w.rotate(by: .radians(-axis))
        w.draw(wingImage, in: CGRect(x: -146, y: -36, width: 190, height: 254))
    }

    /// 시안 `drawFeatures(kind: bird)`.
    private static func drawFeatures(_ ctx: inout GraphicsContext, _ f: BirdModel.Frame) {
        let p = f.pose
        let cy = 359.0
        for side in [-1.0, 1.0] {
            let x = 500 + side * 106
            // 볼
            let bc = CGPoint(x: x + side * 27, y: cy + 71)
            ctx.fill(Path(CGRect(x: x - 65, y: cy + 20, width: 130, height: 105)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xDA8B56, opacity: p.blush), Color(hex: 0xDA8B56, opacity: 0)]),
                                           center: bc, startRadius: 1, endRadius: 51))
            // 눈
            let openness = max(0.025, p.eye * (1 - f.blink))
            let eyeH = 42 * openness
            var eye = ctx
            eye.translateBy(x: x, y: cy)
            if openness > 0.09 {
                eye.fill(Path(ellipseIn: CGRect(x: -29, y: -eyeH, width: 58, height: eyeH * 2)),
                         with: .linearGradient(Gradient(stops: [
                            .init(color: Color(hex: 0x66533F), location: 0),
                            .init(color: Color(hex: 0x342B22), location: 0.42),
                            .init(color: Color(hex: 0x241F1A), location: 1)]),
                            startPoint: CGPoint(x: -25, y: -eyeH), endPoint: CGPoint(x: 20, y: eyeH)))
                eye.fill(Path(ellipseIn: CGRect(x: 1 - 22, y: 3 - eyeH * 0.82, width: 44, height: eyeH * 1.64)),
                         with: .color(Color(hex: 0x1F1C19)))
                var gloss = eye
                gloss.opacity = min(1, openness * 1.5) * (1 - p.smile * 0.8)
                let gh = min(10, eyeH * 0.24)
                gloss.fill(Path(ellipseIn: CGRect(x: -16, y: -eyeH * 0.38 - gh, width: 16, height: gh * 2)),
                           with: .color(Color(hex: 0xFFFAF0)))
                gloss.opacity *= 0.45
                gloss.fill(Path(ellipseIn: CGRect(x: 10 - 3.5, y: eyeH * 0.43 - 4, width: 7, height: 8)),
                           with: .color(Color(hex: 0xFFFAF0)))
            }
            // 웃는 눈(감은 눈)
            if p.smile > 0.05 || openness <= 0.09 {
                var smile = eye
                smile.opacity = openness <= 0.09 ? 1 : p.smile
                var path = Path()
                path.move(to: CGPoint(x: -27, y: 3))
                path.addQuadCurve(to: CGPoint(x: 27, y: 3), control: CGPoint(x: 0, y: -34 * p.smile))
                smile.stroke(path, with: .color(Color(hex: 0x403A2B)),
                             style: StrokeStyle(lineWidth: p.smile > 0.05 ? 18 : 8, lineCap: .round))
            }
            // 눈썹
            var brow = ctx
            brow.opacity = min(0.75, abs(p.brow) * 0.8)
            var bp = Path()
            bp.move(to: CGPoint(x: x - 25, y: cy - 66 - side * p.brow * 12))
            bp.addQuadCurve(to: CGPoint(x: x + 25, y: cy - 66 + side * p.brow * 12), control: CGPoint(x: x, y: cy - 73))
            brow.stroke(bp, with: .color(Color(hex: 0x726E4E)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }

        // 부리·입
        let open = min(1, p.open + f.mouth * 0.8)
        var m = ctx
        m.translateBy(x: 500, y: 430)
        let mouthH = 6 + open * 29
        m.fill(Path(ellipseIn: CGRect(x: -31, y: 14 + open * 16 - mouthH, width: 62, height: mouthH * 2)), with: .color(Color(hex: 0x664327)))
        if open > 0.2 {
            m.fill(Path(ellipseIn: CGRect(x: -16, y: 24 + open * 22 - 6, width: 32, height: 12)), with: .color(Color(hex: 0xCF9870)))
        }
        var upper = Path()
        upper.move(to: CGPoint(x: -35, y: 6))
        upper.addQuadCurve(to: CGPoint(x: 0, y: -25), control: CGPoint(x: -24, y: -26))
        upper.addQuadCurve(to: CGPoint(x: 35, y: 6), control: CGPoint(x: 24, y: -26))
        upper.addQuadCurve(to: CGPoint(x: -35, y: 6), control: CGPoint(x: 0, y: 24))
        m.fill(upper, with: .linearGradient(Gradient(stops: [
            .init(color: Color(hex: 0xF2CF8E), location: 0), .init(color: Color(hex: 0xDBA856), location: 0.5),
            .init(color: Color(hex: 0xAF7939), location: 1)]), startPoint: CGPoint(x: -30, y: -26), endPoint: CGPoint(x: 20, y: 20)))
        var lower = Path()
        lower.move(to: CGPoint(x: -29, y: 15 + open * 35))
        lower.addQuadCurve(to: CGPoint(x: 29, y: 15 + open * 35), control: CGPoint(x: 0, y: 37 + open * 34))
        lower.addQuadCurve(to: CGPoint(x: -29, y: 15 + open * 35), control: CGPoint(x: 0, y: 25 + open * 35))
        m.fill(lower, with: .linearGradient(Gradient(colors: [Color(hex: 0xEDC37A), Color(hex: 0xB68642)]),
                                            startPoint: CGPoint(x: 0, y: 15), endPoint: CGPoint(x: 0, y: 40 + open * 25)))
        var nostril = m
        nostril.opacity = 0.55
        for nx in [-12.0, 12.0] {
            nostril.fill(Path(ellipseIn: CGRect(x: nx - 2.5, y: -7 - 1.7, width: 5, height: 3.4)), with: .color(Color(hex: 0x9C763E)))
        }
    }
}
