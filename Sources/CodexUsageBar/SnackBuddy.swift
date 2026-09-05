import SwiftUI

struct SnackBuddy: View {
    let remaining: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let low = remaining > 0 && remaining < 20
                let full = remaining >= 50
                let asleep = remaining == 0
                let ink = Color(red: 0.12, green: 0.06, blue: 0.22)
                let lime = Color(red: 0.65, green: 0.95, blue: 0.40)
                let pink = Color(red: 1, green: 0.35, blue: 0.64)
                let cyan = Color(red: 0.30, green: 0.88, blue: 1)
                let skin = asleep ? Color.purple : low ? pink : lime
                let bounce = reduceMotion ? 0 : sin(t * (low ? 22 : full ? 4 : 2)) * (low ? 3 : full ? 5 : 2)
                let x = size.width / 2 + (low && !reduceMotion ? sin(t * 29) * 4 : 0)
                let y = size.height / 2 + bounce + 5
                func ellipse(_ rect: CGRect, _ color: Color) {
                    canvas.fill(Path(ellipseIn: rect), with: .color(color))
                }
                func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat) {
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    canvas.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                ellipse(CGRect(x: size.width / 2 - 40, y: size.height - 14, width: 80, height: 8), .black.opacity(0.25))
                for side in [-1.0, 1.0] {
                    // Candy-colored horns, little feet, and waving arms.
                    var horn = Path()
                    horn.move(to: CGPoint(x: x + side * 18, y: y - 33))
                    horn.addQuadCurve(to: CGPoint(x: x + side * 36, y: y - 57), control: CGPoint(x: x + side * 36, y: y - 37))
                    horn.addLine(to: CGPoint(x: x + side * 38, y: y - 24))
                    horn.closeSubpath()
                    canvas.fill(horn, with: .color(side < 0 ? pink : cyan))
                    ellipse(CGRect(x: x + side * 24 - 10, y: y + 35, width: 20, height: 12), skin)
                    let wave = reduceMotion ? 0 : sin(t * (low ? 17 : 4) + side) * (low ? 15 : 5)
                    if !low {
                        line(CGPoint(x: x + side * 38, y: y + 5), CGPoint(x: x + side * 58, y: y + 12 + wave), skin, 9)
                        ellipse(CGRect(x: x + side * 58 - 6, y: y + 6 + wave, width: 12, height: 12), skin)
                    }
                }
                let body = Path(roundedRect: CGRect(x: x - 43, y: y - 36, width: 86, height: 78), cornerRadius: full ? 34 : 27)
                canvas.fill(body, with: .linearGradient(Gradient(colors: [skin, asleep ? .purple : low ? .orange : Color(red: 0.28, green: 0.76, blue: 0.50)]), startPoint: CGPoint(x: x, y: y - 36), endPoint: CGPoint(x: x, y: y + 42)))
                for side in [-1.0, 1.0] {
                    let ex = x + side * 17
                    let blink = asleep || (!reduceMotion && t.truncatingRemainder(dividingBy: 4) < 0.15)
                    if blink {
                        line(CGPoint(x: ex - 7, y: y - 9), CGPoint(x: ex + 7, y: y - 9), ink, 3)
                    } else {
                        ellipse(CGRect(x: ex - 11, y: y - 24, width: 22, height: low ? 29 : 25), Color(red: 1, green: 0.98, blue: 0.87))
                        ellipse(CGRect(x: ex - 4 + (low ? sin(t * 10) * 2 : 0), y: y - 16, width: 8, height: 12), ink)
                        ellipse(CGRect(x: ex - 2, y: y - 15, width: 3, height: 3), .white)
                    }
                    ellipse(CGRect(x: ex - 10, y: y + 5, width: 16, height: 7), pink.opacity(0.65))
                }
                let mouth = CGRect(x: x - (low ? 12 : 17), y: y + 10, width: low ? 24 : 34, height: asleep ? 6 : low ? 25 : 19)
                canvas.fill(Path(roundedRect: mouth, cornerRadius: 10), with: .color(ink))
                if !asleep {
                    for side in [-1.0, 1.0] {
                        var fang = Path()
                        fang.move(to: CGPoint(x: x + side * 8 - 3, y: y + 10))
                        fang.addLine(to: CGPoint(x: x + side * 8 + 3, y: y + 10))
                        fang.addLine(to: CGPoint(x: x + side * 8, y: y + 18))
                        fang.closeSubpath()
                        canvas.fill(fang, with: .color(.white))
                    }
                    ellipse(CGRect(x: x - 7, y: mouth.maxY - 7, width: 14, height: 5), pink)
                }
                if low {
                    // Forearms meet in front of the belly; palms slide in opposite directions.
                    let rub = reduceMotion ? 0 : sin(t * 19) * 4
                    for side in [-1.0, 1.0] {
                        let handY = y + 28 + side * rub
                        var arm = Path()
                        arm.move(to: CGPoint(x: x + side * 39, y: y + 5))
                        arm.addQuadCurve(to: CGPoint(x: x + side * 4, y: handY),
                                         control: CGPoint(x: x + side * 33, y: y + 39))
                        canvas.stroke(arm, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        canvas.stroke(arm, with: .color(skin), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        ellipse(CGRect(x: x + side * 4 - 6, y: handY - 9, width: 12, height: 18), Color(red: 1, green: 0.65, blue: 0.65))
                        for finger in 0..<2 {
                            line(CGPoint(x: x + side * 4 - 3, y: handY + Double(finger) * 4),
                                 CGPoint(x: x + side * 4 + 3, y: handY + Double(finger) * 4), ink.opacity(0.45), 1)
                        }
                    }
                    for i in 0..<3 {
                        let phase = reduceMotion ? Double(i) / 3 : (t * 1.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let dx = x + 52 + Double(i % 2) * 12
                        let dy = y - 39 + phase * 49
                        var drop = Path()
                        drop.move(to: CGPoint(x: dx, y: dy - 7))
                        drop.addQuadCurve(to: CGPoint(x: dx, y: dy + 5), control: CGPoint(x: dx + 9, y: dy + 5))
                        drop.addQuadCurve(to: CGPoint(x: dx, y: dy - 7), control: CGPoint(x: dx - 9, y: dy + 5))
                        canvas.fill(drop, with: .color(cyan.opacity(1 - phase * 0.6)))
                    }
                } else {
                    canvas.draw(Text(asleep ? "z Z" : full ? "✦" : "·").font(.system(size: 23, weight: .bold)).foregroundColor(asleep ? cyan : pink),
                                at: CGPoint(x: x + 64, y: y - 37 - (reduceMotion ? 0 : sin(t * 2) * 4)))
                }
            }
        }
        .accessibilityLabel(remaining == 0 ? "Sleeping monster" : remaining < 20 ? "Hungry monster rubbing its hands and sweating" : remaining < 50 ? "Peckish monster" : "Happy, full monster bouncing")
    }
}
